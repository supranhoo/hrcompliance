-- 0038 Management dashboard: one filterable, read-only function over the existing scope-controlled views, and the responsible department on the compliance view (for drill-down).
-- Filters: entity, location, department (the master's responsible department - D-038) and a due-date period. Everything runs as the caller (SECURITY INVOKER), so role permissions and entity/location/department scope
-- apply exactly as on the registers. Definitions follow compliance_dashboard() and the reports. "Critical" is the highest-ranked value of the RISK / SEVERITY lists (by sort order), not a hardcoded name; "licences expiring"
-- uses the largest value of the licence.expiry_thresholds setting. No targets or RAG thresholds are defined here.
-- Rollback: restore public.report_compliance_performance from migration 0037; drop function public.management_dashboard(uuid, uuid, uuid, date, date); drop function app.mgmt_instances(uuid, uuid, uuid); recreate public.v_compliance_instance (migration 0017, without owner_department_id) and public.v_exception (migration 0019, without department_id).
create or replace view public.v_compliance_instance with (security_invoker = true) as
SELECT i.id,
    i.instance_no,
    i.compliance_id,
    m.code AS compliance_code,
    m.name AS compliance_name,
    m.domain,
    m.category_id,
    i.rule_version_id,
    v.compliance_type,
    v.frequency,
    v.risk_level,
    v.criticality,
    v.evidence_required,
    i.entity_id,
    i.location_id,
    l.code AS location_code,
    l.name AS location_name,
    i.period_start,
    i.period_end,
    i.due_date,
    i.status,
    i.owner_user_id,
    i.completed_on,
    i.remarks,
    (i.due_date - CURRENT_DATE) AS days_to_due,
    app.due_state(i.status, i.due_date) AS due_state,
        CASE
            WHEN ((i.status = ANY (ARRAY['open'::text, 'in_progress'::text])) AND (i.due_date < CURRENT_DATE)) THEN (CURRENT_DATE - i.due_date)
            ELSE 0
        END AS days_overdue,
    m.owner_department_id
   FROM (((compliance_instance i
     JOIN compliance_master m ON ((m.id = i.compliance_id)))
     JOIN compliance_rule_version v ON ((v.id = i.rule_version_id)))
     JOIN location l ON ((l.id = i.location_id)))
  WHERE (i.status <> 'superseded'::text);

-- Same for exceptions: the department of the obligation an exception belongs to (null for licence/evidence-only exceptions), so registers can filter and drill by it.
create or replace view public.v_exception with (security_invoker = true) as
SELECT id,
    exception_no,
    category,
    severity,
    description,
    status,
    source,
    detected_at,
    due_date,
    owner_user_id,
    compliance_instance_id,
    licence_id,
    evidence_id,
    entity_id,
    location_id,
    resolution,
    resolved_at,
    auto_resolved,
        CASE
            WHEN (resolved_at IS NULL) THEN (CURRENT_DATE - (detected_at)::date)
            ELSE ((resolved_at)::date - (detected_at)::date)
        END AS age_days,
        CASE
            WHEN (resolved_at IS NOT NULL) THEN 'closed'::text
            WHEN ((CURRENT_DATE - (detected_at)::date) <= 7) THEN '0-7'::text
            WHEN ((CURRENT_DATE - (detected_at)::date) <= 30) THEN '8-30'::text
            WHEN ((CURRENT_DATE - (detected_at)::date) <= 90) THEN '31-90'::text
            ELSE '90+'::text
        END AS age_bucket,
    ((resolved_at IS NULL) AND (due_date IS NOT NULL) AND (due_date < CURRENT_DATE)) AS target_breached,
    app.instance_department(x.compliance_instance_id) AS department_id
   FROM exception x;


-- report_compliance_performance (0037) selected owner_department_id from compliance_master next to v.*; now that the view carries the same column that reference would be ambiguous.
-- Identical function, reading the department straight from the view. (0037 is hash-locked and live, so the fix is made here.)
create or replace function public.report_compliance_performance(p_dimension text, p_from date default null, p_to date default null)
returns table (group_key text, group_label text, total bigint, completed bigint, completed_on_time bigint, completed_late bigint, overdue_open bigint, upcoming_open bigint, due_to_date bigint, on_time_to_date bigint, completed_to_date bigint, on_time_pct numeric, compliance_pct numeric)
language plpgsql stable security invoker as $$
declare d text := lower(coalesce(p_dimension, '')); f date := coalesce(p_from, (current_date - interval '12 months')::date); t date := coalesce(p_to, current_date);
begin
  if not app.has_permission('compliance.read') then raise exception 'permission denied' using errcode = '42501'; end if;
  if d not in ('location','department','category','risk','domain','owner','month') then raise exception 'unknown report dimension %', p_dimension using errcode = '22023'; end if;
  if f > t then raise exception 'the start date is after the end date' using errcode = '22023'; end if;
  if t - f > 3660 then raise exception 'choose a period of at most 10 years' using errcode = '22023'; end if;
  return query
  with base as (
    select v.*, dep.name as dep_name, cat.name as cat_name, ou.email::text as owner_email
      from public.v_compliance_instance v
      left join public.department dep on dep.id = v.owner_department_id
      left join public.compliance_category cat on cat.id = v.category_id
      left join public.app_user ou on ou.id = v.owner_user_id
     where v.status <> 'not_applicable' and v.due_date between f and t),
  keyed as (
    select b.*,
      case d when 'location' then b.location_code when 'department' then coalesce(b.owner_department_id::text, '-') when 'category' then coalesce(b.category_id::text, '-')
             when 'risk' then coalesce(b.risk_level, '-') when 'domain' then coalesce(b.domain, '-') when 'owner' then coalesce(b.owner_user_id::text, '-')
             else to_char(b.due_date, 'YYYY-MM') end as k,
      case d when 'location' then b.location_code || ' · ' || b.location_name when 'department' then coalesce(b.dep_name, '(no responsible department)') when 'category' then coalesce(b.cat_name, '(no category)')
             when 'risk' then coalesce(b.risk_level, '(none)') when 'domain' then coalesce(b.domain, '(none)') when 'owner' then coalesce(b.owner_email, '(no owner, or not visible to you)')
             else to_char(b.due_date, 'YYYY-MM') end as lbl
      from base b)
  select k, max(lbl), count(*),
         count(*) filter (where status = 'completed'),
         count(*) filter (where status = 'completed' and completed_on <= due_date),
         count(*) filter (where status = 'completed' and completed_on > due_date),
         count(*) filter (where status in ('open','in_progress') and due_date < current_date),
         count(*) filter (where status in ('open','in_progress') and due_date >= current_date),
         count(*) filter (where due_date <= current_date),
         count(*) filter (where status = 'completed' and completed_on <= due_date and due_date <= current_date),
         count(*) filter (where status = 'completed' and due_date <= current_date),
         case when count(*) filter (where due_date <= current_date) > 0 then round(100.0 * count(*) filter (where status = 'completed' and completed_on <= due_date and due_date <= current_date) / count(*) filter (where due_date <= current_date), 1) end,
         case when count(*) filter (where due_date <= current_date) > 0 then round(100.0 * count(*) filter (where status = 'completed' and due_date <= current_date) / count(*) filter (where due_date <= current_date), 1) end
    from keyed group by k
   order by case when d = 'month' then k end, 3 desc, 2;
end $$;

create or replace function app.mgmt_instances(p_entity uuid, p_location uuid, p_department uuid) returns setof public.v_compliance_instance
language sql stable security invoker as $$
  select * from public.v_compliance_instance v
   where v.status <> 'not_applicable' and (p_entity is null or v.entity_id = p_entity) and (p_location is null or v.location_id = p_location) and (p_department is null or v.owner_department_id = p_department)
$$;
revoke all on function app.mgmt_instances(uuid, uuid, uuid) from public, anon;
grant execute on function app.mgmt_instances(uuid, uuid, uuid) to authenticated;

create or replace function public.management_dashboard(p_entity uuid default null, p_location uuid default null, p_department uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security invoker as $$
declare
  f date := coalesce(p_from, (current_date - interval '12 months')::date); t date := coalesce(p_to, current_date);
  top_risk text; top_sev text; horizon int; k jsonb; trend jsonb; risk jsonb; loc jsonb; dep jsonb; up jsonb; cx jsonb; ageing jsonb; lic jsonb; exc_open int; exc_crit int;
begin
  if not app.has_permission('compliance.read') then raise exception 'permission denied' using errcode = '42501'; end if;
  if f > t then raise exception 'the start date is after the end date' using errcode = '22023'; end if;
  if t - f > 3660 then raise exception 'choose a period of at most 10 years' using errcode = '22023'; end if;
  select v.code into top_risk from public.lov_value v join public.lov_set s on s.id = v.set_id where s.code = 'RISK' and v.is_active order by v.sort_order desc limit 1;
  select v.code into top_sev from public.lov_value v join public.lov_set s on s.id = v.set_id where s.code = 'SEVERITY' and v.is_active order by v.sort_order desc limit 1;
  horizon := coalesce((select max(x::int) from system_config c, jsonb_array_elements_text(c.value) x where c.key = 'licence.expiry_thresholds'), 90);

  select jsonb_build_object(
    'total_applicable', count(*) filter (where due_date between f and t),
    'due_this_month', count(*) filter (where status in ('open','in_progress') and due_date >= date_trunc('month', current_date)::date and due_date < (date_trunc('month', current_date) + interval '1 month')::date),
    'overdue', count(*) filter (where status in ('open','in_progress') and due_date < current_date),
    'critical_open', count(*) filter (where status in ('open','in_progress') and risk_level = top_risk),
    'critical_overdue', count(*) filter (where status in ('open','in_progress') and risk_level = top_risk and due_date < current_date),
    'due_to_date', count(*) filter (where due_date between f and t and due_date <= current_date),
    'completed_to_date', count(*) filter (where due_date between f and t and due_date <= current_date and status = 'completed'),
    'on_time_to_date', count(*) filter (where due_date between f and t and due_date <= current_date and status = 'completed' and completed_on <= due_date))
  into k from app.mgmt_instances(p_entity, p_location, p_department);
  k := k || jsonb_build_object('compliance_pct', case when (k ->> 'due_to_date')::int > 0 then round(100.0 * (k ->> 'completed_to_date')::int / (k ->> 'due_to_date')::int, 1) end,
                               'on_time_pct', case when (k ->> 'due_to_date')::int > 0 then round(100.0 * (k ->> 'on_time_to_date')::int / (k ->> 'due_to_date')::int, 1) end);

  -- exceptions: entity/location as given; the department filter keeps exceptions of that department's obligations (licence/evidence-only exceptions have no department)
  select count(*) filter (where e.status in ('open','acknowledged')), count(*) filter (where e.status in ('open','acknowledged') and e.severity = top_sev) into exc_open, exc_crit
    from public.v_exception e where (p_entity is null or e.entity_id = p_entity) and (p_location is null or e.location_id = p_location)
     and (p_department is null or app.instance_department(e.compliance_instance_id) = p_department);
  select coalesce(jsonb_object_agg(age_bucket, c), '{}'::jsonb) into ageing from (select e.age_bucket, count(*) c from public.v_exception e where e.status in ('open','acknowledged') and (p_entity is null or e.entity_id = p_entity) and (p_location is null or e.location_id = p_location)
     and (p_department is null or app.instance_department(e.compliance_instance_id) = p_department) group by e.age_bucket) a;
  select coalesce(jsonb_agg(row_to_json(x) order by x.age_days desc, x.exception_no), '[]'::jsonb) into cx from (
    select e.id, e.exception_no, e.category, e.severity, e.description, e.age_days, e.target_breached, l.code as location_code
      from public.v_exception e left join public.location l on l.id = e.location_id
     where e.status in ('open','acknowledged') and e.severity = top_sev and (p_entity is null or e.entity_id = p_entity) and (p_location is null or e.location_id = p_location)
       and (p_department is null or app.instance_department(e.compliance_instance_id) = p_department)
     order by e.age_days desc, e.exception_no limit 10) x;

  -- licences (no department dimension: the department filter does not apply to them)
  select jsonb_build_object('expiring', count(*) filter (where lifecycle_status = 'active' and expiry_date is not null and expiry_date >= current_date and expiry_date <= current_date + horizon),
                            'expired', count(*) filter (where lifecycle_status = 'active' and expiry_date is not null and expiry_date < current_date), 'horizon_days', horizon, 'department_filter_applies', false)
    into lic from public.v_licence_status s where (p_entity is null or s.entity_id = p_entity) and (p_location is null or s.location_id = p_location);

  select coalesce(jsonb_agg(row_to_json(x) order by x.month), '[]'::jsonb) into trend from (
    select to_char(due_date, 'YYYY-MM') as month, count(*) as due, count(*) filter (where status = 'completed' and completed_on <= due_date) as completed_on_time, count(*) filter (where status = 'completed' and completed_on > due_date) as completed_late,
           count(*) filter (where status in ('open','in_progress') and due_date < current_date) as overdue_open, count(*) filter (where status in ('open','in_progress') and due_date >= current_date) as upcoming_open,
           count(*) filter (where due_date <= current_date) as due_to_date,
           case when count(*) filter (where due_date <= current_date) > 0 then round(100.0 * count(*) filter (where status = 'completed' and due_date <= current_date) / count(*) filter (where due_date <= current_date), 1) end as compliance_pct
      from app.mgmt_instances(p_entity, p_location, p_department) where due_date between f and t group by 1) x;

  select coalesce(jsonb_agg(row_to_json(x) order by x.sort_order), '[]'::jsonb) into risk from (
    select v.code as level, v.label, v.sort_order, count(i.id) filter (where i.status in ('open','in_progress')) as open, count(i.id) filter (where i.status in ('open','in_progress') and i.due_date < current_date) as overdue
      from public.lov_value v join public.lov_set s on s.id = v.set_id and s.code = 'RISK'
      left join app.mgmt_instances(p_entity, p_location, p_department) i on i.risk_level = v.code
     where v.is_active group by v.code, v.label, v.sort_order) x;

  select coalesce(jsonb_agg(row_to_json(x) order by x.overdue desc, x.open desc, x.code), '[]'::jsonb) into loc from (
    select i.location_code as code, max(i.location_name) as name, count(*) filter (where i.due_date between f and t) as total, count(*) filter (where i.status in ('open','in_progress')) as open,
           count(*) filter (where i.status in ('open','in_progress') and i.due_date < current_date) as overdue, count(*) filter (where i.due_date between f and t and i.due_date <= current_date) as due_to_date,
           count(*) filter (where i.due_date between f and t and i.due_date <= current_date and i.status = 'completed') as completed_to_date,
           case when count(*) filter (where i.due_date between f and t and i.due_date <= current_date) > 0 then round(100.0 * count(*) filter (where i.due_date between f and t and i.due_date <= current_date and i.status = 'completed') / count(*) filter (where i.due_date between f and t and i.due_date <= current_date), 1) end as compliance_pct
      from app.mgmt_instances(p_entity, p_location, p_department) i group by i.location_code order by 5 desc, 4 desc, 1 limit 12) x;

  select coalesce(jsonb_agg(row_to_json(x) order by x.overdue desc, x.open desc, x.name), '[]'::jsonb) into dep from (
    select i.owner_department_id as id, coalesce(d.name, '(no responsible department)') as name, count(*) filter (where i.due_date between f and t) as total, count(*) filter (where i.status in ('open','in_progress')) as open,
           count(*) filter (where i.status in ('open','in_progress') and i.due_date < current_date) as overdue, count(*) filter (where i.due_date between f and t and i.due_date <= current_date) as due_to_date,
           count(*) filter (where i.due_date between f and t and i.due_date <= current_date and i.status = 'completed') as completed_to_date,
           case when count(*) filter (where i.due_date between f and t and i.due_date <= current_date) > 0 then round(100.0 * count(*) filter (where i.due_date between f and t and i.due_date <= current_date and i.status = 'completed') / count(*) filter (where i.due_date between f and t and i.due_date <= current_date), 1) end as compliance_pct
      from app.mgmt_instances(p_entity, p_location, p_department) i left join public.department d on d.id = i.owner_department_id group by i.owner_department_id, d.name limit 12) x;

  select coalesce(jsonb_agg(row_to_json(x) order by x.due_date, x.instance_no), '[]'::jsonb) into up from (
    select i.instance_no, i.compliance_code, i.compliance_name, i.location_code, i.due_date, i.risk_level, i.due_state
      from app.mgmt_instances(p_entity, p_location, p_department) i where i.status in ('open','in_progress') and i.due_date between current_date and current_date + 30 order by i.due_date, i.instance_no limit 15) x;

  return jsonb_build_object('generated_at', now(), 'period', jsonb_build_object('from', f, 'to', t),
    'filters', jsonb_build_object('entity_id', p_entity, 'location_id', p_location, 'department_id', p_department),
    'top_risk_level', top_risk, 'top_severity', top_sev,
    'kpis', k || jsonb_build_object('open_exceptions', exc_open, 'critical_exceptions', exc_crit, 'licences_expiring', lic -> 'expiring', 'licences_expired', lic -> 'expired'),
    'licences', lic, 'trend', trend, 'risk', risk, 'by_location', loc, 'by_department', dep, 'upcoming', up, 'critical_exceptions', cx, 'exception_ageing', ageing,
    'definitions', jsonb_build_object(
      'total_applicable', 'Obligations due in the chosen period (not applicable excluded).',
      'due_this_month', 'Open or in progress, due in the current calendar month.',
      'overdue', 'Open or in progress with a due date before today (all periods).',
      'critical', 'Open or in progress at the highest risk level on the Risk list.',
      'open_exceptions', 'Open or acknowledged exceptions.',
      'licences_expiring', 'Active licences expiring within the longest licence expiry threshold.',
      'compliance_pct', 'Completed ÷ obligations already due, in the period.',
      'department', 'The responsible department of the compliance master. Licences have no department.'));
end $$;
revoke all on function public.management_dashboard(uuid, uuid, uuid, date, date) from public, anon;
grant execute on function public.management_dashboard(uuid, uuid, uuid, date, date) to authenticated;
