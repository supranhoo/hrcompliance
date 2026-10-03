-- 0003 Identity, roles, permissions, scope.
-- Flow: Google login -> auth.users -> (trigger links by email) -> app_user -> roles -> scope -> permissions.
-- A Google account with NO pre-provisioned app_user row gets no app_user link, so every RLS check fails closed.
-- Rollback: drop table user_scope, user_role, role_permission, permission, role, app_user cascade; drop trigger on auth.users.

create table public.app_user (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique,                      -- set on first successful Google login
  email extensions.citext not null unique,
  full_name text,
  status text not null default 'invited' check (status in ('invited','active','disabled')),
  scope_all boolean not null default false,      -- true = unrestricted entity/location scope
  employee_code text,                            -- optional link to Employee master (added in Phase 5)
  last_login_at timestamptz,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);

create table public.role (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null, description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);

create table public.permission (
  code text primary key check (code ~ '^[a-z_]+\.[a-z_]+$'),
  module text not null, description text
);

create table public.role_permission (
  role_id uuid not null references public.role(id) on delete cascade,
  permission_code text not null references public.permission(code) on delete cascade,
  primary key (role_id, permission_code)
);

create table public.user_role (
  user_id uuid not null references public.app_user(id) on delete cascade,
  role_id uuid not null references public.role(id) on delete restrict,
  assigned_at timestamptz not null default now(), assigned_by uuid,
  primary key (user_id, role_id)
);

create table public.user_scope (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_user(id) on delete cascade,
  scope_type text not null check (scope_type in ('entity','location','department')),
  scope_id uuid not null,
  unique (user_id, scope_type, scope_id)
);
create index user_scope_user_idx on public.user_scope(user_id);

create trigger app_user_stamp before insert or update on public.app_user for each row execute function app.stamp_row();
create trigger role_stamp before insert or update on public.role for each row execute function app.stamp_row();

-- ---- authorization helpers (SECURITY DEFINER, fixed search_path; read-only) ----
create or replace function app.current_user_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.app_user where auth_user_id = auth.uid() and status = 'active'
$$;

create or replace function app.has_permission(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.app_user u
    join public.user_role ur on ur.user_id = u.id
    join public.role_permission rp on rp.role_id = ur.role_id
    where u.auth_user_id = auth.uid() and u.status = 'active' and rp.permission_code = p_code)
$$;

-- True if the current user may act on a record of the given entity/location.
-- Location scope wins; an entity-scope grant covers all locations of that entity.
create or replace function app.in_scope(p_entity uuid, p_location uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_user u
    where u.auth_user_id = auth.uid() and u.status = 'active'
      and (u.scope_all
        or exists (select 1 from public.user_scope s where s.user_id = u.id and (
              (s.scope_type = 'entity'   and s.scope_id = p_entity)
           or (s.scope_type = 'location' and s.scope_id = p_location)))))
$$;

-- Link a first-time Google login to a pre-provisioned app_user (matched on verified email).
create or replace function app.link_auth_user() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  update public.app_user
     set auth_user_id = new.id,
         status = case when status = 'invited' then 'active' else status end,
         full_name = coalesce(full_name, new.raw_user_meta_data ->> 'full_name'),
         last_login_at = now()
   where email = new.email::extensions.citext and auth_user_id is null;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function app.link_auth_user();

-- Client bootstrap: who am I, what can I do. Returns empty for unprovisioned users.
create or replace function public.my_access() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
      'user_id', u.id, 'email', u.email, 'full_name', u.full_name, 'scope_all', u.scope_all,
      'roles', coalesce((select jsonb_agg(r.code order by r.code) from public.user_role ur join public.role r on r.id=ur.role_id where ur.user_id=u.id), '[]'::jsonb),
      'permissions', coalesce((select jsonb_agg(distinct rp.permission_code order by rp.permission_code) from public.user_role ur join public.role_permission rp on rp.role_id=ur.role_id where ur.user_id=u.id), '[]'::jsonb),
      'scopes', coalesce((select jsonb_agg(jsonb_build_object('type',s.scope_type,'id',s.scope_id)) from public.user_scope s where s.user_id=u.id), '[]'::jsonb))
    from public.app_user u where u.auth_user_id = auth.uid() and u.status = 'active'), '{}'::jsonb)
$$;
revoke all on function public.my_access() from public, anon;
grant execute on function public.my_access() to authenticated;
