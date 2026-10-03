-- 0023 D-001: no alert may disappear silently (owner-approved 2026-10-03; design docs/design/PHASE6_FOLLOWUPS.md section 1 and 6).
-- Resolution order when a fired alert rule has NO valid recipient:
--   1. the BFCL-configured escalation recipients (alert rule code UNROUTABLE_ESCALATION - configuration owned by BFCL, NOT seeded);
--   2. DEVELOPMENT ONLY (system_config environment.name = 'development'): active SUPER_ADMIN users in scope. Never in UAT/production;
--   3. nobody -> a durable UNROUTABLE exception (category alert_unroutable) on the record, shown in System Health and the Notification Centre.
-- Recipients found in 1 or 2 receive a durable in-app notification of category alert_unroutable (deduplicated, scope-respecting).
-- Also: job_finish may now keep a non-fatal warning on a SUCCEEDED run; the alert rule shape accepts an optional "critical" flag;
-- public.alert_routing_validation() lists active rules with no valid routing (blocking when critical / in production);
-- system_health() reports unroutable alerts and routing errors. No data is deleted; all objects are replaced in place.
-- Rollback: restore app.generate_alerts / app.run_alert_generation / app.detect_exceptions / app.job_finish / app.alert_rule_guard / public.system_health from migrations 0020, 0019, 0009;
--           drop function public.alert_routing_validation, app.unroutable_recipients, app.active_alert_rules, app.is_development;
--           delete from lov_value where code = 'alert_unroutable'; restore the notification category check from 0020.

-- ---------- helpers ----------
create or replace function app.is_development() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') = 'development'
$$;

create or replace function app.active_alert_rules() returns table (code text, definition jsonb)
language sql stable security definer set search_path = public as $$
  select distinct on (c.code) c.code, c.definition from public.config_definition c
   where c.kind = 'alert_rule' and c.status = 'active' and (c.effective_from is null or c.effective_from <= current_date) and (c.effective_to is null or c.effective_to >= current_date)
   order by c.code, c.version desc
$$;

-- who is told when an alert has no recipient: configured escalation recipients; in DEVELOPMENT additionally the Super Admin(s)
create or replace function app.unroutable_recipients(p_entity uuid, p_location uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct u from (
    select rc.u from app.active_alert_rules() r
      cross join lateral app.resolve_recipients(
        (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements_text(r.definition -> 'recipients') x where x <> 'owner'), null, p_entity, p_location) rc(u)
     where r.code = 'UNROUTABLE_ESCALATION'
    union all
    select ur.user_id from public.user_role ur join public.role ro on ro.id = ur.role_id
     where app.is_development() and ro.code = 'SUPER_ADMIN' and app.user_scope_ok(ur.user_id, p_entity, p_location)
  ) x where u is not null
$$;
revoke all on function app.is_development(), app.active_alert_rules(), app.unroutable_recipients(uuid, uuid) from public, anon, authenticated;

-- ---------- notification category + exception category ----------
alter table public.notification drop constraint notification_category_check;
alter table public.notification add constraint notification_category_check
  check (category in ('compliance_reminder','compliance_escalation','licence_expiry','alert_unroutable'));

insert into public.lov_value (set_id, code, label, sort_order, color)
select s.id, 'alert_unroutable', 'Alert has no valid recipient', 70, 'red' from public.lov_set s where s.code = 'EXCEPTION_CATEGORY'
on conflict (set_id, code) do nothing;

-- ---------- job_finish: a succeeded run may carry a warning ----------
create or replace function app.job_finish(p_run uuid, p_ok boolean, p_records int default null, p_error jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare r public.job_run; d public.job_definition;
begin
  select * into r from public.job_run where id = p_run for update;
  if not found then raise exception 'Unknown run %', p_run using errcode = '22023'; end if;
  select * into d from public.job_definition where code = r.job_code;
  if p_ok then
    update public.job_run set status = 'succeeded', completed_at = now(), records_processed = p_records, error_detail = p_error, next_retry_at = null where id = p_run;   -- p_error = optional non-fatal warning
  elsif r.attempt < d.max_attempts then
    update public.job_run set status = 'retry_wait', completed_at = now(), records_processed = p_records, error_detail = p_error,
           next_retry_at = now() + make_interval(secs => d.retry_backoff_seconds * r.attempt) where id = p_run;
  else
    update public.job_run set status = 'failed', completed_at = now(), records_processed = p_records, error_detail = p_error, next_retry_at = null where id = p_run;
  end if;
end $$;

-- ---------- alert rule shape: optional "critical" flag ----------
create or replace function app.alert_rule_guard() returns trigger language plpgsql as $$
declare d jsonb := new.definition; o jsonb;
begin
  if new.kind <> 'alert_rule' then return new; end if;
  if jsonb_typeof(d -> 'offsets') is distinct from 'array' or jsonb_array_length(d -> 'offsets') = 0 then raise exception 'alert_rule needs a non-empty offsets array' using errcode = '23514'; end if;
  for o in select * from jsonb_array_elements(d -> 'offsets') loop
    if jsonb_typeof(o) <> 'number' or (o #>> '{}') !~ '^-?\d{1,3}$' or abs((o #>> '{}')::int) > 365 then raise exception 'alert offsets must be whole days between -365 and 365' using errcode = '23514'; end if;
  end loop;
  if jsonb_typeof(d -> 'channels') is distinct from 'array' or jsonb_array_length(d -> 'channels') = 0
     or exists (select 1 from jsonb_array_elements_text(d -> 'channels') c where c not in ('in_app','email')) then
    raise exception 'alert channels must be a non-empty subset of in_app, email' using errcode = '23514';
  end if;
  if jsonb_typeof(d -> 'recipients') is distinct from 'array' or jsonb_array_length(d -> 'recipients') = 0
     or exists (select 1 from jsonb_array_elements_text(d -> 'recipients') r where r !~ '^(owner|role:[A-Z][A-Z0-9_]{1,40}|user:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$') then
    raise exception 'alert recipients must be owner, role:<ROLE_CODE> or user:<uuid>' using errcode = '23514';
  end if;
  if coalesce(d ->> 'applies', 'compliance') not in ('compliance','licence') then raise exception 'alert applies must be compliance or licence' using errcode = '23514'; end if;
  if d ? 'critical' and jsonb_typeof(d -> 'critical') <> 'boolean' then raise exception 'alert critical must be true or false' using errcode = '23514'; end if;
  return new;
end $$;

-- ---------- routing validation (blocking for critical rules and for the escalation rule in production) ----------
create or replace function public.alert_routing_validation() returns table (rule_code text, severity text, problem text)
language plpgsql stable security definer set search_path = public as $$
declare r record; t text; n int; prod boolean := not app.is_development(); crit boolean; sev text;
begin
  if not (app.has_permission('health.read') or app.has_permission('config.read')) then raise exception 'permission denied' using errcode = '42501'; end if;
  for r in select * from app.active_alert_rules() loop
    crit := coalesce((r.definition ->> 'critical')::boolean, false) or r.code = 'UNROUTABLE_ESCALATION';
    sev := case when crit then 'error' else 'warning' end;
    n := 0;
    for t in select jsonb_array_elements_text(r.definition -> 'recipients') loop
      if t = 'owner' then n := n + 1;
      elsif t like 'role:%' then
        if not exists (select 1 from public.role where code = substr(t, 6)) then rule_code := r.code; severity := sev; problem := 'recipient ' || t || ': no such role'; return next;
        elsif not exists (select 1 from public.user_role ur join public.role ro on ro.id = ur.role_id join public.app_user u on u.id = ur.user_id where ro.code = substr(t, 6) and u.status = 'active') then
          rule_code := r.code; severity := sev; problem := 'recipient ' || t || ': no active user holds this role'; return next;
        else n := n + 1; end if;
      elsif t like 'user:%' then
        if not exists (select 1 from public.app_user u where u.id = substr(t, 6)::uuid and u.status = 'active') then
          rule_code := r.code; severity := sev; problem := 'recipient ' || t || ': user is not active'; return next;
        else n := n + 1; end if;
      end if;
    end loop;
    if n = 0 then rule_code := r.code; severity := sev; problem := 'no valid routing: none of the recipients can currently receive an alert'; return next; end if;
  end loop;
  if not exists (select 1 from app.active_alert_rules() a where a.code = 'UNROUTABLE_ESCALATION') then
    rule_code := 'UNROUTABLE_ESCALATION'; severity := case when prod then 'error' else 'warning' end;
    problem := case when prod then 'BLOCKING for production: no active UNROUTABLE_ESCALATION rule - alerts with no recipient would only appear as exceptions. BFCL must configure escalation recipients'
                    else 'not configured (development: Super Admin fallback is active; production requires BFCL escalation recipients)' end;
    return next;
  end if;
  return;
end $$;
revoke all on function public.alert_routing_validation() from public, anon;
grant execute on function public.alert_routing_validation() to authenticated;

-- ---------- exception detection: + alert_unroutable (only when NOBODY can be told) ----------
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
   where i.status <> 'not_applicable' and (i.status = 'completed' or i.due_date < current_date)
     and not exists (select 1 from public.evidence e where e.compliance_instance_id = i.id and e.document_type_id = rq.document_type_id and e.is_current);

  insert into _det
  select 'evidence_rejected:' || e.id, 'evidence_rejected', v.risk_level, 'Evidence ' || e.evidence_no || ' was rejected: ' || coalesce(e.verification_remarks, ''), null, null, e.id, i.owner_user_id
    from public.evidence e join public.compliance_instance i on i.id = e.compliance_instance_id join public.compliance_rule_version v on v.id = i.rule_version_id
   where e.is_current and e.verification_status = 'rejected' and i.status <> 'not_applicable';
  insert into _det
  select 'evidence_expired:' || e.id, 'evidence_expired', coalesce(v.risk_level, li.risk_level, 'medium'), 'Evidence ' || e.evidence_no || ' expired on ' || e.expiry_date,
         null, null, e.id, coalesce(i.owner_user_id, li.owner_user_id)
    from public.evidence e left join public.compliance_instance i on i.id = e.compliance_instance_id left join public.compliance_rule_version v on v.id = i.rule_version_id left join public.licence li on li.id = e.licence_id
   where e.is_current and e.expiry_date is not null and e.expiry_date < current_date and coalesce(i.status, 'open') <> 'not_applicable' and coalesce(li.lifecycle_status, 'active') = 'active';

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

-- ---------- alert generation: unrouted alerts go to the escalation recipients; unreachable ones are counted, never dropped silently ----------
create or replace function app.generate_alerts() returns jsonb
language plpgsql security definer set search_path = public as $$
declare catchup int; email_on boolean; n_c int := 0; n_l int := 0; n_u int := 0; n_x int := 0; n_x2 int := 0;
begin
  catchup := coalesce((select (value #>> '{}')::int from public.system_config where key = 'alert.catchup_days'), 3);
  email_on := coalesce((select value ->> 'state' from public.system_config where key = 'integration.gmail'), 'NOT_CONFIGURED') = 'CONFIGURED';
  drop table if exists _fired;
  create temp table _fired (kind text, id uuid, label text, sub text, entity_id uuid, location_id uuid, owner_user_id uuid, rule_code text, definition jsonb, off int, is_esc boolean) on commit drop;

  insert into _fired
  with rules as (select * from app.active_alert_rules()),
  inst as (
    select i.id, i.instance_no, i.due_date, i.entity_id, i.location_id, i.owner_user_id, m.code as mcode,
           coalesce(v.alert_rule_code, 'DEFAULT_COMPLIANCE_ALERT') as ac, coalesce(v.escalation_rule_code, 'DEFAULT_COMPLIANCE_ESCALATION') as ec
      from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.compliance_rule_version v on v.id = i.rule_version_id
     where i.status in ('open','in_progress'))
  select distinct on (inst.id, r.code) 'compliance', inst.id,
         case when (o.v)::int < 0 then inst.mcode || ' due in ' || (-(o.v)::int) || ' day(s)' when (o.v)::int = 0 then inst.mcode || ' is due today' else inst.mcode || ' overdue by ' || (o.v) || ' day(s)' end,
         inst.instance_no || ' - due ' || inst.due_date, inst.entity_id, inst.location_id, inst.owner_user_id, r.code, r.definition, (o.v)::int, (t.code = inst.ec and t.code <> inst.ac)
    from inst cross join lateral (values (inst.ac), (inst.ec)) t(code)
    join rules r on r.code = t.code and coalesce(r.definition ->> 'applies', 'compliance') = 'compliance'
    cross join lateral jsonb_array_elements_text(r.definition -> 'offsets') o(v)
   where inst.due_date + (o.v)::int <= current_date and inst.due_date + (o.v)::int >= current_date - catchup
   order by inst.id, r.code, (o.v)::int desc;                  -- only the MOST RECENT reached offset

  insert into _fired
  with rules as (select * from app.active_alert_rules())
  select distinct on (l.id, r.code) 'licence', l.id,
         case when (o.v)::int < 0 then t.name || ' expires in ' || (-(o.v)::int) || ' day(s)' when (o.v)::int = 0 then t.name || ' expires today' else t.name || ' expired ' || (o.v) || ' day(s) ago' end,
         l.licence_no || ' - expiry ' || l.expiry_date, l.entity_id, l.location_id, l.owner_user_id, r.code, r.definition, (o.v)::int, false
    from public.licence l join public.licence_type t on t.id = l.licence_type_id
    join rules r on r.code = 'DEFAULT_LICENCE_ALERT'
    cross join lateral jsonb_array_elements_text(r.definition -> 'offsets') o(v)
   where l.lifecycle_status = 'active' and l.expiry_date is not null and l.renewal_status <> 'renewed'
     and l.expiry_date + (o.v)::int <= current_date and l.expiry_date + (o.v)::int >= current_date - catchup
   order by l.id, r.code, (o.v)::int desc;

  -- routed alerts (unchanged behaviour)
  with targets as (
    select f.*, ch.channel, rc.u as user_id from _fired f
      cross join lateral jsonb_array_elements_text(f.definition -> 'channels') ch(channel)
      cross join lateral app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id) rc(u)),
  ins as (
    insert into public.notification (user_id, channel, category, title, body, link_kind, link_id, dedupe_key, status, delivered_at)
    select user_id, channel, case when kind = 'licence' then 'licence_expiry' when is_esc then 'compliance_escalation' else 'compliance_reminder' end, label, sub,
           case when kind = 'licence' then 'licence' else 'compliance_instance' end, id,
           case when kind = 'licence' then 'lic:' else 'ci:' end || id || ':' || rule_code || ':' || off || ':' || user_id || ':' || channel,
           case when channel = 'email' then 'queued' else 'delivered' end, case when channel = 'email' then null else now() end
      from targets where channel = 'in_app' or email_on
    on conflict (dedupe_key) do nothing returning category)
  select count(*) filter (where category <> 'licence_expiry'), count(*) filter (where category = 'licence_expiry') into n_c, n_l from ins;

  -- D-001: fired alerts whose rule resolves to NOBODY -> durable alert_unroutable notification to the escalation recipients
  with unrouted as (
    select f.* from _fired f where not exists (select 1 from app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id))),
  ins as (
    insert into public.notification (user_id, channel, category, title, body, link_kind, link_id, dedupe_key, status, delivered_at)
    select u.uid, 'in_app', 'alert_unroutable', 'UNROUTED: ' || f.label, f.sub || ' - rule ' || f.rule_code || ' has no valid recipient; delivered to the escalation recipients so it is not lost',
           case when f.kind = 'licence' then 'licence' else 'compliance_instance' end, f.id,
           'unr:' || f.kind || ':' || f.id || ':' || f.rule_code || ':' || f.off || ':' || u.uid, 'delivered', now()
      from unrouted f cross join lateral app.unroutable_recipients(f.entity_id, f.location_id) u(uid)
    on conflict (dedupe_key) do nothing returning 1)
  select count(*) into n_u from ins;
  -- fired alerts that reached nobody at all (the exception from detect_exceptions makes these visible as well)
  select count(*) into n_x from _fired f
   where not exists (select 1 from app.resolve_recipients(f.definition -> 'recipients', f.owner_user_id, f.entity_id, f.location_id))
     and not exists (select 1 from app.unroutable_recipients(f.entity_id, f.location_id));

  return jsonb_build_object('compliance_notifications', n_c, 'licence_notifications', n_l, 'unroutable_notifications', n_u, 'unreachable', n_x, 'email_enabled', email_on);
end $$;

create or replace function app.run_alert_generation(p_env text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j record; res jsonb;
begin
  select * into j from app.job_start('alert_generation', to_char(current_date, 'YYYY-MM-DD'), p_env, 'schedule');
  if not j.should_run then return jsonb_build_object('ran', false, 'reason', j.reason); end if;
  begin
    res := app.generate_alerts();
    perform app.job_finish(j.run_id, true, (res ->> 'compliance_notifications')::int + (res ->> 'licence_notifications')::int + (res ->> 'unroutable_notifications')::int,
      case when (res ->> 'unreachable')::int > 0 then jsonb_build_object('warning', 'alerts_unreachable', 'unreachable', (res ->> 'unreachable')::int,
             'message', 'Fired alerts had no valid recipient and no escalation recipient (see Exceptions: alert_unroutable)') end);
    return res || jsonb_build_object('ran', true);
  exception when others then
    perform app.job_finish(j.run_id, false, null, jsonb_build_object('message', sqlerrm, 'state', sqlstate));
    return jsonb_build_object('ran', true, 'error', sqlerrm);
  end;
end $$;
revoke all on function app.generate_alerts(), app.run_alert_generation(text) from public;
grant execute on function app.generate_alerts(), app.run_alert_generation(text) to service_role;

-- ---------- System Health: unroutable alerts + routing validation ----------
create or replace function public.system_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_schema text; v_last jsonb; v_failed jsonb; v_cfg jsonb; v_warn jsonb;
begin
  if not app.has_permission('health.read') then raise exception 'permission denied' using errcode = '42501'; end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into v_schema;
  end if;
  select to_jsonb(j) into v_last from (select job_code, status, started_at, completed_at, records_processed from public.job_run order by started_at desc limit 1) j;
  select to_jsonb(j) into v_failed from (select job_code, status, started_at, attempt, error_detail ->> 'message' as message
                                           from public.job_run where status in ('failed','retry_wait') order by started_at desc limit 1) j;
  select coalesce(jsonb_object_agg(replace(key, 'integration.', ''), value -> 'state'), '{}'::jsonb) into v_cfg
    from public.system_config where key like 'integration.%';
  select to_jsonb(j) into v_warn from (select job_code, started_at, error_detail ->> 'message' as message from public.job_run
                                         where status = 'succeeded' and error_detail ->> 'warning' is not null order by started_at desc limit 1) j;
  return jsonb_build_object(
    'database', jsonb_build_object('connected', true, 'server_time', now(), 'postgres_major', current_setting('server_version_num')::int / 10000),
    'schema_version', v_schema,
    'integrations', v_cfg,
    'latest_job', v_last, 'latest_failed_job', v_failed,
    'jobs_failed_24h', (select count(*) from public.job_run where status in ('failed','retry_wait') and started_at > now() - interval '24 hours'),
    'unroutable_alerts', (select count(*) from public.exception where category = 'alert_unroutable' and status in ('open','acknowledged')),
    'unroutable_notifications_7d', (select count(*) from public.notification where category = 'alert_unroutable' and created_at > now() - interval '7 days'),
    'alert_routing', jsonb_build_object('errors', (select count(*) from public.alert_routing_validation() where severity = 'error'),
                                        'warnings', (select count(*) from public.alert_routing_validation() where severity = 'warning')),
    'latest_job_warning', v_warn,
    'environment', case when app.is_development() then 'development' else 'non-development' end);
end $$;
revoke all on function public.system_health() from public, anon;
grant execute on function public.system_health() to authenticated;
