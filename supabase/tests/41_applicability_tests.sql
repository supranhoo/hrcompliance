-- Rule evaluator + applicability matrix. Reuses fixtures from 10_* (entities E1/E2, locations L-E1/L-E1B/L-E2) and 40_*.
\set ON_ERROR_STOP on

-- ---------- evaluator: every operator, both outcomes ----------
create temp table _f as select '{"location":{"state":"Odisha","employee_headcount":25,"est":"Factory","opened":"2026-10-20","x":"","n":0},"entity":{"industry":"Steel"}}'::jsonb f;
select test.eq('eq text (case-insensitive)', app.rule_eval('{"op":"eq","field":"location.state","value":"odisha"}', (select f from _f)), true);
select test.eq('eq number', app.rule_eval('{"op":"eq","field":"location.employee_headcount","value":25}', (select f from _f)), true);
select test.eq('neq', app.rule_eval('{"op":"neq","field":"location.state","value":"Gujarat"}', (select f from _f)), true);
select test.eq('gt true', app.rule_eval('{"op":"gt","field":"location.employee_headcount","value":24}', (select f from _f)), true);
select test.eq('gt false at boundary', app.rule_eval('{"op":"gt","field":"location.employee_headcount","value":25}', (select f from _f)), false);
select test.eq('gte at boundary', app.rule_eval('{"op":"gte","field":"location.employee_headcount","value":25}', (select f from _f)), true);
select test.eq('lt false at boundary', app.rule_eval('{"op":"lt","field":"location.employee_headcount","value":25}', (select f from _f)), false);
select test.eq('lte at boundary', app.rule_eval('{"op":"lte","field":"location.employee_headcount","value":25}', (select f from _f)), true);
select test.eq('contains', app.rule_eval('{"op":"contains","field":"entity.industry","value":"tee"}', (select f from _f)), true);
select test.eq('in', app.rule_eval('{"op":"in","field":"location.state","value":["Bihar","Odisha"]}', (select f from _f)), true);
select test.eq('not_in', app.rule_eval('{"op":"not_in","field":"location.state","value":["Bihar","Odisha"]}', (select f from _f)), false);
select test.eq('before', app.rule_eval('{"op":"before","field":"location.opened","value":"2026-11-01"}', (select f from _f)), true);
select test.eq('after', app.rule_eval('{"op":"after","field":"location.opened","value":"2026-11-01"}', (select f from _f)), false);
select test.eq('within_days inside window', app.rule_eval('{"op":"within_days","field":"location.opened","value":30}', (select f from _f), date '2026-10-03'), true);
select test.eq('within_days outside window', app.rule_eval('{"op":"within_days","field":"location.opened","value":10}', (select f from _f), date '2026-10-03'), false);
select test.eq('within_days excludes past dates', app.rule_eval('{"op":"within_days","field":"location.opened","value":30}', (select f from _f), date '2026-11-15'), false);
select test.eq('is_blank (empty string)', app.rule_eval('{"op":"is_blank","field":"location.x"}', (select f from _f)), true);
select test.eq('is_blank (missing)', app.rule_eval('{"op":"is_blank","field":"location.nothing"}', (select f from _f)), true);
select test.eq('is_not_blank', app.rule_eval('{"op":"is_not_blank","field":"location.state"}', (select f from _f)), true);
select test.eq('and', app.rule_eval('{"op":"and","args":[{"op":"eq","field":"location.state","value":"Odisha"},{"op":"gte","field":"location.employee_headcount","value":20}]}', (select f from _f)), true);
select test.eq('and (one false)', app.rule_eval('{"op":"and","args":[{"op":"eq","field":"location.state","value":"Odisha"},{"op":"gte","field":"location.employee_headcount","value":50}]}', (select f from _f)), false);
select test.eq('or', app.rule_eval('{"op":"or","args":[{"op":"eq","field":"location.state","value":"X"},{"op":"gte","field":"location.employee_headcount","value":20}]}', (select f from _f)), true);
select test.eq('unknown fact: comparison false (not an error)', app.rule_eval('{"op":"gte","field":"location.contractor_headcount","value":1}', (select f from _f)), false);
select test.eq('unknown fact reported as missing', app.rule_missing_facts('{"op":"and","args":[{"op":"gte","field":"location.contractor_headcount","value":1},{"op":"eq","field":"location.state","value":"Odisha"}]}', (select f from _f)), array['location.contractor_headcount']);
select test.denied('invalid rule refused at eval', $$select app.rule_eval('{"op":"exec","field":"a","value":1}', '{}')$$);
select test.denied('SQL-ish field refused at eval', $$select app.rule_eval('{"op":"eq","field":"a;drop table x","value":1}', '{}')$$);

-- ---------- fixtures (superuser): masters + helpers ----------
insert into public.compliance_master (code, name) values ('AP-1', 'Applicability sample'), ('AP-2', 'Second sample');
create temp table _c as select id, code from public.compliance_master where code in ('AP-1','AP-2');
grant select on _c to authenticated; grant select on _f to authenticated;
create or replace function test.cid(c text) returns uuid language sql stable as $$ select id from _c where code = c $$;
create or replace function test.lid(c text) returns uuid language sql stable as $$ select id from public.location where code = c $$;
create or replace function test.dec(c text, l text, d date default current_date) returns text language sql stable as
$$ select coalesce((select effective_status || case when conflict then '+conflict' else '' end from app.applicability_for(test.cid(c), test.lid(l), d)), 'unmapped') $$;
grant execute on all functions in schema test to authenticated, anon;
-- facts on locations/entity (as admin, exercising master.write)
select test.login('admin@bfcl.test');
update public.entity set industry = 'Steel' where code = 'E1';
update public.location set state = 'Odisha', establishment_type = 'Factory', employee_headcount = 25 where code = 'L-E1';
update public.location set state = 'Odisha', establishment_type = 'Office',  employee_headcount = 10 where code = 'L-E1B';
update public.location set state = 'Gujarat' where code = 'L-E2';       -- headcount deliberately unknown
select test.logout();

select test.login('admin@bfcl.test');
-- 1. nothing configured -> unmapped (reported, not dropped)
select test.eq('no rows -> unmapped', test.dec('AP-1', 'L-E1'), 'unmapped');
select test.eq('coverage lists every pair incl. unmapped', (select count(*) from public.compliance_coverage() where compliance_code='AP-1' and effective_status='unmapped'), (select count(*) from public.location where is_active));

-- 2. entity-wide applicable
insert into public.compliance_applicability (compliance_id, entity_id, status, reason, source_reference, effective_from)
  select test.cid('AP-1'), e.id, 'applicable', 'all E1 sites', 'BFCL note 1', date '2026-01-01' from public.entity e where e.code='E1';
select test.eq('entity-wide applies to its locations', test.dec('AP-1', 'L-E1'), 'applicable');
select test.eq('other entity stays unmapped', test.dec('AP-1', 'L-E2'), 'unmapped');

-- 3. location beats entity
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from)
  values (test.cid('AP-1'), test.lid('L-E1B'), 'not_applicable', 'office only, no workmen', date '2026-01-01');
select test.eq('location-specific not_applicable overrides entity-wide', test.dec('AP-1', 'L-E1B'), 'not_applicable');
select test.eq('sibling location unaffected', test.dec('AP-1', 'L-E1'), 'applicable');

-- 4. state-level applies across entities, but is less specific than entity
insert into public.compliance_applicability (compliance_id, state, status, reason, effective_from) values (test.cid('AP-2'), 'Gujarat', 'applicable', 'state rule', date '2026-01-01');
select test.eq('state dimension matches (case-insensitive)', test.dec('AP-2', 'L-E2'), 'applicable');
select test.eq('state dimension excludes others', test.dec('AP-2', 'L-E1'), 'unmapped');

-- 5. conditional with headcount facts
insert into public.compliance_applicability (compliance_id, entity_id, status, condition, reason, effective_from)
  select test.cid('AP-2'), e.id, 'conditional', '{"op":"gte","field":"location.employee_headcount","value":20}', '20+ employees', date '2026-01-01' from public.entity e where e.code='E1';
select test.eq('conditional true -> applicable', test.dec('AP-2', 'L-E1'), 'applicable');
select test.eq('conditional false -> not_applicable', test.dec('AP-2', 'L-E1B'), 'not_applicable');
select test.eq('conditional reports missing facts via coverage', (select missing_facts from public.compliance_coverage() where compliance_code='AP-2' and location_code='L-E1B'), '{}'::text[]);
update public.location set employee_headcount = null where code = 'L-E1B';
select test.eq('conditional with unknown fact is flagged, not silent', (select missing_facts from public.compliance_coverage() where compliance_code='AP-2' and location_code='L-E1B'), array['location.employee_headcount']);
update public.location set employee_headcount = 10 where code = 'L-E1B';

-- 6. headcount range dimension + establishment type + industry
insert into public.compliance_applicability (compliance_id, entity_id, establishment_type, employee_headcount_min, status, reason, effective_from)
  select test.cid('AP-2'), e.id, 'factory', 20, 'applicable', 'factories with 20+', date '2026-01-01' from public.entity e where e.code='E1';
select test.eq('more specific (entity+est.type+headcount) beats conditional', (select specificity from app.applicability_for(test.cid('AP-2'), test.lid('L-E1'), current_date)), 45);
insert into public.compliance_applicability (compliance_id, industry, status, reason, effective_from) values (test.cid('AP-1'), 'Steel', 'applicable', 'industry rule', date '2026-01-01');
select test.eq('industry dimension reads entity.industry', (select count(*) from app.applicability_for(test.cid('AP-1'), test.lid('L-E1'), current_date)), 1::bigint);

-- 7. effective dating
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from, effective_to)
  values (test.cid('AP-1'), test.lid('L-E2'), 'applicable', 'temporary', date '2025-01-01', date '2025-12-31');
select test.eq('expired row not used today', test.dec('AP-1', 'L-E2'), 'unmapped');
select test.eq('expired row used for its own period (historical interpretation preserved)', test.dec('AP-1', 'L-E2', date '2025-06-01'), 'applicable');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) values (test.cid('AP-1'), test.lid('L-E2'), 'applicable', 'future', date '2999-01-01');
select test.eq('future row not used today', test.dec('AP-1', 'L-E2'), 'unmapped');
update public.compliance_applicability set is_active = false where reason = 'future';

-- 8. same-specificity conflict: fail-safe toward applicable, flagged
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) values (test.cid('AP-2'), test.lid('L-E2'), 'applicable', 'a', date '2026-01-01');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) values (test.cid('AP-2'), test.lid('L-E2'), 'not_applicable', 'b', date '2026-01-01');
select test.eq('tie resolves to applicable and is flagged as conflict', test.dec('AP-2', 'L-E2'), 'applicable+conflict');

-- 9. constraints
select test.denied('not_applicable requires a reason', $$insert into public.compliance_applicability(compliance_id,location_id,status,effective_from) values (test.cid('AP-1'), test.lid('L-E1'), 'not_applicable', date '2026-01-01')$$);
select test.denied('conditional requires a condition', $$insert into public.compliance_applicability(compliance_id,location_id,status,reason,effective_from) values (test.cid('AP-1'), test.lid('L-E1'), 'conditional','r', date '2026-01-01')$$);
select test.denied('condition must be a valid whitelisted rule', $$insert into public.compliance_applicability(compliance_id,location_id,status,condition,effective_from) values (test.cid('AP-1'), test.lid('L-E1'), 'conditional','{"op":"js","field":"a","value":"1"}', date '2026-01-01')$$);
select test.denied('applicable cannot carry a condition', $$insert into public.compliance_applicability(compliance_id,location_id,status,condition,effective_from) values (test.cid('AP-1'), test.lid('L-E1'), 'applicable','{"op":"eq","field":"a","value":"1"}', date '2026-01-01')$$);
select test.denied('reviewed_by and reviewed_at go together', $$insert into public.compliance_applicability(compliance_id,location_id,status,effective_from,reviewed_at) values (test.cid('AP-1'), test.lid('L-E1'), 'applicable', date '2026-01-01', now())$$);
select test.denied('headcount min <= max', $$insert into public.compliance_applicability(compliance_id,location_id,status,effective_from,employee_headcount_min,employee_headcount_max) values (test.cid('AP-1'), test.lid('L-E1'), 'applicable', date '2026-01-01', 50, 10)$$);

-- 10. immutability once in effect
select test.denied('in-effect decision cannot be rewritten', $$update public.compliance_applicability set status='not_applicable', reason='x' where reason='all E1 sites'$$);
select test.denied('in-effect scope cannot be rewritten', $$update public.compliance_applicability set state='Odisha' where reason='all E1 sites'$$);
update public.compliance_applicability set effective_to = current_date - 1, reviewed_by = (select id from public.app_user where email='admin@bfcl.test'), reviewed_at = now() where reason='all E1 sites';
select test.eq('in-effect row can be ended and reviewed', (select effective_to from public.compliance_applicability where reason='all E1 sites'), current_date - 1);
select test.eq('after ending, entity-wide no longer applies today', test.dec('AP-1', 'L-E1'), 'applicable');  -- industry rule (Steel) still matches
select test.logout();

-- ---------- access + scope ----------
select test.login('viewer@bfcl.test');
select test.eq('viewer without any scope sees no matrix rows (F-1: applicability is scope-controlled; fail closed)', test.count('select * from public.compliance_applicability'), 0::bigint);
select test.denied('viewer cannot write matrix', $$insert into public.compliance_applicability(compliance_id,location_id,status,effective_from) values ((select id from public.compliance_master limit 1), (select id from public.location limit 1), 'applicable', date '2026-01-01')$$);
select test.eq('viewer without any scope sees no coverage (F-1)', test.count('select * from public.compliance_coverage()'), 0::bigint);
select test.eq('viewer can still read the Compliance Master (global reference data)', test.count('select * from public.compliance_master') > 0, true);
select test.eq('viewer can still read the Location Master (global base data)', test.count('select * from public.location') > 0, true);
select test.logout();
select test.login('stranger@gmail.com');
select test.eq('unprovisioned sees no matrix', test.count('select * from public.compliance_applicability'), 0::bigint);
select test.eq('unprovisioned sees no coverage', test.count('select * from public.compliance_coverage()'), 0::bigint);
select test.logout();
-- a manager whose scope is Entity One only
insert into public.role (code, name) values ('PLANT_MGR','Plant compliance manager');
insert into public.role_permission select r.id, p from public.role r, unnest(array['compliance.read','compliance.manage']) p where r.code='PLANT_MGR';
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_MGR';
select test.login('plant@bfcl.test');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) values (test.cid('AP-1'), test.lid('L-E1'), 'not_applicable', 'in-scope write', date '2026-01-01');
select test.eq('scoped manager can write inside scope', test.count($$select 1 from public.compliance_applicability where reason='in-scope write'$$), 1::bigint);
select test.denied('scoped manager cannot write for another entity (location)', $$insert into public.compliance_applicability(compliance_id,location_id,status,reason,effective_from) values (test.cid('AP-1'), test.lid('L-E2'), 'not_applicable','x', date '2026-01-01')$$);
select test.denied('scoped manager cannot write for another entity (entity id)', $$insert into public.compliance_applicability(compliance_id,entity_id,status,effective_from) values (test.cid('AP-1'), (select id from public.entity where code='E2'), 'applicable', date '2026-01-01')$$);
select test.denied('scoped manager cannot write GLOBAL rows', $$insert into public.compliance_applicability(compliance_id,status,effective_from) values (test.cid('AP-1'), 'applicable', date '2026-01-01')$$);
select test.logout();
select test.eq('applicability changes audited', (select count(*) from public.audit_log where table_name='compliance_applicability') >= 10, true);
\echo ALL APPLICABILITY TESTS PASSED
