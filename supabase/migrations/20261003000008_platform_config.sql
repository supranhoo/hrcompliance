-- 0008 Platform configuration: modules, status designer, system config, versioned config definitions.
-- config_definition is the single versioned store for: sla_rule, alert_rule, exception_rule, template, contractor_requirement,
-- score_rule, bill_hold_rule, report_definition, import_definition. Typed tables replace a kind only when its module is built
-- against audited source data (docs/DECISIONS.md D-011). Active versions are immutable: change = new version (req. 78).
-- Rollback: drop function public.config_new_version, app.config_definition_guard, app.status_transition_allowed; drop tables in reverse.

create table public.module_definition (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z_]+$'),
  name text not null,
  sort_order int not null default 0,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);

create table public.status_definition (
  id uuid primary key default gen_random_uuid(),
  module text not null references public.module_definition(code),
  code text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  category text not null check (category in ('open','in_progress','closed','cancelled')),
  color text check (color in ('green','amber','red','blue','grey')),
  sort_order int not null default 0,
  is_initial boolean not null default false,
  is_terminal boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (module, code),
  constraint status_terminal_category_ck check (not is_terminal or category in ('closed','cancelled'))
);
create unique index status_one_initial_uk on public.status_definition(module) where is_initial and is_active;

create table public.status_transition (
  id uuid primary key default gen_random_uuid(),
  module text not null,
  from_status text not null,
  to_status text not null,
  requires_reason boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (module, from_status, to_status),
  foreign key (module, from_status) references public.status_definition(module, code),
  foreign key (module, to_status) references public.status_definition(module, code),
  constraint status_transition_distinct_ck check (from_status <> to_status)
);

-- Structural safety: configuration decides WHICH transitions exist; this function is the only way modules ask.
create or replace function app.status_transition_allowed(p_module text, p_from text, p_to text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.status_transition t
                   join public.status_definition f on f.module = t.module and f.code = t.from_status
                   join public.status_definition s on s.module = t.module and s.code = t.to_status
                  where t.module = p_module and t.from_status = p_from and t.to_status = p_to
                    and t.is_active and f.is_active and s.is_active)
$$;

create table public.system_config (
  key text primary key check (key ~ '^[a-z0-9_.]+$'
                              and key !~* '(secret|password|passwd|token|api_?key|private|credential)'),
  value jsonb not null,
  description text,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);
comment on table public.system_config is 'Non-secret runtime settings only. Secrets live in Supabase/CI secret stores, never here.';

create table public.config_definition (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('sla_rule','alert_rule','exception_rule','template','contractor_requirement',
                                     'score_rule','bill_hold_rule','report_definition','import_definition')),
  code text not null check (code ~ '^[A-Za-z][A-Za-z0-9_.-]{0,63}$'),
  name text not null,
  version int not null default 1 check (version >= 1),
  status text not null default 'active' check (status in ('draft','active','retired')),
  definition jsonb not null check (jsonb_typeof(definition) = 'object'),
  change_reason text,
  effective_from date, effective_to date,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (kind, code, version),
  constraint config_when_valid_ck check (not (definition ? 'when') or app.rule_is_valid(definition -> 'when')),
  constraint config_period_ck check (app.valid_period(effective_from, effective_to))
);
create unique index config_definition_live_uk on public.config_definition(kind, code) where status = 'active';
create index config_definition_kind_idx on public.config_definition(kind, code, version desc);

-- Published versions are immutable; only status (active->retired) and effective_to may change.
create or replace function app.config_definition_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and old.status in ('active','retired') then
    if (new.kind, new.code, new.name, new.version, new.definition) is distinct from (old.kind, old.code, old.name, old.version, old.definition)
       or new.effective_from is distinct from old.effective_from then
      raise exception 'config_definition %/% v% is published and immutable; create a new version', old.kind, old.code, old.version using errcode = '42501';
    end if;
    if old.status = 'retired' and new.status <> 'retired' then
      raise exception 'retired config versions cannot be reactivated; create a new version' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger config_definition_guard before update on public.config_definition for each row execute function app.config_definition_guard();

-- Atomically publish the next version and retire the previous live one.
create or replace function public.config_new_version(p_kind text, p_code text, p_name text, p_definition jsonb, p_reason text,
                                                      p_effective_from date default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_next int; v_id uuid;
begin
  if not app.has_permission('config.write') then raise exception 'permission denied' using errcode = '42501'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'change reason is required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_kind || ':' || p_code, 0));
  select coalesce(max(version), 0) + 1 into v_next from public.config_definition where kind = p_kind and code = p_code;
  update public.config_definition set status = 'retired', effective_to = coalesce(effective_to, coalesce(p_effective_from, current_date))
   where kind = p_kind and code = p_code and status = 'active';
  insert into public.config_definition (kind, code, name, version, status, definition, change_reason, effective_from)
  values (p_kind, p_code, p_name, v_next, 'active', p_definition, p_reason, coalesce(p_effective_from, current_date))
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.config_new_version(text, text, text, jsonb, text, date) from public, anon;
grant execute on function public.config_new_version(text, text, text, jsonb, text, date) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['module_definition','status_definition','status_transition','system_config','config_definition']
  loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function app.stamp_row()', t||'_stamp', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.audit_row()', 'audit_'||t, t);
  end loop;
end $$;
