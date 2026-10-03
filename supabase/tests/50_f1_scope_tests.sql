-- F-1: reference masters + Compliance Master + base Location Master are readable regardless of scope; the Applicability Matrix and coverage are scope-controlled.
\set ON_ERROR_STOP on
begin;
insert into public.compliance_master (code, name) values ('F1-1', 'F1 sample');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', date '2020-01-01' from public.compliance_master where code='F1-1';
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='F1-1');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from)
  select (select id from public.compliance_master where code='F1-1'), l.id, 'applicable', 'f1 ' || l.code, date '2020-01-01' from public.location l where l.code in ('L-E1','L-E2');
insert into public.compliance_applicability (compliance_id, status, effective_from) values ((select id from public.compliance_master where code='F1-1'), 'applicable', date '2020-01-01');   -- GLOBAL row
insert into public.app_user (email, status) values ('f1scoped@bfcl.test', 'active');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='f1scoped@bfcl.test' and r.code='HEAD_HR';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email='f1scoped@bfcl.test' and e.code='E1';
insert into auth.users (id, email) select gen_random_uuid(), 'f1scoped@bfcl.test' where not exists (select 1 from auth.users where email='f1scoped@bfcl.test');
update public.app_user set auth_user_id = (select id from auth.users where email='f1scoped@bfcl.test') where email='f1scoped@bfcl.test';

select test.login('f1scoped@bfcl.test');
select test.eq('scoped user: COMPLIANCE MASTER is globally readable', test.count($$select 1 from public.compliance_master where code='F1-1'$$), 1::bigint);
select test.eq('scoped user: rule versions are globally readable', test.count($$select 1 from public.compliance_rule_version v join public.compliance_master m on m.id=v.compliance_id where m.code='F1-1'$$), 1::bigint);
select test.eq('scoped user: BASE LOCATION MASTER is globally readable (all locations, both entities)', test.count($$select 1 from public.location where code in ('L-E1','L-E2')$$), 2::bigint);
select test.eq('scoped user: entity master is readable', test.count($$select 1 from public.entity where code in ('E1','E2')$$), 2::bigint);
select test.eq('scoped user: applicability rows ONLY for the own entity', test.count($$select 1 from public.compliance_applicability a join public.compliance_master m on m.id=a.compliance_id where m.code='F1-1' and a.location_id is not null$$), 1::bigint);
select test.eq('scoped user: the other entity''s applicability row is invisible', test.count($$select 1 from public.compliance_applicability where reason = 'f1 L-E2'$$), 0::bigint);
select test.eq('scoped user: GLOBAL applicability rows are invisible (scope_all only)', test.count($$select 1 from public.compliance_applicability a join public.compliance_master m on m.id=a.compliance_id where m.code='F1-1' and a.entity_id is null and a.location_id is null$$), 0::bigint);
select test.eq('scoped user: coverage lists only own-entity locations', test.count($$select 1 from public.compliance_coverage() where compliance_code='F1-1' and location_code='L-E1'$$), 1::bigint);
select test.eq('scoped user: coverage never lists the other entity', test.count($$select 1 from public.compliance_coverage() where location_code='L-E2'$$), 0::bigint);
select test.logout();

select test.login('admin@bfcl.test');
select test.eq('scope_all user sees the whole matrix incl. the global row', test.count($$select 1 from public.compliance_applicability a join public.compliance_master m on m.id=a.compliance_id where m.code='F1-1'$$), 3::bigint);
select test.eq('scope_all user sees coverage for every location', test.count($$select 1 from public.compliance_coverage() where compliance_code='F1-1' and location_code in ('L-E1','L-E2')$$), 2::bigint);
select test.logout();
select test.login('stranger@gmail.com');
select test.eq('unprovisioned still sees nothing', test.count('select 1 from public.compliance_applicability') + test.count('select 1 from public.compliance_coverage()'), 0::bigint);
select test.logout();
select test.eq('maintenance session (no auth user) still sees the full coverage', (select count(*) from public.compliance_coverage() where compliance_code='F1-1' and location_code in ('L-E1','L-E2')), 2::bigint);
rollback;
\echo ALL READ SCOPE TESTS PASSED
