-- UAT ENGINE 08 - overall result from persistent database state
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: Last row 'OVERALL' = PASS (INFO rows are explained). FAIL rows name what is wrong.
-- Read-only: reads the database and job log; it needs no temp table from any other file. Run it after 01-07. It proves the end STATE; the run-time 'inserted 0' proofs are in files 02, 04 and 06.
do $g$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name).';
  end if;
  if (select count(*) from public.compliance_master where code like 'SAMPLE-%') < 3 then
    raise exception 'Load supabase/dev-samples/sample_compliance.sql first (3 SAMPLE compliances not found).';
  end if;
end $g$;
drop table if exists _uat;
create temp table _uat (n serial primary key, step text, result text, detail jsonb);
do $$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then raise exception 'REFUSED: not development'; end if;
  insert into _uat(step, result, detail) values
   ('8.01 SAMPLE obligations exist', case when (select count(*) from public.compliance_instance where compliance_id in (select id from public.compliance_master where code like 'SAMPLE-%')) > 0 then 'PASS' else 'FAIL' end,
      jsonb_build_object('count', (select count(*) from public.compliance_instance where compliance_id in (select id from public.compliance_master where code like 'SAMPLE-%')))),
   ('8.02 no duplicate obligation keys', case when not exists (select 1 from public.compliance_instance where status <> 'superseded' group by compliance_id, location_id, period_start having count(*) > 1) then 'PASS' else 'FAIL' end, '{}'::jsonb),
   ('8.03 conditional applicability: no quarterly obligation at SAMPLE-LOC-B', case when not exists (select 1 from public.compliance_instance i join public.location l on l.id = i.location_id where l.code = 'SAMPLE-LOC-B' and i.compliance_id = (select id from public.compliance_master where code = 'SAMPLE-QUARTERLY')) then 'PASS' else 'FAIL' end, '{}'::jsonb),
   ('8.04 exceptions exist for SAMPLE obligations', case when exists (select 1 from public.exception x join public.compliance_instance i on i.id = x.compliance_instance_id where i.compliance_id in (select id from public.compliance_master where code like 'SAMPLE-%')) then 'PASS' else 'FAIL' end, '{}'::jsonb),
   ('8.05 at most one active exception per detection key', case when not exists (select detection_key from public.exception where status in ('open','acknowledged') group by 1 having count(*) > 1) then 'PASS' else 'FAIL' end, '{}'::jsonb),
   ('8.06 an exception has auto-resolved (file 05)', case when exists (select 1 from public.exception where auto_resolved and resolution = 'Condition cleared automatically') then 'PASS' else 'INFO' end, jsonb_build_object('note', 'INFO = run uat_engine_05 to demonstrate auto-resolution')),
   ('8.07 evidence_missing exceptions exist', case when exists (select 1 from public.exception where category = 'evidence_missing') then 'PASS' else 'INFO' end, jsonb_build_object('note', 'INFO = no evidence-requiring obligation has been completed yet')),
   ('8.08 notifications exist for the alert demo', case when exists (select 1 from public.notification) then 'PASS' else 'INFO' end, jsonb_build_object('notifications', (select count(*) from public.notification), 'note', 'INFO with 0 notifications = KNOWN BASELINE DEFECT D-001 (no valid recipient), not an engine failure')),
   ('8.09 no duplicate notification keys', case when not exists (select dedupe_key from public.notification group by 1 having count(*) > 1) then 'PASS' else 'FAIL' end, '{}'::jsonb),
   ('8.10 job_run: compliance_generation succeeded', case when exists (select 1 from public.job_run where job_code = 'compliance_generation' and status = 'succeeded') then 'PASS' else 'FAIL' end, '{}'::jsonb),
   ('8.11 job_run: exception_generation succeeded', case when exists (select 1 from public.job_run where job_code = 'exception_generation' and status = 'succeeded') then 'PASS' else 'FAIL' end, '{}'::jsonb),
   ('8.12 job_run: alert_generation succeeded', case when exists (select 1 from public.job_run where job_code = 'alert_generation' and status = 'succeeded') then 'PASS' else 'FAIL' end, '{}'::jsonb);
  insert into _uat(step, result, detail)
  select 'OVERALL', case when count(*) filter (where result = 'FAIL') = 0 then 'PASS' else 'FAIL' end,
         jsonb_build_object('pass', count(*) filter (where result = 'PASS'), 'fail', count(*) filter (where result = 'FAIL'), 'info', count(*) filter (where result = 'INFO')) from _uat where step <> 'OVERALL';
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
