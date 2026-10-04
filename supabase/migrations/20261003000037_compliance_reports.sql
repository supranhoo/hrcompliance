-- 0037 Compliance performance and licence pipeline reports (read-only, RLS-scoped).
-- Both are SECURITY INVOKER functions over the existing scope-controlled views, so a report can never show a row the caller cannot see on the registers (role permission AND entity/location/department scope).
-- on_time_to_date / completed_to_date are the numerators of the two percentages, returned so totals can be recomputed from counts (never by averaging percentages).
-- Definitions follow the dashboard: "due to date" = due_date <= today; on-time % = completed on/before due date / due to date; compliance % = completed / due to date. Not-applicable and superseded obligations are excluded.
-- Dimensions are a fixed whitelist (location, department, category, risk, domain, owner, month); nothing is executed from user text.
-- Rollback: drop function public.report_compliance_performance(text, date, date); drop function public.report_licence_pipeline(int).
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
    select v.*, m.owner_department_id, dep.name as dep_name, cat.name as cat_name, ou.email::text as owner_email
      from public.v_compliance_instance v
      join public.compliance_master m on m.id = v.compliance_id
      left join public.department dep on dep.id = m.owner_department_id
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

create or replace function public.report_licence_pipeline(p_months int default 12)
returns table (bucket text, licence_type_code text, licence_type_name text, licences bigint)
language plpgsql stable security invoker as $$
declare n int := least(greatest(coalesce(p_months, 12), 1), 60);
begin
  if not app.has_permission('licence.read') then raise exception 'permission denied' using errcode = '42501'; end if;
  return query
  select case when s.expiry_date < current_date then 'expired' else to_char(s.expiry_date, 'YYYY-MM') end, s.licence_type_code, s.licence_type_name, count(*)
    from public.v_licence_status s
   where s.lifecycle_status = 'active' and s.expiry_date is not null and s.expiry_date < (date_trunc('month', current_date) + make_interval(months => n))::date
   group by 1, 2, 3 order by 1, 2;
end $$;
revoke all on function public.report_compliance_performance(text, date, date), public.report_licence_pipeline(int) from public, anon;
grant execute on function public.report_compliance_performance(text, date, date), public.report_licence_pipeline(int) to authenticated;
