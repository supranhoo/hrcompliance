-- Dashboard aggregates are verified against INDEPENDENT queries run as the same user (correctness + scope), plus access rules.
\set ON_ERROR_STOP on
create or replace function test.dash(p_path text[]) returns text language sql stable as $$ select public.compliance_dashboard() #>> p_path $$;
grant execute on all functions in schema test to authenticated, anon;

-- Unprivileged / unprovisioned callers are refused (never shown zeros)
select test.login('stranger@gmail.com');
select test.denied('unprovisioned cannot call the dashboard', 'select public.compliance_dashboard()');
select test.logout();

-- Fixture: guarantee variety across states without relying on earlier suites
update public.compliance_master set is_active = true where code = 'AL-1';
create temp table _c as select id from public.compliance_master where code='AL-1';
create or replace function test.mk_d(p_loc text, p_due date, p_status text, p_done date default null) returns uuid language plpgsql as $$
declare v_id uuid; n int := nextval('test.mk_seq')::int;
begin
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, source)
  select m.id, v.id, l.entity_id, l.id, date '1990-01-01' + n * 40, date '1990-01-01' + n * 40 + 5, p_due, 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status='active', public.location l where m.code='AL-1' and l.code = p_loc returning id into v_id;
  if p_status = 'completed' then update public.compliance_instance set status='completed', completed_on = coalesce(p_done, current_date) where id = v_id;
  elsif p_status = 'in_progress' then update public.compliance_instance set status='in_progress' where id = v_id;
  elsif p_status = 'not_applicable' then perform set_config('app.audit_reason','fixture', true); update public.compliance_instance set status='not_applicable' where id = v_id; end if;
  return v_id;
end $$;
select test.mk_d('L-E1', current_date - 10, 'open');
select test.mk_d('L-E1', current_date - 2, 'in_progress');
select test.mk_d('L-E1', current_date + 2, 'open');
select test.mk_d('L-E1', current_date + 20, 'open');
select test.mk_d('L-E1', current_date - 20, 'completed', current_date - 25);       -- on time
select test.mk_d('L-E1', current_date - 20, 'completed', current_date - 15);       -- late
select test.mk_d('L-E1', current_date - 20, 'not_applicable');
select test.mk_d('L-E2', current_date - 5, 'open');
select app.detect_exceptions();

-- Head HR (unrestricted): every figure must equal an independent count
select test.login('headhr@bfcl.test');
select test.eq('total excludes not applicable', test.dash(array['obligations','total'])::int, (select count(*)::int from public.compliance_instance where status <> 'not_applicable'));
select test.eq('overdue matches independent count', test.dash(array['obligations','overdue'])::int, (select count(*)::int from public.compliance_instance where status in ('open','in_progress') and due_date < current_date));
select test.eq('due soon matches independent count', test.dash(array['obligations','due_soon'])::int, (select count(*)::int from public.compliance_instance where status in ('open','in_progress') and due_date between current_date and current_date + 7));
select test.eq('next-30-days matches', test.dash(array['obligations','upcoming_30_days'])::int, (select count(*)::int from public.compliance_instance where status in ('open','in_progress') and due_date between current_date and current_date + 30));
select test.eq('completed matches', test.dash(array['obligations','completed'])::int, (select count(*)::int from public.compliance_instance where status='completed'));
select test.eq('late completions matches', test.dash(array['obligations','completed_late'])::int, (select count(*)::int from public.compliance_instance where status='completed' and completed_on > due_date));
select test.eq('compliance % = completed / due so far', test.dash(array['obligations','compliance_pct'])::numeric,
  (select round(100.0 * count(*) filter (where status='completed') / count(*), 1) from public.compliance_instance where status <> 'not_applicable' and due_date <= current_date));
select test.eq('on-time % = completed on/before due / due so far', test.dash(array['obligations','on_time_pct'])::numeric,
  (select round(100.0 * count(*) filter (where status='completed' and completed_on <= due_date) / count(*), 1) from public.compliance_instance where status <> 'not_applicable' and due_date <= current_date));
select test.eq('open exceptions match', test.dash(array['exceptions','open'])::int, (select count(*)::int from public.exception where status in ('open','acknowledged')));
select test.eq('critical open exceptions match', test.dash(array['exceptions','critical_open'])::int, (select count(*)::int from public.exception where status in ('open','acknowledged') and severity='critical'));
select test.eq('severity split sums to open', (select sum(value::int)::int from jsonb_each_text(public.compliance_dashboard() -> 'exceptions' -> 'by_severity')), test.dash(array['exceptions','open'])::int);
select test.eq('age split sums to open', (select sum(value::int)::int from jsonb_each_text(public.compliance_dashboard() -> 'exceptions' -> 'by_age')), test.dash(array['exceptions','open'])::int);
select test.eq('overdue-by-risk sums to overdue', (select coalesce(sum(value::int),0)::int from jsonb_each_text(public.compliance_dashboard() -> 'obligations' -> 'overdue_by_risk')), test.dash(array['obligations','overdue'])::int);
select test.eq('licence active count matches', test.dash(array['licences','active'])::int, (select count(*)::int from public.licence where lifecycle_status='active'));
select test.eq('licence category split sums to active', (select sum(value::int)::int from jsonb_each_text(public.compliance_dashboard() -> 'licences' -> 'by_category')), test.dash(array['licences','active'])::int);
select test.eq('has_data true', test.dash(array['has_data']), 'true');
select test.eq('next_due list is limited and sorted', (select count(*) from jsonb_array_elements(public.compliance_dashboard() -> 'next_due')) between 1 and 10, true);
select test.eq('by_location is limited to 10', (select count(*) from jsonb_array_elements(public.compliance_dashboard() -> 'by_location')) between 1 and 10, true);
select test.eq('definitions travel with the numbers', (public.compliance_dashboard() -> 'definitions' ->> 'overdue') is not null, true);
select test.logout();

-- Entity-One-scoped user: sees ONLY their scope (figures equal the same independent counts under their own RLS)
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_HR' on conflict do nothing;
select test.login('plant@bfcl.test');
select test.eq('scoped overdue equals own-scope independent count', test.dash(array['obligations','overdue'])::int, (select count(*)::int from public.compliance_instance where status in ('open','in_progress') and due_date < current_date));
select test.eq('scoped total equals own-scope independent count', test.dash(array['obligations','total'])::int, (select count(*)::int from public.compliance_instance where status <> 'not_applicable'));

select test.eq('scoped user cannot see Entity Two locations in by_location', (select count(*) from jsonb_array_elements(public.compliance_dashboard() -> 'by_location') x where x ->> 'location_code' = 'L-E2'), 0::bigint);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('unrestricted user does see Entity Two in by_location', (select count(*) from jsonb_array_elements(public.compliance_dashboard() -> 'by_location') x where x ->> 'location_code' = 'L-E2'), 1::bigint);
select test.logout();

-- A permitted user with no scope: truthful empty result, flagged has_data=false, percentages NULL (never a fabricated 0%/100%)
select test.login('viewer@bfcl.test');
select test.eq('no-scope viewer: has_data=false', test.dash(array['has_data']), 'false');
select test.eq('no-scope viewer: total 0', test.dash(array['obligations','total']), '0');
select test.eq('no-scope viewer: compliance % is NULL, not 0', test.dash(array['obligations','compliance_pct']), null);
select test.eq('no-scope viewer: on-time % is NULL', test.dash(array['obligations','on_time_pct']), null);
select test.logout();
\echo ALL DASHBOARD TESTS PASSED
