-- 0033 Users, roles, permissions and scope administration (backend).
-- Permissions stay the single source of truth: the same role_permission rows feed my_access() (UI visibility) and app.has_permission() (RLS), so nothing here hardcodes a role name.
-- New permission role.admin separates "who may edit what roles can do / who holds which role" from user.admin ("who is a user, active or not, and which locations they see"),
-- so granting user administration to e.g. HEAD_HR cannot become self-promotion. Only SUPER_ADMIN holds role.admin by default.
-- Guards are triggers, so they hold for every path (API, RPC, SQL editor): (1) continuity - at least one active, signed-in user must keep role.admin, checked at commit so a
-- multi-row change that ends valid is allowed; (2) self-lockout - removing your own user.admin / role.admin, or disabling yourself, needs an explicit confirmation flag that only the RPCs set;
-- (3) role codes and linked emails are immutable. Role/user changes go through reason-mandatory, audited RPCs (SECURITY INVOKER: RLS and table audit triggers still apply).
-- Department scope rows are not enforced by app.in_scope today, so the admin RPCs manage entity and location scope only.
-- Rollback: drop the RPCs and views below; drop triggers *_continuity/*_selflock/role_code_immutable/app_user_identity_guard; restore policies role_mod, role_permission_mod, user_role_mod to user.admin; delete role.admin from permission.
insert into public.permission(code, module, description) values ('role.admin', 'user', 'Administer roles, role permissions and role assignments') on conflict do nothing;
insert into public.role_permission(role_id, permission_code) select id, 'role.admin' from public.role where code = 'SUPER_ADMIN' on conflict do nothing;

drop policy role_mod on public.role;
create policy role_mod on public.role for all to authenticated
  using (app.has_permission('role.admin') and not is_system) with check (app.has_permission('role.admin') and not is_system);
drop policy role_permission_mod on public.role_permission;
create policy role_permission_mod on public.role_permission for all to authenticated
  using (app.has_permission('role.admin')) with check (app.has_permission('role.admin'));
drop policy user_role_mod on public.user_role;
create policy user_role_mod on public.user_role for all to authenticated
  using (app.has_permission('role.admin')) with check (app.has_permission('role.admin'));

-- ---- guards ----
create or replace function app.admin_holders() returns bigint language sql stable security definer set search_path = public as $$
  select count(distinct u.id) from public.app_user u join public.user_role ur on ur.user_id = u.id join public.role_permission rp on rp.role_id = ur.role_id
   where u.status = 'active' and u.auth_user_id is not null and rp.permission_code = 'role.admin'
$$;
revoke all on function app.admin_holders() from public, anon, authenticated;

create or replace function app.guard_continuity() returns trigger language plpgsql security definer set search_path = public as $$
declare lost boolean := false;
begin
  if tg_table_name = 'user_role' then
    lost := tg_op in ('DELETE','UPDATE') and exists (select 1 from public.role_permission rp where rp.role_id = old.role_id and rp.permission_code = 'role.admin');
  elsif tg_table_name = 'role_permission' then
    lost := tg_op in ('DELETE','UPDATE') and old.permission_code = 'role.admin';
  elsif tg_table_name = 'app_user' then
    lost := tg_op in ('DELETE','UPDATE') and old.status = 'active' and old.auth_user_id is not null and (tg_op = 'DELETE' or new.status <> 'active' or new.auth_user_id is null);
  end if;
  if lost and app.admin_holders() = 0 then
    raise exception 'at least one active user must keep role administration (role.admin); this change would leave none' using errcode = 'AD001';
  end if;
  return null;
end $$;
create constraint trigger user_role_continuity after update or delete on public.user_role deferrable initially deferred for each row execute function app.guard_continuity();
create constraint trigger role_permission_continuity after update or delete on public.role_permission deferrable initially deferred for each row execute function app.guard_continuity();
create constraint trigger app_user_continuity after update or delete on public.app_user deferrable initially deferred for each row execute function app.guard_continuity();

-- Permissions the caller holds, optionally ignoring one role (what would remain after removing it).
create or replace function app.actor_perms(p_without_role uuid default null) returns setof text language sql stable security definer set search_path = public as $$
  select distinct rp.permission_code from public.app_user u join public.user_role ur on ur.user_id = u.id join public.role_permission rp on rp.role_id = ur.role_id
   where u.auth_user_id = auth.uid() and u.status = 'active' and ur.role_id is distinct from p_without_role
$$;
revoke all on function app.actor_perms(uuid) from public, anon, authenticated;

create or replace function app.guard_selflock() returns trigger language plpgsql security definer set search_path = public as $$
declare actor uuid := app.current_user_id(); crit constant text[] := array['user.admin','role.admin']; lost text[];
begin
  if actor is null or current_setting('app.confirm_self_lockout', true) = 'yes' then return coalesce(new, old); end if;
  if tg_table_name = 'user_role' then
    if old.user_id <> actor then return coalesce(new, old); end if;
    select array_agg(rp.permission_code) into lost from public.role_permission rp where rp.role_id = old.role_id and rp.permission_code = any(crit)
      and rp.permission_code not in (select * from app.actor_perms(old.role_id));
  elsif tg_table_name = 'role_permission' then
    if old.permission_code <> all(crit) or not exists (select 1 from public.user_role ur where ur.user_id = actor and ur.role_id = old.role_id) then return coalesce(new, old); end if;
    select array_agg(old.permission_code) into lost where old.permission_code not in (select * from app.actor_perms(old.role_id));
  elsif tg_table_name = 'app_user' then
    if old.id = actor and (tg_op = 'DELETE' or new.status <> 'active') then lost := array['your own access']; end if;
  end if;
  if coalesce(cardinality(lost), 0) > 0 then
    raise exception 'this change removes your own administrative access (%): confirm explicitly to proceed', array_to_string(lost, ', ') using errcode = 'AD002';
  end if;
  return coalesce(new, old);
end $$;
create trigger user_role_selflock before update or delete on public.user_role for each row execute function app.guard_selflock();
create trigger role_permission_selflock before update or delete on public.role_permission for each row execute function app.guard_selflock();
create trigger app_user_selflock before update or delete on public.app_user for each row execute function app.guard_selflock();

create or replace function app.role_code_immutable() returns trigger language plpgsql as $$
begin if new.code is distinct from old.code then raise exception 'a role code never changes' using errcode = '22023'; end if; return new; end $$;
create trigger role_code_immutable before update on public.role for each row execute function app.role_code_immutable();

create or replace function app.app_user_identity_guard() returns trigger language plpgsql as $$
begin
  if old.auth_user_id is not null and new.email is distinct from old.email then raise exception 'the email of a signed-in user cannot be changed' using errcode = '22023'; end if;
  return new;
end $$;
create trigger app_user_identity_guard before update on public.app_user for each row execute function app.app_user_identity_guard();

-- ---- read models ----
create view public.v_role_admin with (security_invoker = true) as
select r.id, r.code, r.name, r.description, r.is_system, r.row_version,
       coalesce((select array_agg(rp.permission_code order by rp.permission_code) from public.role_permission rp where rp.role_id = r.id), '{}') as permissions,
       (select count(*) from public.user_role ur where ur.role_id = r.id) as user_count,
       exists (select 1 from public.role_permission rp where rp.role_id = r.id and rp.permission_code = 'role.admin') as grants_role_admin
  from public.role r;
grant select on public.v_role_admin to authenticated;

create view public.v_user_admin with (security_invoker = true) as
select u.id, u.email::text as email, u.full_name, u.status, u.scope_all, u.last_login_at, (u.auth_user_id is not null) as signed_in, u.row_version,
       coalesce((select array_agg(r.code order by r.code) from public.user_role ur join public.role r on r.id = ur.role_id where ur.user_id = u.id), '{}') as roles,
       (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'entity') as entity_scopes,
       (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'location') as location_scopes,
       exists (select 1 from public.user_role ur join public.role_permission rp on rp.role_id = ur.role_id where ur.user_id = u.id and rp.permission_code = 'role.admin') as is_role_admin
  from public.app_user u;
grant select on public.v_user_admin to authenticated;

create view public.v_user_scope with (security_invoker = true) as
select s.id, s.user_id, s.scope_type, s.scope_id, coalesce(e.code, l.code) as code, coalesce(e.name, l.name) as name
  from public.user_scope s left join public.entity e on s.scope_type = 'entity' and e.id = s.scope_id left join public.location l on s.scope_type = 'location' and l.id = s.scope_id
 where s.scope_type in ('entity','location');
grant select on public.v_user_scope to authenticated;

-- ---- RPCs (invoker; reason mandatory; GUC confirms a deliberate self-change) ----
create or replace function app.admin_begin(p_perm text, p_reason text, p_confirm boolean) returns void language plpgsql as $$
begin
  if not app.has_permission(p_perm) then raise exception 'you do not have permission (%)', p_perm using errcode = '42501'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'a reason is required' using errcode = '22023'; end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  perform set_config('app.confirm_self_lockout', case when p_confirm then 'yes' else 'no' end, true);
end $$;
revoke all on function app.admin_begin(text, text, boolean) from public, anon;
grant execute on function app.admin_begin(text, text, boolean) to authenticated;

create or replace function public.role_save(p_code text, p_name text, p_description text, p_permissions text[], p_reason text, p_confirm_self boolean default false) returns uuid
language plpgsql security invoker as $$
declare rid uuid; bad text[]; perms text[] := coalesce(p_permissions, '{}');
begin
  perform app.admin_begin('role.admin', p_reason, p_confirm_self);
  if p_code is null or p_code !~ '^[A-Z][A-Z0-9_]{1,40}$' then raise exception 'role code must be upper-case letters, digits or underscore' using errcode = '22023'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'role name is required' using errcode = '22023'; end if;
  select array_agg(x) into bad from unnest(perms) x where x not in (select code from public.permission);
  if bad is not null then raise exception 'unknown permission(s): %', array_to_string(bad, ', ') using errcode = '22023'; end if;
  select id into rid from public.role where code = p_code;
  if rid is null then insert into public.role(code, name, description) values (p_code, trim(p_name), nullif(trim(coalesce(p_description,'')), '')) returning id into rid;
  else
    update public.role set name = trim(p_name), description = nullif(trim(coalesce(p_description,'')), '') where id = rid and (name, description) is distinct from (trim(p_name), nullif(trim(coalesce(p_description,'')), ''));
  end if;
  delete from public.role_permission where role_id = rid and permission_code <> all(perms);
  insert into public.role_permission(role_id, permission_code) select rid, x from unnest(perms) x on conflict do nothing;
  return rid;
end $$;

create or replace function public.user_invite(p_email text, p_full_name text, p_roles text[], p_reason text) returns uuid
language plpgsql security invoker as $$
declare uid uuid; em text := lower(trim(coalesce(p_email,'')));
begin
  perform app.admin_begin('user.admin', p_reason, false);
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'a valid email is required' using errcode = '22023'; end if;
  insert into public.app_user(email, full_name, status) values (em, nullif(trim(coalesce(p_full_name,'')), ''), 'invited') returning id into uid;
  if coalesce(cardinality(p_roles), 0) > 0 then perform public.user_set_roles(uid, p_roles, p_reason, false); end if;
  return uid;
end $$;

create or replace function public.user_set_roles(p_user uuid, p_roles text[], p_reason text, p_confirm_self boolean default false) returns void
language plpgsql security invoker as $$
declare ids uuid[]; roles text[] := coalesce(p_roles, '{}');
begin
  perform app.admin_begin('role.admin', p_reason, p_confirm_self);
  if not exists (select 1 from public.app_user where id = p_user) then raise exception 'user not found' using errcode = '42501'; end if;
  select array_agg(id) into ids from public.role where code = any(roles);
  if coalesce(cardinality(ids), 0) <> cardinality(roles) then raise exception 'unknown role in the list' using errcode = '22023'; end if;
  delete from public.user_role where user_id = p_user and role_id <> all(coalesce(ids, '{}'));
  insert into public.user_role(user_id, role_id, assigned_by) select p_user, id, app.current_user_id() from public.role where code = any(roles) on conflict do nothing;
end $$;

create or replace function public.user_set_status(p_user uuid, p_status text, p_reason text, p_confirm_self boolean default false) returns void
language plpgsql security invoker as $$
declare linked boolean;
begin
  perform app.admin_begin('user.admin', p_reason, p_confirm_self);
  if p_status not in ('active','disabled') then raise exception 'status must be active or disabled' using errcode = '22023'; end if;
  select auth_user_id is not null into linked from public.app_user where id = p_user;
  if not found then raise exception 'user not found' using errcode = '42501'; end if;
  update public.app_user set status = case when p_status = 'active' and not linked then 'invited' else p_status end where id = p_user;
end $$;

create or replace function public.user_set_scope(p_user uuid, p_scope_all boolean, p_entities uuid[], p_locations uuid[], p_reason text) returns void
language plpgsql security invoker as $$
declare ents uuid[] := coalesce(p_entities,'{}'); locs uuid[] := coalesce(p_locations,'{}');
begin
  perform app.admin_begin('user.admin', p_reason, false);
  if not exists (select 1 from public.app_user where id = p_user) then raise exception 'user not found' using errcode = '42501'; end if;
  if exists (select 1 from unnest(ents) x where x not in (select id from public.entity)) then raise exception 'unknown legal entity in scope' using errcode = '22023'; end if;
  if exists (select 1 from unnest(locs) x where x not in (select id from public.location)) then raise exception 'unknown location in scope' using errcode = '22023'; end if;
  if not coalesce(p_scope_all, false) and cardinality(ents) + cardinality(locs) = 0 then raise exception 'choose all locations or at least one entity/location' using errcode = '22023'; end if;
  update public.app_user set scope_all = coalesce(p_scope_all, false) where id = p_user;
  delete from public.user_scope where user_id = p_user and scope_type in ('entity','location') and not ((scope_type = 'entity' and scope_id = any(ents)) or (scope_type = 'location' and scope_id = any(locs)));
  insert into public.user_scope(user_id, scope_type, scope_id) select p_user, 'entity', x from unnest(ents) x on conflict do nothing;
  insert into public.user_scope(user_id, scope_type, scope_id) select p_user, 'location', x from unnest(locs) x on conflict do nothing;
end $$;

do $$ declare f text; begin
  foreach f in array array['role_save(text,text,text,text[],text,boolean)','user_invite(text,text,text[],text)','user_set_roles(uuid,text[],text,boolean)','user_set_status(uuid,text,text,boolean)','user_set_scope(uuid,boolean,uuid[],uuid[],text)'] loop
    execute format('revoke all on function public.%s from public, anon', f); execute format('grant execute on function public.%s to authenticated', f); end loop; end $$;
