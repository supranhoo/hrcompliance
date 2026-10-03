-- UAT ENGINE 03 - conditional applicability
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: 4 rows, all PASS: quarterly obligations exist for SAMPLE-LOC-A, none for SAMPLE-LOC-B (15 employees, rule needs 50+); coverage says not applicable.
-- Independent: it runs the (idempotent) generator first so obligations exist.
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
do $$
declare a bigint; b bigint; hz int; cov text;
begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then raise exception 'REFUSED: not development'; end if;
  hz := coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_horizon_days'), 60);
  perform app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz);
  select count(*) into a from public.compliance_instance i join public.location l on l.id = i.location_id where l.code = 'SAMPLE-LOC-A' and i.compliance_id = (select id from public.compliance_master where code = 'SAMPLE-QUARTERLY');
  select count(*) into b from public.compliance_instance i join public.location l on l.id = i.location_id where l.code = 'SAMPLE-LOC-B' and i.compliance_id = (select id from public.compliance_master where code = 'SAMPLE-QUARTERLY');
  select effective_status into cov from public.compliance_coverage() where compliance_code = 'SAMPLE-QUARTERLY' and location_code = 'SAMPLE-LOC-B';
  insert into _uat(step, result, detail) values
   ('3a. quarterly obligations exist at SAMPLE-LOC-A (120 employees)', case when a > 0 then 'PASS' else 'FAIL' end, jsonb_build_object('count', a)),
   ('3b. NO quarterly obligation at SAMPLE-LOC-B (15 employees, rule 50+)', case when b = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('count', b)),
   ('3c. coverage report: quarterly at LOC-B is not applicable', case when cov = 'not_applicable' then 'PASS' else 'FAIL' end, jsonb_build_object('effective_status', cov)),
   ('3d. monthly obligations exist at both locations', case when (select count(distinct i.location_id) from public.compliance_instance i where i.compliance_id = (select id from public.compliance_master where code = 'SAMPLE-MONTHLY')) = 2 then 'PASS' else 'FAIL' end,
      jsonb_build_object('locations', (select count(distinct i.location_id) from public.compliance_instance i where i.compliance_id = (select id from public.compliance_master where code = 'SAMPLE-MONTHLY'))));
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
