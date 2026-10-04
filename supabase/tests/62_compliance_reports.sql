-- Compliance performance + licence pipeline reports: correct numbers, whitelisted dimensions, same scope as the registers. Rolled back.
\set ON_ERROR_STOP on
begin;
insert into public.department (code, name) values ('RP-D', 'Report dept');
insert into public.compliance_master (code, name, owner_department_id) values ('RP-M1', 'report M1', (select id from public.department where code='RP-D')), ('RP-M2', 'report M2', null);
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', case code when 'RP-M1' then 'high' else 'low' end, date '2000-01-01' from public.compliance_master where code like 'RP-M%';
update public.compliance_rule_version set status='active' where compliance_id in (select id from public.compliance_master where code like 'RP-M%');
create or replace function test.mk(p_no text, p_master text, p_loc text, p_due date, p_status text, p_done date) returns void language sql as $$
  insert into public.compliance_instance (instance_no, compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, status, completed_on, source)
  select p_no, m.id, v.id, l.entity_id, l.id, p_due - 10, p_due - 5, p_due, p_status, p_done, 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l where m.code = p_master and l.code = p_loc $$;
select test.mk('RP-A', 'RP-M1', 'L-E1', date '2001-01-10', 'completed', date '2001-01-09');      -- on time
select test.mk('RP-B', 'RP-M1', 'L-E1', date '2001-01-20', 'completed', date '2001-01-25');      -- late
select test.mk('RP-C', 'RP-M2', 'L-E2', date '2001-01-25', 'open', null);                         -- overdue
select test.mk('RP-D', 'RP-M2', 'L-E2', date '2001-02-10', 'completed', date '2001-02-10');      -- on time (same day)
select test.mk('RP-E', 'RP-M2', 'L-E2', date '2001-02-15', 'not_applicable', null);              -- excluded
select test.mk('RP-F', 'RP-M2', 'L-E2', date '2001-04-15', 'open', null);                         -- outside the window below
grant execute on all functions in schema test to authenticated, anon;
create or replace function test.rep(p_dim text) returns text language sql stable as $$
  select coalesce(string_agg(group_key || '=' || total || '/' || completed || '/' || completed_on_time || '/' || completed_late || '/' || overdue_open || '/' || due_to_date || '/' || coalesce(on_time_pct::text, 'n') || '/' || coalesce(compliance_pct::text, 'n'), ' ' order by group_key), '-')
    from public.report_compliance_performance(p_dim, date '2001-01-01', date '2001-03-31') $$;
grant execute on all functions in schema test to authenticated, anon;

select test.login('admin@bfcl.test');
select test.eq('month: total/completed/on-time/late/overdue/due-to-date/on-time %/compliance %', test.rep('month'), '2001-01=3/2/1/1/1/3/33.3/66.7 2001-02=1/1/1/0/0/1/100.0/100.0');
select test.eq('location', test.rep('location'), 'L-E1=2/2/1/1/0/2/50.0/100.0 L-E2=2/1/1/0/1/2/50.0/50.0');
select test.eq('risk', test.rep('risk'), 'high=2/2/1/1/0/2/50.0/100.0 low=2/1/1/0/1/2/50.0/50.0');
select test.eq('department uses the responsible department of the master', (select string_agg(group_label || ':' || total, ' ' order by group_label) from public.report_compliance_performance('department', date '2001-01-01', date '2001-03-31')), '(no responsible department):2 Report dept:2');
select test.eq('window excludes obligations due outside it', (select sum(total) from public.report_compliance_performance('month', date '2001-01-01', date '2001-03-31')), 4::numeric);
select test.eq('an empty window returns no rows', (select count(*) from public.report_compliance_performance('month', date '1990-01-01', date '1990-02-01')), 0::bigint);
select test.denied('unknown dimension is refused (nothing is executed from text)', $$select * from public.report_compliance_performance('1; drop table x', null, null)$$);
select test.denied('start after end is refused', $$select * from public.report_compliance_performance('month', date '2001-03-01', date '2001-01-01')$$);
select test.denied('a period over 10 years is refused', $$select * from public.report_compliance_performance('month', date '1980-01-01', date '2001-01-01')$$);
select test.eq('default window works (last 12 months)', (select count(*) >= 0 from public.report_compliance_performance('month')), true);
select test.logout();

-- scope: a user limited to entity E1 sees only L-E1 obligations; a department-owned master needs the department
insert into public.app_user (email, status) values ('rp_scoped@bfcl.test', 'active');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email = 'rp_scoped@bfcl.test' and r.code = 'HEAD_HR';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email = 'rp_scoped@bfcl.test' and e.code = 'E1';
insert into auth.users (id, email) select gen_random_uuid(), 'rp_scoped@bfcl.test' where not exists (select 1 from auth.users where email = 'rp_scoped@bfcl.test');
update public.app_user set auth_user_id = (select id from auth.users where email = 'rp_scoped@bfcl.test') where email = 'rp_scoped@bfcl.test';
select test.login('rp_scoped@bfcl.test');
select test.eq('scoped user: only own entity, and department-owned obligations are hidden without the department', test.rep('location'), '-');
select test.logout();
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'department', d.id from public.app_user u, public.department d where u.email = 'rp_scoped@bfcl.test' and d.code = 'RP-D';
select test.login('rp_scoped@bfcl.test');
select test.eq('scoped user with the department: only L-E1 obligations of that department', test.rep('location'), 'L-E1=2/2/1/1/0/2/50.0/100.0');
select test.logout();

-- permission: a user without compliance.read gets nothing
insert into public.app_user (email, status) values ('rp_noperm@bfcl.test', 'active');
insert into public.role (code, name) values ('RP_NOPERM', 'no perms');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email = 'rp_noperm@bfcl.test' and r.code = 'RP_NOPERM';
insert into auth.users (id, email) select gen_random_uuid(), 'rp_noperm@bfcl.test' where not exists (select 1 from auth.users where email = 'rp_noperm@bfcl.test');
update public.app_user set auth_user_id = (select id from auth.users where email = 'rp_noperm@bfcl.test') where email = 'rp_noperm@bfcl.test';
select test.login('rp_noperm@bfcl.test');
select test.denied('no compliance.read: refused', $$select * from public.report_compliance_performance('month')$$);
select test.denied('no licence.read: refused', $$select * from public.report_licence_pipeline(12)$$);
select test.logout();
select test.login('stranger@gmail.com');
select test.denied('unprovisioned user: refused', $$select * from public.report_compliance_performance('month')$$);
select test.logout();

-- licence pipeline: buckets by expiry month, expired separately, horizon respected, scope respected
insert into public.authority (code, name) values ('RP-AUTH', 'Report authority');
insert into public.licence_type (code, name, authority_id, default_risk) select 'RP-LT', 'Report licence type', id, 'high' from public.authority where code = 'RP-AUTH';
create or replace function test.mk_lic2(p_loc text, p_expiry date, p_num text) returns void language sql as $$
  insert into public.licence (licence_type_id, entity_id, location_id, authority_id, licence_number, issue_date, expiry_date)
  select (select id from public.licence_type where code = 'RP-LT'), l.entity_id, l.id, (select id from public.authority where code = 'RP-AUTH'), p_num, date '2020-01-01', p_expiry from public.location l where l.code = p_loc $$;
select test.mk_lic2('L-E1', current_date - 5, 'RP-L1');                     -- expired
select test.mk_lic2('L-E1', date_trunc('month', current_date)::date + 40, 'RP-L2');   -- next month or the one after
select test.mk_lic2('L-E2', date_trunc('month', current_date)::date + 40, 'RP-L3');
select test.mk_lic2('L-E1', current_date + 800, 'RP-L4');                   -- beyond a 12-month horizon
grant execute on all functions in schema test to authenticated, anon;
select test.login('admin@bfcl.test');
select test.eq('expired licences are their own bucket', (select sum(licences) from public.report_licence_pipeline(12) where bucket = 'expired' and licence_type_code = 'RP-LT'), 1::numeric);
select test.eq('licences inside the horizon are bucketed by month', (select sum(licences) from public.report_licence_pipeline(12) where bucket <> 'expired' and licence_type_code = 'RP-LT'), 2::numeric);
select test.eq('licences beyond the horizon are not counted', (select sum(licences) from public.report_licence_pipeline(12) where licence_type_code = 'RP-LT'), 3::numeric);
select test.eq('a longer horizon includes them', (select sum(licences) from public.report_licence_pipeline(60) where licence_type_code = 'RP-LT'), 4::numeric);
select test.logout();
select test.login('rp_scoped@bfcl.test');
select test.eq('scoped user sees only own-entity licences', (select sum(licences) from public.report_licence_pipeline(12) where licence_type_code = 'RP-LT'), 2::numeric);
select test.logout();
rollback;
\echo ALL COMPLIANCE REPORT TESTS PASSED
