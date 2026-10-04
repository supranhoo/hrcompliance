-- Management dashboard: filters, definitions, scope, errors. Rolled back.
\set ON_ERROR_STOP on
begin;
insert into public.department (code, name) values ('MD-D', 'Dashboard dept');
insert into public.compliance_master (code, name, owner_department_id) values ('MD-A', 'dashboard A', (select id from public.department where code='MD-D'));
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'critical', date '2000-01-01' from public.compliance_master where code = 'MD-A';
update public.compliance_rule_version set status='active' where compliance_id = (select id from public.compliance_master where code = 'MD-A');
create or replace function test.mk(p_no text, p_loc text, p_due date, p_status text, p_done date) returns void language sql as $$
  insert into public.compliance_instance (instance_no, compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, status, completed_on, source)
  select p_no, m.id, v.id, l.entity_id, l.id, p_due - 10, p_due - 5, p_due, p_status, p_done, 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l where m.code = 'MD-A' and l.code = p_loc $$;
select test.mk('MD-1', 'L-E1', date '2001-01-10', 'completed', date '2001-01-09');
select test.mk('MD-2', 'L-E1', date '2001-01-20', 'completed', date '2001-01-25');
select test.mk('MD-3', 'L-E2', date '2001-01-25', 'open', null);
select test.mk('MD-4', 'L-E2', date '2001-02-10', 'completed', date '2001-02-10');
select test.mk('MD-5', 'L-E2', date '2001-02-15', 'not_applicable', null);
select test.mk('MD-6', 'L-E1', current_date, 'open', null);
select test.mk('MD-7', 'L-E1', current_date + 5, 'open', null);
insert into public.authority (code, name) values ('MD-AUTH', 'Dashboard authority');
insert into public.licence_type (code, name, authority_id, default_risk) select 'MD-LT', 'Dashboard licence type', id, 'high' from public.authority where code = 'MD-AUTH';
insert into public.licence (licence_type_id, entity_id, location_id, authority_id, licence_number, issue_date, expiry_date)
  select (select id from public.licence_type where code='MD-LT'), l.entity_id, l.id, (select id from public.authority where code='MD-AUTH'), n, date '2020-01-01', d
    from public.location l, (values ('MD-L1', current_date + 30), ('MD-L2', current_date - 3), ('MD-L3', current_date + 400)) v(n, d) where l.code = 'L-E1';
grant execute on all functions in schema test to authenticated, anon;
create or replace function test.md(p_ent text default null, p_loc text default null, p_dep text default 'MD-D', p_from date default date '2001-01-01', p_to date default date '2001-03-31') returns jsonb language sql stable as $$
  select public.management_dashboard((select id from public.entity where code = p_ent), (select id from public.location where code = p_loc), (select id from public.department where code = p_dep), p_from, p_to) $$;
grant execute on all functions in schema test to authenticated, anon;

select test.eq('view exposes the responsible department', (select count(*) from public.v_compliance_instance where instance_no like 'MD-%' and owner_department_id = (select id from public.department where code='MD-D')), 7::bigint);
select test.eq('exception view exposes the department of its obligation', (select count(*) from information_schema.columns where table_name = 'v_exception' and column_name = 'department_id'), 1::bigint);
select test.login('admin@bfcl.test');
select test.eq('total applicable = obligations due in the period, not-applicable excluded', (test.md() -> 'kpis' ->> 'total_applicable')::int, 4);
select test.eq('overdue = open past due (all periods)', (test.md() -> 'kpis' ->> 'overdue')::int, 1);
select test.eq('due this month (calendar month, open)', (test.md() -> 'kpis' ->> 'due_this_month')::int, 1 + case when current_date + 5 < (date_trunc('month', current_date) + interval '1 month')::date then 1 else 0 end);
select test.eq('critical = highest RISK level, open (not a hardcoded name)', (test.md() -> 'kpis' ->> 'critical_open')::int, 3);
select test.eq('critical overdue', (test.md() -> 'kpis' ->> 'critical_overdue')::int, 1);
select test.eq('top risk level comes from the list (sort order)', test.md() ->> 'top_risk_level', 'critical');
select test.eq('compliance % in the period', (test.md() -> 'kpis' ->> 'compliance_pct')::numeric, 75.0);
select test.eq('on-time % in the period', (test.md() -> 'kpis' ->> 'on_time_pct')::numeric, 50.0);
select test.eq('trend by month', (select string_agg((x ->> 'month') || ':' || (x ->> 'due') || '/' || (x ->> 'completed_on_time') || '/' || (x ->> 'completed_late') || '/' || (x ->> 'overdue_open'), ' ' order by x ->> 'month') from jsonb_array_elements(test.md() -> 'trend') x), '2001-01:3/1/1/1 2001-02:1/1/0/0');
select test.eq('risk distribution lists every level in list order', (select string_agg(x ->> 'level', ',' order by (x ->> 'sort_order')::int) from jsonb_array_elements(test.md() -> 'risk') x), 'low,medium,high,critical');
select test.eq('risk distribution counts open and overdue', (select (x ->> 'open') || '/' || (x ->> 'overdue') from jsonb_array_elements(test.md() -> 'risk') x where x ->> 'level' = 'critical'), '3/1');
select test.eq('by location', (select string_agg((x ->> 'code') || ':' || (x ->> 'total') || '/' || (x ->> 'overdue'), ' ' order by x ->> 'code') from jsonb_array_elements(test.md() -> 'by_location') x), 'L-E1:2/0 L-E2:2/1');
select test.eq('by department (filtered to the chosen one)', (select string_agg((x ->> 'name') || ':' || (x ->> 'total'), ' ') from jsonb_array_elements(test.md() -> 'by_department') x), 'Dashboard dept:4');
select test.eq('location filter narrows everything', (test.md(p_loc => 'L-E1') -> 'kpis' ->> 'total_applicable')::int, 2);
select test.eq('entity filter narrows everything', (test.md(p_ent => 'E2') -> 'kpis' ->> 'total_applicable')::int, (select count(*)::int from public.v_compliance_instance i join public.location l on l.id = i.location_id join public.entity e on e.id = l.entity_id where e.code = 'E2' and i.instance_no like 'MD-%' and i.status <> 'not_applicable' and i.due_date between date '2001-01-01' and date '2001-03-31'));
select test.eq('upcoming lists open obligations in the next 30 days, in due order', (select string_agg(x ->> 'instance_no', ',' order by x ->> 'due_date') from jsonb_array_elements(test.md() -> 'upcoming') x), 'MD-6,MD-7');
select test.eq('licences expiring use the longest configured threshold', (test.md(p_loc => 'L-E1') -> 'licences' ->> 'horizon_days')::int, 90);
select test.eq('licences expiring / expired (entity+location filters; not the department)', (test.md(p_loc => 'L-E1') -> 'kpis' ->> 'licences_expiring')::int >= 1, true);
select test.eq('and the department filter is declared not applicable to licences', (test.md() -> 'licences' ->> 'department_filter_applies')::boolean, false);
select test.eq('critical exceptions is a list', jsonb_typeof(test.md() -> 'critical_exceptions'), 'array');
select test.eq('definitions travel with the data', (test.md() -> 'definitions' ->> 'overdue') is not null, true);
select test.denied('start after end', $$select test.md(p_from => date '2001-03-01', p_to => date '2001-01-01')$$);
select test.denied('over ten years', $$select test.md(p_from => date '1980-01-01', p_to => date '2001-01-01')$$);
select test.eq('default period works', (select jsonb_typeof(public.management_dashboard())), 'object');
select test.eq('the existing dashboard still works', (select jsonb_typeof(public.compliance_dashboard())), 'object');
select test.logout();

-- scope: entity-limited user sees nothing of a department-owned master without the department, and only own-entity rows with it
insert into public.app_user (email, status) values ('md_scoped@bfcl.test', 'active');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email = 'md_scoped@bfcl.test' and r.code = 'HEAD_HR';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email = 'md_scoped@bfcl.test' and e.code = 'E1';
insert into auth.users (id, email) select gen_random_uuid(), 'md_scoped@bfcl.test' where not exists (select 1 from auth.users where email = 'md_scoped@bfcl.test');
update public.app_user set auth_user_id = (select id from auth.users where email = 'md_scoped@bfcl.test') where email = 'md_scoped@bfcl.test';
select test.login('md_scoped@bfcl.test');
select test.eq('without the department: nothing', (test.md() -> 'kpis' ->> 'total_applicable')::int, 0);
select test.logout();
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'department', d.id from public.app_user u, public.department d where u.email = 'md_scoped@bfcl.test' and d.code = 'MD-D';
select test.login('md_scoped@bfcl.test');
select test.eq('with the department: own entity only (L-E1)', (select string_agg(x ->> 'code', ',' order by x ->> 'code') from jsonb_array_elements(test.md() -> 'by_location') x), 'L-E1');
select test.eq('and totals follow', (test.md() -> 'kpis' ->> 'total_applicable')::int, 2);
select test.logout();

insert into public.app_user (email, status) values ('md_noperm@bfcl.test', 'active');
insert into public.role (code, name) values ('MD_NOPERM', 'no perms');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email = 'md_noperm@bfcl.test' and r.code = 'MD_NOPERM';
insert into auth.users (id, email) select gen_random_uuid(), 'md_noperm@bfcl.test' where not exists (select 1 from auth.users where email = 'md_noperm@bfcl.test');
update public.app_user set auth_user_id = (select id from auth.users where email = 'md_noperm@bfcl.test') where email = 'md_noperm@bfcl.test';
select test.login('md_noperm@bfcl.test');
select test.denied('no compliance.read: refused', $$select public.management_dashboard()$$);
select test.logout();
select test.login('stranger@gmail.com');
select test.denied('unprovisioned: refused', $$select public.management_dashboard()$$);
select test.logout();
rollback;
\echo ALL MANAGEMENT DASHBOARD TESTS PASSED
