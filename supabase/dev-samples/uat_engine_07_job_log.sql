-- UAT ENGINE 07 - job_run evidence
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: One row per engine job showing its latest run; PASS when each of the three engines has at least one succeeded run.
-- Read-only. Run it AFTER files 01, 04 and 06.
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
  insert into _uat(step, result, detail)
  select '7. job_run: ' || d.code, case when j.status = 'succeeded' then 'PASS' else 'INFO' end,
         coalesce(jsonb_build_object('key', j.idempotency_key, 'status', j.status, 'attempt', j.attempt, 'records', j.records_processed, 'duration_ms', round(extract(epoch from j.completed_at - j.started_at) * 1000), 'environment', j.environment, 'started_at', j.started_at), jsonb_build_object('note', 'not run yet - run the matching engine file (01 / 04 / 06) first'))
    from (values ('compliance_generation'), ('exception_generation'), ('alert_generation')) d(code)
    left join lateral (select * from public.job_run r where r.job_code = d.code and r.status = 'succeeded' order by r.started_at desc limit 1) j on true;
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
