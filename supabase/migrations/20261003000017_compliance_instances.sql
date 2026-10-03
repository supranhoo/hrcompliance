-- 0017 Compliance instances + idempotent generator (Phase 6.4).
-- IDEMPOTENCY KEY: UNIQUE (compliance_id, location_id, period_start). The generator uses INSERT … ON CONFLICT DO NOTHING, so
-- repeated or concurrent runs can never duplicate an obligation. The rule version used for an instance is the one in force at the
-- period start, so a later rule change never rewrites past instances (req. 78).
-- Status model is configuration (status_definition / status_transition, module 'compliance'); due-state (due soon/overdue/upcoming)
-- is DERIVED, never stored.
-- Rollback: drop view v_compliance_instance; drop functions public.compliance_create_manual_instance, public.compliance_calendar,
--           app.run_compliance_generation, app.generate_compliance_instances, app.compliance_periods, app.due_state, app.enforce_status;
--           drop table compliance_instance; delete seeded status rows for module 'compliance'.

-- ---------- generic, configuration-driven status enforcement ----------
-- usage: create trigger … before insert or update on t for each row execute function app.enforce_status('compliance','status');
-- INSERT: must be an active status of the module. UPDATE: the transition must exist in status_transition; transitions flagged
-- requires_reason need a non-empty app.audit_reason (set_config('app.audit_reason', '…', true)) which the audit log records.
create or replace function app.enforce_status() returns trigger language plpgsql as $$
declare col text := tg_argv[1]; nv text := to_jsonb(new) ->> tg_argv[1]; ov text; reason_needed boolean;
begin
  if tg_op = 'UPDATE' then
    ov := to_jsonb(old) ->> col;
    if ov is not distinct from nv then return new; end if;
  end if;
  if not exists (select 1 from public.status_definition where module = tg_argv[0] and code = nv and is_active) then
    raise exception 'Unknown or inactive % status "%"', tg_argv[0], nv using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if not app.status_transition_allowed(tg_argv[0], ov, nv) then
      raise exception 'Status change % -> % is not allowed for %', ov, nv, tg_argv[0] using errcode = '23514';
    end if;
    select requires_reason into reason_needed from public.status_transition where module = tg_argv[0] and from_status = ov and to_status = nv;
    if reason_needed and length(trim(coalesce(current_setting('app.audit_reason', true), ''))) = 0 then
      raise exception 'Status change % -> % requires a reason', ov, nv using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

-- ---------- seed: compliance statuses + transitions (structural; labels/colours editable in the Status Designer) ----------
insert into public.status_definition (module, code, label, category, color, sort_order, is_initial, is_terminal) values
  ('compliance','open','Open','open','blue',10,true,false),
  ('compliance','in_progress','In progress','in_progress','blue',20,false,false),
  ('compliance','completed','Completed','closed','green',30,false,true),
  ('compliance','not_applicable','Not applicable','cancelled','grey',40,false,true)
on conflict (module, code) do nothing;
insert into public.status_transition (module, from_status, to_status, requires_reason) values
  ('compliance','open','in_progress',false), ('compliance','open','completed',false), ('compliance','in_progress','completed',false),
  ('compliance','open','not_applicable',true), ('compliance','in_progress','not_applicable',true),
  ('compliance','in_progress','open',false),
  ('compliance','completed','open',true), ('compliance','completed','in_progress',true), ('compliance','not_applicable','open',true)
on conflict (module, from_status, to_status) do nothing;

insert into public.system_config (key, value, description) values
  ('compliance.due_soon_days', '7', 'An open obligation is "due soon" when due within this many days'),
  ('compliance.generation_horizon_days', '60', 'How far ahead the generator creates instances'),
  ('compliance.generation_lookback_days', '0', 'How far back the nightly generator looks (0 = current period only; historical data comes from the Import Centre)')
on conflict (key) do nothing;

-- ---------- derived due-state ----------
create or replace function app.due_state(p_status text, p_due date, p_ref date default current_date, p_soon int default null) returns text
language sql stable as $$
  select case when p_status = 'completed' then 'completed'
              when p_status = 'not_applicable' then 'not_applicable'
              when p_due < p_ref then 'overdue'
              when p_due <= p_ref + coalesce(p_soon, (select (value #>> '{}')::int from public.system_config where key = 'compliance.due_soon_days'), 7) then 'due_soon'
              else 'upcoming' end
$$;

-- ---------- periods ----------
-- Periods of a frequency overlapping [p_from, p_to]. Quarter/half/annual boundaries are anchored on period_start_month (1 = calendar, 4 = Apr–Mar).
-- one_time / event_based / incident_based / custom are never auto-generated.
create or replace function app.compliance_periods(p_frequency text, p_start_month int, p_from date, p_to date)
returns table (period_start date, period_end date)
language plpgsql immutable as $$
declare step interval; anchor date;
begin
  if p_to < p_from then return; end if;
  -- timestamp (not timestamptz) series: no time-zone or DST drift on pure dates
  if p_frequency = 'daily' then
    return query select d::date, d::date from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d;
  elsif p_frequency = 'weekly' then
    return query select w::date, w::date + 6 from generate_series(date_trunc('week', p_from::timestamp), p_to::timestamp, interval '7 days') w where w::date + 6 >= p_from;
  elsif p_frequency in ('monthly','quarterly','half_yearly','annual') then
    step := case p_frequency when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' when 'half_yearly' then interval '6 months' else interval '1 year' end;
    anchor := make_date(1990, case when p_frequency = 'monthly' then 1 else p_start_month end, 1);
    return query select s::date, (s + step - interval '1 day')::date
                   from generate_series(anchor::timestamp, date_trunc('month', p_to::timestamp), step) s
                  where (s + step - interval '1 day')::date >= p_from and s::date <= p_to;
  end if;
end $$;

-- ---------- instance table ----------
create table public.compliance_instance (
  id uuid primary key default gen_random_uuid(),
  instance_no text not null unique,                  -- CMP-2026-000001
  compliance_id uuid not null references public.compliance_master(id),
  rule_version_id uuid not null references public.compliance_rule_version(id),
  entity_id uuid not null references public.entity(id),
  location_id uuid not null references public.location(id),
  period_start date not null,
  period_end date not null,
  due_date date not null,
  status text not null default 'open',
  owner_user_id uuid references public.app_user(id),
  completed_on date,
  completed_by uuid,
  remarks text,
  source text not null default 'generated' check (source in ('generated','manual','import')),
  custom jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint compliance_instance_period_ck check (period_end >= period_start),
  constraint compliance_instance_completion_ck check ((status = 'completed') = (completed_on is not null)),
  constraint compliance_instance_idem_uk unique (compliance_id, location_id, period_start)
);
create index ci_due_idx on public.compliance_instance(due_date) where status in ('open','in_progress');
create index ci_status_due_idx on public.compliance_instance(status, due_date);
create index ci_location_idx on public.compliance_instance(location_id, due_date);
create index ci_entity_idx on public.compliance_instance(entity_id);
create index ci_owner_idx on public.compliance_instance(owner_user_id) where owner_user_id is not null;
create index ci_custom_gin on public.compliance_instance using gin (custom);

create trigger ci_no_assign before insert on public.compliance_instance for each row execute function app.assign_business_id('CMP','instance_no');
create trigger ci_status before insert or update on public.compliance_instance for each row execute function app.enforce_status('compliance','status');

-- completion bookkeeping + identity immutability
create or replace function app.compliance_instance_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    if (new.instance_no, new.compliance_id, new.rule_version_id, new.entity_id, new.location_id, new.period_start, new.period_end, new.due_date, new.source)
       is distinct from (old.instance_no, old.compliance_id, old.rule_version_id, old.entity_id, old.location_id, old.period_start, old.period_end, old.due_date, old.source) then
      raise exception 'compliance instance identity, period and due date are immutable' using errcode = '42501';
    end if;
  end if;
  if new.status = 'completed' then
    new.completed_on := coalesce(new.completed_on, current_date);
    new.completed_by := coalesce(new.completed_by, auth.uid());
    if new.completed_on < new.period_start then raise exception 'completion date cannot precede the period start' using errcode = '23514'; end if;
  else
    new.completed_on := null; new.completed_by := null;
  end if;
  return new;
end $$;
create trigger ci_guard before insert or update on public.compliance_instance for each row execute function app.compliance_instance_guard();
create trigger ci_stamp before insert or update on public.compliance_instance for each row execute function app.stamp_row();
create trigger audit_ci after insert or update or delete on public.compliance_instance for each row execute function app.audit_row();

-- ---------- generator ----------
create or replace function app.generate_compliance_instances(p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cand int; v_ins int;
begin
  with rv as (
    select r.*, m.default_owner_user_id as m_owner
      from public.compliance_rule_version r join public.compliance_master m on m.id = r.compliance_id
     where r.status in ('active','retired') and m.is_active
       and r.frequency in ('daily','weekly','monthly','quarterly','half_yearly','annual')
       and r.effective_from <= p_to and (r.effective_to is null or r.effective_to >= p_from)
       and (m.effective_from is null or m.effective_from <= p_to) and (m.effective_to is null or m.effective_to >= p_from)),
  cand as (
    select rv.compliance_id, rv.id as rule_version_id, rv.m_owner, l.entity_id, l.id as location_id, p.period_start, p.period_end,
           app.compute_due_date(rv.due_rule, p.period_start, p.period_end) as due_date
      from rv
      cross join public.location l
      cross join lateral app.compliance_periods(rv.frequency, rv.period_start_month, greatest(p_from, rv.effective_from), least(p_to, coalesce(rv.effective_to, p_to))) p
     where l.is_active
       and p.period_start >= rv.effective_from and (rv.effective_to is null or p.period_start <= rv.effective_to)   -- rule version in force at the period start
       and (select a.effective_status from app.applicability_for(rv.compliance_id, l.id, p.period_start) a) = 'applicable'),
  ins as (
    insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, source)
    select compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, m_owner, 'generated' from cand
    on conflict (compliance_id, location_id, period_start) do nothing
    returning 1)
  select (select count(*) from cand), (select count(*) from ins) into v_cand, v_ins;
  return jsonb_build_object('window_from', p_from, 'window_to', p_to, 'applicable_obligations', v_cand, 'inserted', v_ins, 'already_existing', v_cand - v_ins);
end $$;

-- Scheduler entry point: one logical run per day (job idempotency key), logged in job_run; never silently fails.
create or replace function app.run_compliance_generation(p_env text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cfg_h int; cfg_b int; j record; res jsonb;
begin
  select coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_horizon_days'), 60),
         coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_lookback_days'), 0) into cfg_h, cfg_b;
  select * into j from app.job_start('compliance_generation', to_char(current_date, 'YYYY-MM-DD'), p_env, 'schedule');
  if not j.should_run then return jsonb_build_object('ran', false, 'reason', j.reason); end if;
  begin
    res := app.generate_compliance_instances(current_date - cfg_b, current_date + cfg_h);
    perform app.job_finish(j.run_id, true, (res ->> 'inserted')::int, null);
    return res || jsonb_build_object('ran', true);
  exception when others then
    perform app.job_finish(j.run_id, false, null, jsonb_build_object('message', sqlerrm, 'state', sqlstate));
    return jsonb_build_object('ran', true, 'error', sqlerrm);
  end;
end $$;
revoke all on function app.generate_compliance_instances(date, date), app.run_compliance_generation(text) from public;
grant execute on function app.generate_compliance_instances(date, date), app.run_compliance_generation(text) to service_role;

-- Event-/incident-based and one-time obligations are created by a person, never by the scheduler. Idempotent by the same key.
create or replace function public.compliance_create_manual_instance(p_compliance uuid, p_location uuid, p_event_date date, p_remarks text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare l public.location; rv public.compliance_rule_version; m public.compliance_master; v_id uuid; v_start date; v_end date;
begin
  select * into l from public.location where id = p_location;
  if not found then raise exception 'unknown location' using errcode = '22023'; end if;
  if not (app.has_permission('compliance.write') and app.scope_ok(l.entity_id, l.id)) then raise exception 'permission denied' using errcode = '42501'; end if;
  select * into m from public.compliance_master where id = p_compliance and is_active;
  if not found then raise exception 'unknown or inactive compliance' using errcode = '22023'; end if;
  select * into rv from public.compliance_rule_version
   where compliance_id = p_compliance and status in ('active','retired') and effective_from <= p_event_date and (effective_to is null or effective_to >= p_event_date)
   order by version desc limit 1;
  if not found then raise exception 'no published rule version in force on %', p_event_date using errcode = '22023'; end if;
  if rv.frequency not in ('one_time','event_based','incident_based','custom') then raise exception 'periodic compliance is generated automatically' using errcode = '22023'; end if;
  if (select effective_status from app.applicability_for(p_compliance, p_location, p_event_date)) is distinct from 'applicable' then
    raise exception 'compliance is not applicable to this location on %', p_event_date using errcode = '22023';
  end if;
  v_start := p_event_date; v_end := p_event_date;
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, remarks, source)
  values (p_compliance, rv.id, l.entity_id, l.id, v_start, v_end, app.compute_due_date(rv.due_rule, v_start, v_end), m.default_owner_user_id, p_remarks, 'manual')
  on conflict (compliance_id, location_id, period_start) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.compliance_instance where compliance_id = p_compliance and location_id = p_location and period_start = v_start; end if;
  return v_id;
end $$;
revoke all on function public.compliance_create_manual_instance(uuid, uuid, date, text) from public, anon;
grant execute on function public.compliance_create_manual_instance(uuid, uuid, date, text) to authenticated;

-- ---------- derived register view (SECURITY INVOKER) + calendar ----------
create view public.v_compliance_instance with (security_invoker = true) as
select i.id, i.instance_no, i.compliance_id, m.code as compliance_code, m.name as compliance_name, m.domain, m.category_id,
       i.rule_version_id, v.compliance_type, v.frequency, v.risk_level, v.criticality, v.evidence_required,
       i.entity_id, i.location_id, l.code as location_code, l.name as location_name,
       i.period_start, i.period_end, i.due_date, i.status, i.owner_user_id, i.completed_on, i.remarks,
       (i.due_date - current_date) as days_to_due,
       app.due_state(i.status, i.due_date) as due_state,
       case when i.status in ('open','in_progress') and i.due_date < current_date then current_date - i.due_date else 0 end as days_overdue
  from public.compliance_instance i
  join public.compliance_master m on m.id = i.compliance_id
  join public.compliance_rule_version v on v.id = i.rule_version_id
  join public.location l on l.id = i.location_id;

create or replace function public.compliance_calendar(p_from date, p_to date)
returns table (instance_id uuid, instance_no text, compliance_code text, compliance_name text, location_code text, due_date date, status text, due_state text, risk_level text)
language sql stable as $$
  select id, instance_no, compliance_code, compliance_name, location_code, due_date, status, due_state, risk_level
    from public.v_compliance_instance where due_date between p_from and p_to order by due_date, compliance_code, location_code
$$;
revoke all on function public.compliance_calendar(date, date) from public, anon;
grant execute on function public.compliance_calendar(date, date) to authenticated;

-- ---------- RLS: reads scoped; updates scoped; NO direct inserts (generator / manual RPC only) ----------
alter table public.compliance_instance enable row level security;
alter table public.compliance_instance force row level security;
grant select, update on public.compliance_instance to authenticated;
grant select on public.v_compliance_instance to authenticated;
create policy ci_sel on public.compliance_instance for select to authenticated using (app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id));
create policy ci_upd on public.compliance_instance for update to authenticated
  using (app.has_permission('compliance.write') and app.scope_ok(entity_id, location_id))
  with check (app.has_permission('compliance.write') and app.scope_ok(entity_id, location_id));
