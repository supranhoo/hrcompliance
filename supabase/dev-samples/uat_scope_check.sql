-- SCOPE ENFORCEMENT CHECK (DEVELOPMENT ONLY, synthetic). Run after sample_compliance.sql + uat_engine_demo.sql, as postgres, in the SQL editor.
-- Creates a synthetic user 'sample.scoped@example.invalid' (role PLANT_HR) whose scope is ONLY location SAMPLE-LOC-B, then executes queries AS that user
-- (role "authenticated" + the same JWT claim the API sets) and compares what it can see with what exists. No Google account is needed:
-- app_user.auth_user_id is not tied to auth.users, so impersonation by claim is exactly how RLS evaluates a real request.
-- Prints one result table. Removed by remove_samples.sql. Environment guard: refuses outside DEVELOPMENT.
begin;
do $g$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name).';
  end if;
  if (select count(*) from public.location where code in ('SAMPLE-LOC-A','SAMPLE-LOC-B')) < 2 then raise exception 'Load sample_compliance.sql first'; end if;
end $g$;

insert into public.app_user (email, full_name, status, scope_all, auth_user_id)
values ('sample.scoped@example.invalid', 'SAMPLE scoped user (synthetic)', 'active', false, '5a5a5a5a-0000-4000-8000-000000000001')
on conflict (email) do update set status = 'active', scope_all = false;
insert into public.user_role (user_id, role_id) select u.id, r.id from public.app_user u, public.role r where u.email = 'sample.scoped@example.invalid' and r.code = 'PLANT_HR' on conflict do nothing;
delete from public.user_scope where user_id = (select id from public.app_user where email = 'sample.scoped@example.invalid');
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'location', l.id from public.app_user u, public.location l where u.email = 'sample.scoped@example.invalid' and l.code = 'SAMPLE-LOC-B';

select set_config('uat.other_instance', (select i.id::text from public.compliance_instance i join public.location l on l.id = i.location_id where l.code = 'SAMPLE-LOC-A' and i.status in ('open','in_progress') limit 1), true);
create temp table _scope (n serial primary key, check_name text, expected text, actual text, result text);
create temp table _vis (k text primary key, v text);
grant all on _vis to authenticated;   -- scratch table so the impersonated role can report what it could see
select set_config('request.jwt.claim.sub', '5a5a5a5a-0000-4000-8000-000000000001', true);
set local role authenticated;
  insert into _vis values
    ('instances_visible',        (select count(*)::text from public.compliance_instance)),
    ('instances_other_location', (select count(*)::text from public.v_compliance_instance where location_code <> 'SAMPLE-LOC-B')),
    ('exceptions_visible',       (select count(*)::text from public.exception)),
    ('exceptions_other_loc',     (select count(*)::text from public.exception x join public.location l on l.id = x.location_id where l.code <> 'SAMPLE-LOC-B')),
    ('licences_visible',         (select count(*)::text from public.licence)),
    ('licence_view_visible',     (select count(*)::text from public.v_licence_status)),
    ('evidence_req_visible',     (select count(*)::text from public.v_evidence_requirement where location_id not in (select id from public.location where code = 'SAMPLE-LOC-B'))),
    ('notifications_visible',    (select count(*)::text from public.notification)),
    ('calendar_rows_other_loc',  (select count(*)::text from public.compliance_calendar(current_date - 400, current_date + 400) where location_code <> 'SAMPLE-LOC-B')),
    ('dashboard_total',          (public.compliance_dashboard() #>> '{obligations,total}')),
    ('dashboard_locations',      (select coalesce(string_agg(x ->> 'location_code', ','), '') from jsonb_array_elements(public.compliance_dashboard() -> 'by_location') x)),
    ('coverage_rows_other_loc',  (select count(*)::text from public.compliance_coverage() where location_code <> 'SAMPLE-LOC-B')),
    ('applicability_other_loc',  (select count(*)::text from public.compliance_applicability a join public.location l on l.id = a.location_id where l.code <> 'SAMPLE-LOC-B')),
    ('locations_visible',        (select count(*)::text from public.location where code like 'SAMPLE-LOC-%')),
    ('masters_visible',          (select count(*)::text from public.compliance_master where code like 'SAMPLE-%'));
  do $w$ begin
    begin
      perform public.compliance_set_status((select (current_setting('uat.other_instance', true))::uuid), 'in_progress');
      insert into _vis values ('update_other_location', 'ALLOWED');
    exception when others then insert into _vis values ('update_other_location', 'DENIED: ' || left(sqlerrm, 60)); end;
    begin
      insert into public.licence (licence_type_id, entity_id, location_id, licence_number) select (select id from public.licence_type limit 1), l.entity_id, l.id, 'SAMPLE-SCOPE-TRY' from public.location l where l.code = 'SAMPLE-LOC-A';
      insert into _vis values ('create_licence_other_location', 'ALLOWED');
    exception when others then insert into _vis values ('create_licence_other_location', 'DENIED: ' || left(sqlerrm, 60)); end;
  end $w$;
reset role;

-- expectations computed as postgres (ground truth)
insert into _scope (check_name, expected, actual, result)
select c.name, c.expected, coalesce((select v from _vis where k = c.k), '(missing)'), case when coalesce((select v from _vis where k = c.k), '(missing)') like c.expected then 'PASS' else 'FAIL' end
from (values
  ('sees obligations of its own location only (count equals what exists at SAMPLE-LOC-B)', 'instances_visible', (select count(*)::text from public.compliance_instance i join public.location l on l.id = i.location_id where l.code = 'SAMPLE-LOC-B')),
  ('sees NO obligation of another location', 'instances_other_location', '0'),
  ('sees only exceptions of its own location', 'exceptions_other_loc', '0'),
  ('sees no licence (all sample licences are at SAMPLE-LOC-A)', 'licences_visible', '0'),
  ('sees no licence in the derived view', 'licence_view_visible', '0'),
  ('sees no evidence requirement of another location', 'evidence_req_visible', '0'),
  ('sees none of the other users notifications', 'notifications_visible', '0'),
  ('calendar returns no other-location rows', 'calendar_rows_other_loc', '0'),
  ('dashboard totals equal its own-location obligations (not the global total)', 'dashboard_total', (select count(*)::text from public.compliance_instance i join public.location l on l.id = i.location_id where l.code = 'SAMPLE-LOC-B' and i.status <> 'not_applicable')),
  ('dashboard lists only its own location', 'dashboard_locations', 'SAMPLE-LOC-B'),
  ('cannot change the status of an obligation at another location', 'update_other_location', 'DENIED%'),
  ('cannot create a licence at another location', 'create_licence_other_location', 'DENIED%')
) c(name, k, expected);
-- F-1 (owner decision, migration 0024): Compliance Master, rule versions and the base LOCATION MASTER are globally readable; the Applicability Matrix and the
-- coverage report are scope-controlled. Both halves are graded below (before 0024 the coverage/applicability checks FAIL on purpose).
insert into _scope (check_name, expected, actual, result)
select 'F-1: applicability matrix shows no other-location rows', '0', (select v from _vis where k = 'applicability_other_loc'), case when (select v from _vis where k = 'applicability_other_loc') = '0' then 'PASS' else 'FAIL' end;
insert into _scope (check_name, expected, actual, result)
select 'F-1: base Location Master is globally readable (both sample locations)', '2', (select v from _vis where k = 'locations_visible'), case when (select v from _vis where k = 'locations_visible') = '2' then 'PASS' else 'FAIL' end;
insert into _scope (check_name, expected, actual, result)
select 'F-1: Compliance Master is globally readable (3 sample compliances)', '3', (select v from _vis where k = 'masters_visible'), case when (select v from _vis where k = 'masters_visible') = '3' then 'PASS' else 'FAIL' end;
insert into _scope (check_name, expected, actual, result)
select 'F-1: coverage report lists no other-location rows', '0', (select v from _vis where k = 'coverage_rows_other_loc'), case when (select v from _vis where k = 'coverage_rows_other_loc') = '0' then 'PASS' else 'FAIL' end;
insert into _scope (check_name, expected, actual, result)
select 'positive control: the scope is not simply empty', '> 0', (select v from _vis where k = 'instances_visible'), case when (select v::int from _vis where k = 'instances_visible') > 0 then 'PASS' else 'FAIL' end;
insert into _scope (check_name, expected, actual, result)
select 'OVERALL', 'no FAIL', (count(*) filter (where result = 'FAIL'))::text || ' FAIL / ' || (count(*) filter (where result = 'PASS'))::text || ' PASS', case when count(*) filter (where result = 'FAIL') = 0 then 'PASS' else 'FAIL' end from _scope;
commit;
select n, check_name, expected, actual, result from _scope order by n;
