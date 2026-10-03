-- 0021 Operational compliance dashboard aggregates (Phase 6.7).
-- All numbers are computed in the database from the RLS-scoped views (SECURITY INVOKER), so each user sees ONLY what their scope allows,
-- and nothing is computed from raw tables in the browser. The function refuses callers without compliance.read: a "0 overdue" shown
-- to someone who cannot see the data would be misleading. Percentages are NULL (not 0%) when there is nothing to measure.
-- Definitions (also returned in the payload so the UI can show them):
--   due so far        = non-"not applicable" obligations with due_date <= today
--   compliance %      = completed / due so far              (completed at any time)
--   on-time %         = completed on or before due / due so far
--   overdue           = open or in progress, due_date < today
--   due soon          = open or in progress, due within compliance.due_soon_days
--   next 30 days      = open or in progress, due today .. today+30
-- Rollback: drop function public.compliance_dashboard();
create or replace function public.compliance_dashboard() returns jsonb
language plpgsql stable as $$
declare res jsonb; o jsonb; e jsonb; ev jsonb; l jsonb; loc jsonb; up jsonb; due_so_far int; completed_due int; on_time int;
begin
  if not app.has_permission('compliance.read') then raise exception 'permission denied' using errcode = '42501'; end if;

  select jsonb_build_object(
    'total', count(*) filter (where status <> 'not_applicable'),
    'completed', count(*) filter (where status = 'completed'),
    'open', count(*) filter (where status in ('open','in_progress')),
    'overdue', count(*) filter (where due_state = 'overdue'),
    'due_soon', count(*) filter (where due_state = 'due_soon'),
    'upcoming_30_days', count(*) filter (where status in ('open','in_progress') and due_date between current_date and current_date + 30),
    'completed_late', count(*) filter (where status = 'completed' and completed_on > due_date),
    'overdue_by_risk', coalesce((select jsonb_object_agg(risk_level, c) from (select risk_level, count(*) c from public.v_compliance_instance where due_state = 'overdue' group by risk_level) r), '{}'::jsonb)),
    count(*) filter (where status <> 'not_applicable' and due_date <= current_date),
    count(*) filter (where status = 'completed' and due_date <= current_date),
    count(*) filter (where status = 'completed' and due_date <= current_date and completed_on <= due_date)
  into o, due_so_far, completed_due, on_time
  from public.v_compliance_instance;
  o := o || jsonb_build_object('due_so_far', due_so_far,
        'compliance_pct', case when due_so_far > 0 then round(100.0 * completed_due / due_so_far, 1) end,
        'on_time_pct', case when due_so_far > 0 then round(100.0 * on_time / due_so_far, 1) end);

  select jsonb_build_object(
    'open', count(*) filter (where status in ('open','acknowledged')),
    'critical_open', count(*) filter (where status in ('open','acknowledged') and severity = 'critical'),
    'target_breached', count(*) filter (where target_breached),
    'by_severity', coalesce((select jsonb_object_agg(severity, c) from (select severity, count(*) c from public.v_exception where status in ('open','acknowledged') group by severity) s), '{}'::jsonb),
    'by_age', coalesce((select jsonb_object_agg(age_bucket, c) from (select age_bucket, count(*) c from public.v_exception where status in ('open','acknowledged') group by age_bucket) a), '{}'::jsonb),
    'by_category', coalesce((select jsonb_object_agg(category, c) from (select category, count(*) c from public.v_exception where status in ('open','acknowledged') group by category) c2), '{}'::jsonb))
  into e from public.v_exception;

  select jsonb_build_object(
    'missing', count(*) filter (where evidence_state = 'missing' and instance_status <> 'not_applicable' and (due_date < current_date or instance_status = 'completed')),
    'pending_review', count(*) filter (where evidence_state = 'pending_review'),
    'rejected', count(*) filter (where evidence_state = 'rejected'),
    'expired', count(*) filter (where evidence_state = 'expired'))
  into ev from public.v_evidence_requirement where is_mandatory;

  select jsonb_build_object(
    'active', count(*) filter (where lifecycle_status = 'active'),
    'expired', count(*) filter (where expiry_category = 'expired'),
    'renewal_window_open', count(*) filter (where renewal_window_open),
    'by_category', coalesce((select jsonb_object_agg(expiry_category, c) from (select expiry_category, count(*) c from public.v_licence_status where lifecycle_status = 'active' group by expiry_category) x), '{}'::jsonb))
  into l from public.v_licence_status;

  select coalesce(jsonb_agg(row_to_json(t) order by t.overdue desc, t.due_soon desc, t.location_code), '[]'::jsonb) into loc
    from (select location_code, count(*) filter (where due_state = 'overdue') as overdue, count(*) filter (where due_state = 'due_soon') as due_soon,
                 count(*) filter (where status in ('open','in_progress')) as open
            from public.v_compliance_instance where status <> 'not_applicable' group by location_code
           order by 2 desc, 3 desc, 1 limit 10) t;

  select coalesce(jsonb_agg(row_to_json(t) order by t.due_date, t.instance_no), '[]'::jsonb) into up
    from (select instance_no, compliance_code, compliance_name, location_code, due_date, risk_level, due_state
            from public.v_compliance_instance where status in ('open','in_progress') and due_date between current_date and current_date + 30
           order by due_date, instance_no limit 10) t;

  res := jsonb_build_object(
    'generated_at', now(), 'has_data', (o ->> 'total')::int > 0 or (e ->> 'open')::int > 0 or (l ->> 'active')::int > 0,
    'obligations', o, 'exceptions', e, 'evidence', ev, 'licences', l, 'by_location', loc, 'next_due', up,
    'definitions', jsonb_build_object(
      'compliance_pct', 'Completed obligations as a share of obligations already due (not applicable excluded).',
      'on_time_pct', 'Completed on or before the due date as a share of obligations already due.',
      'overdue', 'Open or in progress with a due date before today.',
      'upcoming_30_days', 'Open or in progress due from today to 30 days ahead.'));
  return res;
end $$;
revoke all on function public.compliance_dashboard() from public, anon;
grant execute on function public.compliance_dashboard() to authenticated;
