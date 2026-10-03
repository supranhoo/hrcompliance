-- 0025 F-2 (owner-decided 2026-10-03): when a rule version takes effect,
--   * obligations that were COMPLETED, ACTIONED or otherwise TOUCHED BY A HUMAN stay pinned to the rule version they were created under;
--   * FUTURE, UNTOUCHED, system-generated obligations (period starts on/after the new effective date) are SUPERSEDED and regenerated under the new rule,
--     with the full change history in the audit log, the replacement linked to the superseded row, and no duplicate (uniqueness holds among non-superseded rows).
-- "Untouched" = no HUMAN / BUSINESS action ever occurred. It is held in a reliable marker, compliance_instance.human_touched_at, set by triggers only when a
-- user-originated session (authenticated API user) changes status / owner / remarks / completion / custom data, attaches evidence, or acts on an exception of the
-- obligation. Machine activity (generator, alert engine, exception detector, scheduled jobs; sessions without an auth user) NEVER sets it.
-- The marker is verifiable and rebuildable from the audit log / evidence / exception timeline (app.human_touch_events, app.rebuild_human_touched).
-- Superseded rows are excluded from registers, calendar, dashboards, evidence requirements, alerts and exception detection (v_compliance_instance is filtered)
-- and remain readable through public.v_compliance_superseded and the audit log. 'superseded' is set ONLY by app.reconcile_future_obligations (no UI transition).
-- Rollback: restore functions/views from migrations 0014, 0017, 0018, 0023; drop triggers ci_touch_*; drop index compliance_instance_idem_uk and re-create the
--           unique constraint compliance_instance_idem_uk (compliance_id, location_id, period_start) after deleting superseded rows; drop the added columns;
--           delete from status_definition where module = 'compliance' and code = 'superseded'.

-- ---------- columns, status, uniqueness ----------
alter table public.compliance_instance
  add column human_touched_at timestamptz,
  add column superseded_by uuid references public.compliance_instance(id),
  add column superseded_at timestamptz,
  add column supersede_reason text;
alter table public.compliance_instance add constraint compliance_instance_superseded_ck check ((status = 'superseded') = (superseded_at is not null));
insert into public.status_definition (module, code, label, category, color, sort_order, is_initial, is_terminal)
values ('compliance','superseded','Superseded by rule change','cancelled','grey',90,false,true) on conflict (module, code) do nothing;

-- the idempotency key now holds among NON-superseded rows, so a replacement for the same period is legal and a duplicate is still impossible
alter table public.compliance_instance drop constraint compliance_instance_idem_uk;
create unique index compliance_instance_idem_uk on public.compliance_instance (compliance_id, location_id, period_start) where status <> 'superseded';
create index ci_untouched_idx on public.compliance_instance (compliance_id, period_start) where human_touched_at is null and status = 'open' and source = 'generated';

-- ---------- human-touch marker ----------
-- trusted context = a security-definer function (owner session), never a PostgREST caller
create or replace function app.trusted_context(p_flag text) returns boolean language sql stable as
$$ select coalesce(current_setting(p_flag, true), '') = 'on' and current_user not in ('authenticated','anon','authenticator') $$;

create or replace function app.compliance_instance_guard() returns trigger language plpgsql as $$
declare human boolean := auth.uid() is not null;
begin
  if tg_op = 'UPDATE' then
    if (new.instance_no, new.compliance_id, new.rule_version_id, new.entity_id, new.location_id, new.period_start, new.period_end, new.due_date, new.source)
       is distinct from (old.instance_no, old.compliance_id, old.rule_version_id, old.entity_id, old.location_id, old.period_start, old.period_end, old.due_date, old.source) then
      raise exception 'compliance instance identity, period and due date are immutable' using errcode = '42501';
    end if;
    if new.status = 'superseded' and old.status <> 'superseded' and not app.trusted_context('app.reconcile') then
      raise exception 'only the rule-change reconciliation can supersede an obligation' using errcode = '42501';
    end if;
    if old.status = 'superseded' and (new.status, new.superseded_at, new.supersede_reason) is distinct from (old.status, old.superseded_at, old.supersede_reason) then
      raise exception 'a superseded obligation is closed history' using errcode = '42501';
    end if;
    if (new.superseded_by, new.superseded_at, new.supersede_reason) is distinct from (old.superseded_by, old.superseded_at, old.supersede_reason) and not app.trusted_context('app.reconcile') then
      raise exception 'supersession fields are system-managed' using errcode = '42501';
    end if;
    -- human_touched_at: set only by a user-originated business change (or the trusted child-record trigger); never cleared; never written by the caller
    if human and not app.trusted_context('app.touch') then
      new.human_touched_at := coalesce(old.human_touched_at,
        case when new.status <> 'superseded' and (new.status, new.owner_user_id, new.remarks, new.custom, new.completed_on) is distinct from (old.status, old.owner_user_id, old.remarks, old.custom, old.completed_on) then now() end);
    else
      new.human_touched_at := coalesce(old.human_touched_at, new.human_touched_at);
    end if;
  else
    if human and new.source = 'manual' then new.human_touched_at := now(); else new.human_touched_at := null; end if;   -- a person raising an obligation is a business action
    new.superseded_by := null; new.superseded_at := null; new.supersede_reason := null;
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

-- evidence / exception activity by a USER on an obligation touches it (machine activity does not: no auth user)
create or replace function app.touch_instance_from_child() returns trigger language plpgsql security definer set search_path = public as $$
declare v_inst uuid;
begin
  if auth.uid() is null then return null; end if;
  if tg_table_name = 'evidence' then v_inst := new.compliance_instance_id;
  elsif tg_table_name = 'exception_action' then
    select coalesce(x.compliance_instance_id, (select e.compliance_instance_id from public.evidence e where e.id = x.evidence_id)) into v_inst from public.exception x where x.id = new.exception_id;
    if new.created_by is null then return null; end if;
  end if;
  if v_inst is not null then
    perform set_config('app.touch', 'on', true);
    update public.compliance_instance set human_touched_at = now() where id = v_inst and human_touched_at is null;
    perform set_config('app.touch', 'off', true);
  end if;
  return null;
end $$;
create trigger ci_touch_evidence after insert on public.evidence for each row execute function app.touch_instance_from_child();
create trigger ci_touch_exception_action after insert on public.exception_action for each row execute function app.touch_instance_from_child();

-- audit-driven determination (the verification / rebuild side of the marker)
create or replace function app.human_touch_events(p_instance uuid) returns timestamptz language sql stable security definer set search_path = public as $$
  select min(t) from (
    select a.at as t from public.audit_log a where a.table_name = 'compliance_instance' and a.record_id = p_instance::text and a.actor_id is not null
       and ((a.action = 'INSERT' and a.new_data ->> 'source' = 'manual') or (a.action = 'UPDATE' and a.changed_fields && array['status','owner_user_id','remarks','custom','completed_on']
             and coalesce(a.new_data ->> 'status', '') <> 'superseded'))
    union all select e.created_at from public.evidence e where e.compliance_instance_id = p_instance and e.created_by is not null
    union all select ea.created_at from public.exception_action ea join public.exception x on x.id = ea.exception_id
       where ea.created_by is not null and (x.compliance_instance_id = p_instance or x.evidence_id in (select id from public.evidence where compliance_instance_id = p_instance))
  ) q
$$;
create or replace function app.rebuild_human_touched() returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform set_config('app.touch', 'on', true);
  update public.compliance_instance i set human_touched_at = app.human_touch_events(i.id) where i.human_touched_at is null and app.human_touch_events(i.id) is not null;
  get diagnostics n = row_count; perform set_config('app.touch', 'off', true); return n;
end $$;
grant execute on function app.trusted_context(text) to authenticated;      -- read-only GUC check, called from the invoker-rights guard triggers
revoke all on function app.touch_instance_from_child(), app.human_touch_events(uuid), app.rebuild_human_touched() from public, anon, authenticated;
select app.rebuild_human_touched();      -- backfill existing rows from the audit log (rows only ever changed by jobs / the SQL editor stay untouched)

-- the one status that has no UI transition: only the trusted reconciliation may set it
CREATE OR REPLACE FUNCTION app.enforce_status()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
    if not app.status_transition_allowed(tg_argv[0], ov, nv) and not (nv = 'superseded' and app.trusted_context('app.reconcile')) then
      raise exception 'Status change % -> % is not allowed for %', ov, nv, tg_argv[0] using errcode = '23514';
    end if;
    select requires_reason into reason_needed from public.status_transition where module = tg_argv[0] and from_status = ov and to_status = nv;
    if reason_needed and length(trim(coalesce(current_setting('app.audit_reason', true), ''))) = 0 then
      raise exception 'Status change % -> % requires a reason', ov, nv using errcode = '23514';
    end if;
  end if;
  return new;
end $function$;

-- ---------- reconciliation ----------
create or replace function app.rule_in_force(p_compliance uuid, p_on date) returns uuid language sql stable security definer set search_path = public as $$
  select id from public.compliance_rule_version where compliance_id = p_compliance and status in ('active','retired')
     and effective_from <= p_on and (effective_to is null or effective_to >= p_on) order by version desc limit 1
$$;

create or replace function app.reconcile_future_obligations(p_compliance uuid, p_from date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ids uuid[]; v_min date; v_max date; n_sup int := 0; n_new int := 0; n_pinned int := 0; r jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('rule:' || p_compliance::text, 0));
  select array_agg(i.id), min(i.period_start), max(i.period_end) into ids, v_min, v_max
    from public.compliance_instance i
   where i.compliance_id = p_compliance and i.period_start >= p_from and i.source = 'generated' and i.status = 'open' and i.human_touched_at is null
     and not exists (select 1 from public.evidence e where e.compliance_instance_id = i.id)
     and i.rule_version_id is distinct from app.rule_in_force(i.compliance_id, i.period_start);
  select count(*) into n_pinned from public.compliance_instance i
   where i.compliance_id = p_compliance and i.period_start >= p_from and i.status <> 'superseded' and i.rule_version_id is distinct from app.rule_in_force(i.compliance_id, i.period_start)
     and not (i.id = any(coalesce(ids, '{}'::uuid[])));
  if ids is null then return jsonb_build_object('superseded', 0, 'created', 0, 'pinned_actioned', n_pinned); end if;

  perform set_config('app.reconcile', 'on', true);
  perform set_config('app.audit_reason', 'Rule change: ' || coalesce(nullif(trim(p_reason), ''), 'new rule version took effect'), true);
  update public.compliance_instance set status = 'superseded', superseded_at = now(), supersede_reason = current_setting('app.audit_reason') where id = any(ids);
  get diagnostics n_sup = row_count;
  update public.exception set status = 'resolved', resolution = 'Obligation superseded by rule change', auto_resolved = true
   where compliance_instance_id = any(ids) and status in ('open','acknowledged');
  r := app.generate_compliance_instances(v_min, v_max);
  n_new := (r ->> 'inserted')::int;
  update public.compliance_instance s set superseded_by = (select n.id from public.compliance_instance n
     where n.compliance_id = s.compliance_id and n.location_id = s.location_id and n.period_start = s.period_start and n.status <> 'superseded' limit 1)
   where s.id = any(ids);
  perform set_config('app.reconcile', 'off', true);
  perform set_config('app.audit_reason', '', true);
  return jsonb_build_object('superseded', n_sup, 'created', n_new, 'pinned_actioned', n_pinned);
end $$;
revoke all on function app.rule_in_force(uuid, date), app.reconcile_future_obligations(uuid, date, text) from public, anon, authenticated;
grant execute on function app.reconcile_future_obligations(uuid, date, text) to service_role;

-- obligations still on a superseded-by-change rule because a person already acted on them: the list a human decides on
create or replace function public.compliance_reconciliation_report(p_compliance uuid default null)
returns table (instance_no text, compliance_code text, location_code text, period_start date, status text, pinned_rule_version int, rule_version_in_force int, human_touched_at timestamptz)
language sql stable as $$
  select i.instance_no, m.code, l.code, i.period_start, i.status, v.version, nv.version, i.human_touched_at
    from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.location l on l.id = i.location_id
    join public.compliance_rule_version v on v.id = i.rule_version_id
    left join public.compliance_rule_version nv on nv.id = app.rule_in_force(i.compliance_id, i.period_start)
   where i.status <> 'superseded' and i.period_start >= current_date and i.rule_version_id is distinct from nv.id and (p_compliance is null or i.compliance_id = p_compliance)
   order by m.code, l.code, i.period_start
$$;
revoke all on function public.compliance_reconciliation_report(uuid) from public, anon;
grant execute on function public.compliance_reconciliation_report(uuid) to authenticated;

-- ---------- consumers: superseded rows are history, not work ----------
create or replace view public.v_compliance_instance with (security_invoker = true) as
 SELECT i.id, i.instance_no, i.compliance_id, m.code AS compliance_code, m.name AS compliance_name, m.domain, m.category_id, i.rule_version_id, v.compliance_type, v.frequency,
    v.risk_level, v.criticality, v.evidence_required, i.entity_id, i.location_id, l.code AS location_code, l.name AS location_name, i.period_start, i.period_end, i.due_date, i.status,
    i.owner_user_id, i.completed_on, i.remarks, (i.due_date - CURRENT_DATE) AS days_to_due, app.due_state(i.status, i.due_date) AS due_state,
    CASE WHEN ((i.status = ANY (ARRAY['open'::text, 'in_progress'::text])) AND (i.due_date < CURRENT_DATE)) THEN (CURRENT_DATE - i.due_date) ELSE 0 END AS days_overdue
   FROM (((public.compliance_instance i JOIN public.compliance_master m ON ((m.id = i.compliance_id))) JOIN public.compliance_rule_version v ON ((v.id = i.rule_version_id))) JOIN public.location l ON ((l.id = i.location_id)))
  WHERE i.status <> 'superseded';

create or replace view public.v_evidence_requirement with (security_invoker = true) as
 SELECT i.id AS compliance_instance_id, i.instance_no, i.compliance_id, i.entity_id, i.location_id, i.due_date, i.status AS instance_status, rq.document_type_id,
    dt.code AS document_type_code, dt.name AS document_type_name, rq.is_mandatory, e.id AS evidence_id, e.evidence_no, e.version, e.verification_status, e.expiry_date,
    CASE WHEN (e.id IS NULL) THEN 'missing'::text WHEN ((e.expiry_date IS NOT NULL) AND (e.expiry_date < CURRENT_DATE)) THEN 'expired'::text ELSE e.verification_status END AS evidence_state
   FROM ((((public.compliance_instance i JOIN public.compliance_rule_version v ON (((v.id = i.rule_version_id) AND v.evidence_required)))
     JOIN public.compliance_rule_evidence rq ON ((rq.rule_version_id = v.id))) JOIN public.document_type dt ON ((dt.id = rq.document_type_id)))
     LEFT JOIN public.evidence e ON (((e.compliance_instance_id = i.id) AND (e.document_type_id = rq.document_type_id) AND e.is_current)))
  WHERE i.status <> 'superseded';

create view public.v_compliance_superseded with (security_invoker = true) as
select s.id, s.instance_no, m.code as compliance_code, l.code as location_code, s.period_start, s.due_date, s.superseded_at, s.supersede_reason,
       v.version as old_rule_version, n.instance_no as replaced_by_instance_no, nv.version as new_rule_version, s.entity_id, s.location_id
  from public.compliance_instance s join public.compliance_master m on m.id = s.compliance_id join public.location l on l.id = s.location_id
  join public.compliance_rule_version v on v.id = s.rule_version_id
  left join public.compliance_instance n on n.id = s.superseded_by left join public.compliance_rule_version nv on nv.id = n.rule_version_id
 where s.status = 'superseded';
grant select on public.v_compliance_superseded to authenticated;

CREATE OR REPLACE FUNCTION app.generate_compliance_instances(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    on conflict (compliance_id, location_id, period_start) where status <> 'superseded' do nothing
    returning 1)
  select (select count(*) from cand), (select count(*) from ins) into v_cand, v_ins;
  return jsonb_build_object('window_from', p_from, 'window_to', p_to, 'applicable_obligations', v_cand, 'inserted', v_ins, 'already_existing', v_cand - v_ins);
end $function$;

CREATE OR REPLACE FUNCTION public.compliance_create_manual_instance(p_compliance uuid, p_location uuid, p_event_date date, p_remarks text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  on conflict (compliance_id, location_id, period_start) where status <> 'superseded' do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.compliance_instance where compliance_id = p_compliance and location_id = p_location and period_start = v_start and status <> 'superseded'; end if;
  return v_id;
end $function$;

create or replace function app.detect_exceptions() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_found int := 0; v_new int := 0; v_resolved int := 0; grace int;
begin
  grace := coalesce((select (value #>> '{}')::int from public.system_config where key = 'exception.overdue_grace_days'), 0);
  drop table if exists _det;
  create temp table _det (key text primary key, category text, severity text, descr text, instance_id uuid, licence_id uuid, evidence_id uuid, owner uuid) on commit drop;

  insert into _det
  select 'compliance_overdue:' || i.id, 'compliance_overdue', v.risk_level,
         'Compliance ' || m.code || ' (' || i.instance_no || ') for ' || to_char(i.period_start, 'Mon YYYY') || ' at ' || l.code || ' was due ' || i.due_date || ' and is not complete',
         i.id, null, null, i.owner_user_id
    from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.compliance_rule_version v on v.id = i.rule_version_id join public.location l on l.id = i.location_id
   where i.status in ('open','in_progress') and i.due_date + grace < current_date;

  insert into _det
  select 'evidence_missing:' || i.id || ':' || rq.document_type_id, 'evidence_missing', v.risk_level,
         'Mandatory document "' || dt.name || '" is missing for ' || i.instance_no, i.id, null, null, i.owner_user_id
    from public.compliance_instance i join public.compliance_rule_version v on v.id = i.rule_version_id and v.evidence_required
    join public.compliance_rule_evidence rq on rq.rule_version_id = v.id and rq.is_mandatory join public.document_type dt on dt.id = rq.document_type_id
   where i.status not in ('not_applicable','superseded') and (i.status = 'completed' or i.due_date < current_date)
     and not exists (select 1 from public.evidence e where e.compliance_instance_id = i.id and e.document_type_id = rq.document_type_id and e.is_current);

  insert into _det
  select 'evidence_rejected:' || e.id, 'evidence_rejected', v.risk_level, 'Evidence ' || e.evidence_no || ' was rejected: ' || coalesce(e.verification_remarks, ''), null, null, e.id, i.owner_user_id
    from public.evidence e join public.compliance_instance i on i.id = e.compliance_instance_id join public.compliance_rule_version v on v.id = i.rule_version_id
   where e.is_current and e.verification_status = 'rejected' and i.status not in ('not_applicable','superseded');
  insert into _det
  select 'evidence_expired:' || e.id, 'evidence_expired', coalesce(v.risk_level, li.risk_level, 'medium'), 'Evidence ' || e.evidence_no || ' expired on ' || e.expiry_date,
         null, null, e.id, coalesce(i.owner_user_id, li.owner_user_id)
    from public.evidence e left join public.compliance_instance i on i.id = e.compliance_instance_id left join public.compliance_rule_version v on v.id = i.rule_version_id left join public.licence li on li.id = e.licence_id
   where e.is_current and e.expiry_date is not null and e.expiry_date < current_date and coalesce(i.status, 'open') not in ('not_applicable','superseded') and coalesce(li.lifecycle_status, 'active') = 'active';

  insert into _det
  select 'licence_expired:' || li.id, 'licence_expired', case when app.severity_rank(coalesce(li.risk_level, 'medium')) >= 3 then 'critical' else 'high' end,
         'Licence ' || li.licence_no || ' (' || t.name || ') expired on ' || li.expiry_date, null, li.id, null, li.owner_user_id
    from public.licence li join public.licence_type t on t.id = li.licence_type_id where li.lifecycle_status = 'active' and li.expiry_date is not null and li.expiry_date < current_date;
  insert into _det
  select 'licence_expiring:' || li.id, 'licence_expiring', coalesce(li.risk_level, 'medium'),
         'Licence ' || li.licence_no || ' (' || t.name || ') expires on ' || li.expiry_date || ' (' || (li.expiry_date - current_date) || ' days)', null, li.id, null, li.owner_user_id
    from public.licence li join public.licence_type t on t.id = li.licence_type_id
   where li.lifecycle_status = 'active' and li.expiry_date is not null and li.expiry_date >= current_date and (li.expiry_date - current_date) <= li.renewal_lead_days
     and li.renewal_status not in ('renewed');

  -- D-001: an open obligation / active licence whose alert rule has no recipient AND for which nobody can be told (no escalation recipient, no dev fallback)
  insert into _det
  select 'alert_unroutable:' || i.id, 'alert_unroutable', 'high',
         'Alerts for ' || m.code || ' (' || i.instance_no || ') cannot reach anyone: rule ' || string_agg(distinct r.code, ', ') || ' has no valid recipient and no escalation recipient is configured. Assign an owner or configure routing.',
         i.id, null, null, i.owner_user_id
    from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.compliance_rule_version v on v.id = i.rule_version_id
    cross join lateral (values (coalesce(v.alert_rule_code, 'DEFAULT_COMPLIANCE_ALERT')), (coalesce(v.escalation_rule_code, 'DEFAULT_COMPLIANCE_ESCALATION'))) t(code)
    join app.active_alert_rules() r on r.code = t.code and coalesce(r.definition ->> 'applies', 'compliance') = 'compliance'
   where i.status in ('open','in_progress')
     and not exists (select 1 from app.resolve_recipients(r.definition -> 'recipients', i.owner_user_id, i.entity_id, i.location_id))
     and not exists (select 1 from app.unroutable_recipients(i.entity_id, i.location_id))
   group by i.id, m.code, i.instance_no, i.owner_user_id;
  insert into _det
  select 'alert_unroutable:' || li.id, 'alert_unroutable', 'high',
         'Alerts for licence ' || li.licence_no || ' cannot reach anyone: rule DEFAULT_LICENCE_ALERT has no valid recipient and no escalation recipient is configured. Assign an owner or configure routing.',
         null, li.id, null, li.owner_user_id
    from public.licence li join app.active_alert_rules() r on r.code = 'DEFAULT_LICENCE_ALERT'
   where li.lifecycle_status = 'active' and li.expiry_date is not null and li.renewal_status <> 'renewed'
     and not exists (select 1 from app.resolve_recipients(r.definition -> 'recipients', li.owner_user_id, li.entity_id, li.location_id))
     and not exists (select 1 from app.unroutable_recipients(li.entity_id, li.location_id));
  select count(*) into v_found from _det;

  with ins as (
    insert into public.exception (category, severity, description, compliance_instance_id, licence_id, evidence_id, entity_id, detection_key, source, owner_user_id)
    select d.category, d.severity, d.descr, d.instance_id, d.licence_id, d.evidence_id, null::uuid, d.key, 'auto', d.owner from _det d
    on conflict (detection_key) where status in ('open','acknowledged') do nothing returning 1)
  select count(*) into v_new from ins;

  perform set_config('app.audit_reason', 'Condition cleared automatically', true);
  update public.exception x set status = 'resolved', resolution = 'Condition cleared automatically', auto_resolved = true
   where x.source = 'auto' and x.status in ('open','acknowledged') and not exists (select 1 from _det d where d.key = x.detection_key);
  get diagnostics v_resolved = row_count;
  perform set_config('app.audit_reason', '', true);
  return jsonb_build_object('conditions_found', v_found, 'raised', v_new, 'auto_resolved', v_resolved);
end $$;

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
  -- F-2: future untouched obligations on/after the new effective date move to the new rule (actioned/completed ones stay pinned)
  perform app.reconcile_future_obligations(v.compliance_id, greatest(v.effective_from, current_date), p_reason);
end $$;

