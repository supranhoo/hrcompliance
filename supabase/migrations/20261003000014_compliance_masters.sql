-- 0014 Compliance Master (Phase 6.1).
-- Identity (compliance_master) is separate from interpretation (compliance_rule_version): frequency, due rule, risk, evidence
-- requirement live in versions that are IMMUTABLE once published, so a rule change can never silently rewrite history (req. 78).
-- No legal content is seeded (req. 79). Legal fields (law, section, legal_source, last_reviewed_at) are stored, never invented.
-- Rollback: drop tables compliance_rule_evidence, compliance_rule_version, compliance_master, compliance_category;
--           drop functions app.due_rule_is_valid, app.compute_due_date, app.validate_lov, app.lov_value_exists, public.compliance_activate_rule_version;
--           alter table entity drop column industry.

alter table public.entity add column industry text;       -- applicability dimension (Industry); free text until an Industry LOV is agreed

-- ---------- generic LOV membership guard (no hardcoded business lists) ----------
create or replace function app.lov_value_exists(p_set text, p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.lov_value v join public.lov_set s on s.id = v.set_id
                  where s.code = p_set and v.code = p_code and v.is_active and s.is_active)
$$;
-- usage: create trigger … before insert or update on t for each row execute function app.validate_lov('RISK','risk_level');
-- Checked on INSERT and when the column changes, so retiring a LOV value never blocks edits to old rows.
create or replace function app.validate_lov() returns trigger language plpgsql as $$
declare v text := to_jsonb(new) ->> tg_argv[1];
begin
  if v is null then return new; end if;
  if tg_op = 'UPDATE' and (to_jsonb(old) ->> tg_argv[1]) is not distinct from v then return new; end if;
  if not app.lov_value_exists(tg_argv[0], v) then
    raise exception 'Invalid value "%" for % (not an active value of list %)', v, tg_argv[1], tg_argv[0] using errcode = '23514';
  end if;
  return new;
end $$;

-- ---------- structural LOV sets/values the engine relies on (editable labels; codes are referenced by logic) ----------
insert into public.lov_set (code, name, is_system) values
  ('COMPLIANCE_TYPE','Compliance type',true), ('COMPLIANCE_DOMAIN','Compliance domain',false), ('CRITICALITY','Criticality',true)
on conflict (code) do nothing;
insert into public.lov_value (set_id, code, label, sort_order, color)
select s.id, v.code, v.label, v.ord, v.color from public.lov_set s join (values
  ('RISK','low','Low',10,'green'), ('RISK','medium','Medium',20,'amber'), ('RISK','high','High',30,'red'), ('RISK','critical','Critical',40,'red'),
  ('SEVERITY','low','Low',10,'green'), ('SEVERITY','medium','Medium',20,'amber'), ('SEVERITY','high','High',30,'red'), ('SEVERITY','critical','Critical',40,'red'),
  ('CRITICALITY','routine','Routine',10,'grey'), ('CRITICALITY','important','Important',20,'amber'), ('CRITICALITY','critical','Critical',30,'red'),
  ('COMPLIANCE_TYPE','statutory','Statutory',10,null), ('COMPLIANCE_TYPE','regulatory','Regulatory',20,null), ('COMPLIANCE_TYPE','internal','Internal',30,null),
  ('COMPLIANCE_TYPE','contractor','Contractor',40,null), ('COMPLIANCE_TYPE','licence','Licence',50,null), ('COMPLIANCE_TYPE','return','Return',60,null),
  ('COMPLIANCE_TYPE','payment','Payment',70,null), ('COMPLIANCE_TYPE','register','Register',80,null), ('COMPLIANCE_TYPE','inspection','Inspection',90,null),
  ('COMPLIANCE_TYPE','notice','Notice',100,null), ('COMPLIANCE_TYPE','event_based','Event-based',110,null), ('COMPLIANCE_TYPE','incident_based','Incident-based',120,null),
  ('COMPLIANCE_TYPE','one_time','One-time',130,null)
) as v(setcode, code, label, ord, color) on v.setcode = s.code
on conflict (set_id, code) do nothing;

-- ---------- due-rule language (whitelisted JSON; evaluated only by app.compute_due_date) ----------
-- day_of_month        {"type":"day_of_month","day":1-31,"month_offset":0-12}     day (clamped to month end) of the month `month_offset` months after the period-end month
-- days_after_period_end {"type":"days_after_period_end","days":0-366}
-- fixed_date          {"type":"fixed_date","month":1-12,"day":1-31,"year_offset":0-2}  relative to the period-end year
-- absolute_date       {"type":"absolute_date","date":"YYYY-MM-DD"}                 one-time obligations
-- days_after_event    {"type":"days_after_event","days":0-3650}                    event/incident based (period_start = event date)
create or replace function app.due_rule_is_valid(r jsonb, p_frequency text) returns boolean
language plpgsql immutable as $$
declare t text;
begin
  if r is null or jsonb_typeof(r) <> 'object' then return false; end if;
  t := r ->> 'type';
  if p_frequency in ('event_based','incident_based') then return t = 'days_after_event' and (r ->> 'days') ~ '^\d{1,4}$' and (r ->> 'days')::int <= 3650; end if;
  if p_frequency = 'one_time' then return t = 'absolute_date' and (r ->> 'date') ~ '^\d{4}-\d{2}-\d{2}$'; end if;
  if p_frequency = 'custom' then return t in ('absolute_date') and (r ->> 'date') ~ '^\d{4}-\d{2}-\d{2}$'; end if;
  -- periodic frequencies
  if t = 'day_of_month' then
    return (r ->> 'day') ~ '^\d{1,2}$' and (r ->> 'day')::int between 1 and 31 and (r ->> 'month_offset') ~ '^\d{1,2}$' and (r ->> 'month_offset')::int between 0 and 12;
  elsif t = 'days_after_period_end' then
    return (r ->> 'days') ~ '^\d{1,3}$' and (r ->> 'days')::int <= 366;
  elsif t = 'fixed_date' then
    return (r ->> 'month') ~ '^\d{1,2}$' and (r ->> 'month')::int between 1 and 12 and (r ->> 'day') ~ '^\d{1,2}$' and (r ->> 'day')::int between 1 and 31
       and (r ->> 'year_offset') ~ '^\d$' and (r ->> 'year_offset')::int between 0 and 2;
  end if;
  return false;
end $$;

create or replace function app.compute_due_date(r jsonb, p_start date, p_end date) returns date
language plpgsql immutable as $$
declare m date; y int; last_day int; d int;
begin
  case r ->> 'type'
    when 'day_of_month' then
      m := (date_trunc('month', p_end) + make_interval(months => (r ->> 'month_offset')::int))::date;
      last_day := extract(day from (date_trunc('month', m) + interval '1 month - 1 day'))::int;
      return m + (least((r ->> 'day')::int, last_day) - 1);
    when 'days_after_period_end' then return p_end + (r ->> 'days')::int;
    when 'fixed_date' then
      y := extract(year from p_end)::int + (r ->> 'year_offset')::int;
      m := make_date(y, (r ->> 'month')::int, 1);
      last_day := extract(day from (m + interval '1 month - 1 day'))::int;
      d := least((r ->> 'day')::int, last_day);
      return make_date(y, (r ->> 'month')::int, d);
    when 'absolute_date' then return (r ->> 'date')::date;
    when 'days_after_event' then return p_start + (r ->> 'days')::int;
    else raise exception 'Unsupported due rule type %', r ->> 'type' using errcode = '22023';
  end case;
end $$;

-- ---------- tables ----------
create table public.compliance_category (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,31}$'),
  name text not null,
  parent_id uuid references public.compliance_category(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint compliance_category_parent_ck check (parent_id is null or parent_id <> id)
);

create table public.compliance_master (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,39}$'),
  name text not null,
  description text,
  domain text,                                     -- LOV COMPLIANCE_DOMAIN (admin-managed; none seeded)
  category_id uuid references public.compliance_category(id),
  law_id uuid references public.law(id),
  section_reference text,                          -- Act/Rule/Section as supplied by BFCL; never invented
  legal_source text,                               -- authoritative citation/URL
  last_reviewed_at date, reviewed_by uuid,
  owner_department_id uuid references public.department(id),
  default_owner_user_id uuid references public.app_user(id),
  is_active boolean not null default true,
  effective_from date, effective_to date,
  custom jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint compliance_master_period_ck check (app.valid_period(effective_from, effective_to))
);
create index compliance_master_category_idx on public.compliance_master(category_id);
create index compliance_master_law_idx on public.compliance_master(law_id);
create index compliance_master_custom_gin on public.compliance_master using gin (custom);

create table public.compliance_rule_version (
  id uuid primary key default gen_random_uuid(),
  compliance_id uuid not null references public.compliance_master(id),
  version int not null,
  status text not null default 'draft' check (status in ('draft','active','retired')),
  compliance_type text not null,                   -- LOV COMPLIANCE_TYPE
  frequency text not null check (frequency in ('daily','weekly','monthly','quarterly','half_yearly','annual','one_time','event_based','incident_based','custom')),
  period_start_month int not null default 1 check (period_start_month between 1 and 12),  -- 1 = calendar year; 4 = April–March
  due_rule jsonb not null,
  risk_level text not null,                        -- LOV RISK
  criticality text not null default 'routine',     -- LOV CRITICALITY
  evidence_required boolean not null default false,
  alert_rule_code text,                            -- config_definition(kind=alert_rule).code
  escalation_rule_code text,                       -- config_definition(kind=alert_rule).code
  effective_from date not null,
  effective_to date,
  change_reason text,
  custom jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (compliance_id, version),
  constraint rule_version_period_ck check (app.valid_period(effective_from, effective_to)),
  constraint rule_version_due_ck check (app.due_rule_is_valid(due_rule, frequency))
);
create unique index rule_version_one_active_uk on public.compliance_rule_version(compliance_id) where status = 'active';

create table public.compliance_rule_evidence (
  rule_version_id uuid not null references public.compliance_rule_version(id) on delete cascade,
  document_type_id uuid not null references public.document_type(id),
  is_mandatory boolean not null default true,
  primary key (rule_version_id, document_type_id)
);

-- version numbering + immutability of published versions
create or replace function app.rule_version_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then raise exception 'new rule versions must start as draft; activate with compliance_activate_rule_version()' using errcode = '23514'; end if;
    select coalesce(max(version), 0) + 1 into new.version from public.compliance_rule_version where compliance_id = new.compliance_id;
    return new;
  end if;
  if old.status in ('active','retired') then
    if (new.compliance_id, new.version, new.compliance_type, new.frequency, new.period_start_month, new.due_rule, new.risk_level, new.criticality, new.evidence_required, new.effective_from, new.alert_rule_code, new.escalation_rule_code)
       is distinct from
       (old.compliance_id, old.version, old.compliance_type, old.frequency, old.period_start_month, old.due_rule, old.risk_level, old.criticality, old.evidence_required, old.effective_from, old.alert_rule_code, old.escalation_rule_code) then
      raise exception 'rule version % of % is published and immutable; create a new version', old.version, old.compliance_id using errcode = '42501';
    end if;
    if old.status = 'retired' and new.status <> 'retired' then raise exception 'retired rule versions cannot be reactivated' using errcode = '42501'; end if;
    if old.status = 'active' and new.status = 'draft' then raise exception 'published rule versions cannot return to draft' using errcode = '42501'; end if;
  end if;
  return new;
end $$;
create trigger rule_version_guard before insert or update on public.compliance_rule_version for each row execute function app.rule_version_guard();

create or replace function app.rule_evidence_guard() returns trigger language plpgsql as $$
declare v_id uuid := coalesce(new.rule_version_id, old.rule_version_id); v_status text;
begin
  select status into v_status from public.compliance_rule_version where id = v_id;
  if v_status is distinct from 'draft' and v_status is not null then
    raise exception 'evidence requirements of a published rule version are immutable; create a new version' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
create trigger rule_evidence_guard before insert or update or delete on public.compliance_rule_evidence for each row execute function app.rule_evidence_guard();

-- LOV guards
create trigger cm_domain_lov before insert or update on public.compliance_master for each row execute function app.validate_lov('COMPLIANCE_DOMAIN','domain');
create trigger crv_type_lov  before insert or update on public.compliance_rule_version for each row execute function app.validate_lov('COMPLIANCE_TYPE','compliance_type');
create trigger crv_risk_lov  before insert or update on public.compliance_rule_version for each row execute function app.validate_lov('RISK','risk_level');
create trigger crv_crit_lov  before insert or update on public.compliance_rule_version for each row execute function app.validate_lov('CRITICALITY','criticality');

-- Publish a draft: retire the live version (its effective_to = day before the new one starts) and activate, atomically.
create or replace function public.compliance_activate_rule_version(p_version_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare v public.compliance_rule_version; cur public.compliance_rule_version;
begin
  if not app.has_permission('compliance.manage') then raise exception 'permission denied' using errcode = '42501'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'change reason is required' using errcode = '22023'; end if;
  select * into v from public.compliance_rule_version where id = p_version_id for update;
  if not found then raise exception 'unknown rule version' using errcode = '22023'; end if;
  if v.status <> 'draft' then raise exception 'only draft versions can be activated' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('rule:' || v.compliance_id::text, 0));
  select * into cur from public.compliance_rule_version where compliance_id = v.compliance_id and status = 'active';
  if found then
    if v.effective_from <= cur.effective_from then raise exception 'new version must start after the current version (% )', cur.effective_from using errcode = '22023'; end if;
    update public.compliance_rule_version set status = 'retired', effective_to = v.effective_from - 1 where id = cur.id;
  end if;
  update public.compliance_rule_version set status = 'active', change_reason = p_reason where id = v.id;
end $$;
revoke all on function public.compliance_activate_rule_version(uuid, text) from public, anon;
grant execute on function public.compliance_activate_rule_version(uuid, text) to authenticated;

-- stamps + audit
do $$ declare t text; begin
  foreach t in array array['compliance_category','compliance_master','compliance_rule_version'] loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function app.stamp_row()', t||'_stamp', t);
  end loop;
  foreach t in array array['compliance_category','compliance_master','compliance_rule_version','compliance_rule_evidence'] loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.audit_row()', 'audit_'||t, t);
  end loop;
end $$;

-- permissions + grants + RLS
insert into public.permission (code, module, description) values
  ('compliance.read','compliance','View compliance masters, applicability, instances, calendar'),
  ('compliance.write','compliance','Update compliance instances (status, owner, completion)'),
  ('compliance.manage','compliance','Maintain compliance master, rule versions and applicability matrix')
on conflict (code) do nothing;

do $$ declare t text; begin
  foreach t in array array['compliance_category','compliance_master','compliance_rule_version','compliance_rule_evidence'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (app.has_permission(%L))', t||'_sel', t, 'compliance.read');
    execute format('create policy %I on public.%I for insert to authenticated with check (app.has_permission(%L))', t||'_ins', t, 'compliance.manage');
    execute format('create policy %I on public.%I for update to authenticated using (app.has_permission(%L)) with check (app.has_permission(%L))', t||'_upd', t, 'compliance.manage', 'compliance.manage');
  end loop;
  foreach t in array array['compliance_category','compliance_master','compliance_rule_version'] loop
    execute format('grant select, insert, update on public.%I to authenticated', t);
  end loop;
  -- evidence requirements: draft versions only (trigger), so delete is allowed through the guard
  grant select, insert, update, delete on public.compliance_rule_evidence to authenticated;
  create policy compliance_rule_evidence_del on public.compliance_rule_evidence for delete to authenticated using (app.has_permission('compliance.manage'));
end $$;

-- default role grants (editable later from the Permissions UI)
insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r join public.permission p on p.code like 'compliance.%' where
     r.code = 'SUPER_ADMIN'
  or (r.code = 'HEAD_HR'  and p.code in ('compliance.read','compliance.write','compliance.manage'))
  or (r.code = 'PLANT_HR' and p.code in ('compliance.read','compliance.write'))
  or (r.code in ('HOD','VIEWER') and p.code = 'compliance.read')
on conflict do nothing;
