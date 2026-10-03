-- UAT ENGINE 02 - generator idempotency
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: 4 rows, all PASS: wrapper refused on the second same-day call; identical direct run inserts 0; no duplicate obligation keys.
-- Independent: it runs the generator itself first (absorbing any first-run effect) and only then proves the second run is a no-op.
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
declare r jsonb; a jsonb; b jsonb; n0 bigint; n1 bigint; dups bigint; hz int;
begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then raise exception 'REFUSED: not development'; end if;
  hz := coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_horizon_days'), 60);
  r := app.run_compliance_generation('uat');            -- absorbs a first run if none happened today
  r := app.run_compliance_generation('uat');            -- this one must be refused
  insert into _uat(step, result, detail) values ('2a. second wrapper call on the same day is refused',
    case when (r ->> 'ran')::boolean is false and r ->> 'reason' = 'already succeeded' then 'PASS' else 'FAIL' end, r);
  a := app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz);
  select count(*) into n0 from public.compliance_instance;
  b := app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz);
  select count(*) into n1 from public.compliance_instance;
  insert into _uat(step, result, detail) values ('2b. identical second direct execution inserts nothing',
    case when (b ->> 'inserted')::int = 0 and n0 = n1 and (b ->> 'already_existing')::int = (b ->> 'applicable_obligations')::int then 'PASS' else 'FAIL' end,
    b || jsonb_build_object('obligations_before', n0, 'obligations_after', n1));
  select count(*) into dups from (select 1 from public.compliance_instance group by compliance_id, location_id, period_start having count(*) > 1) d;
  insert into _uat(step, result, detail) values ('2c. no duplicate obligation keys (compliance, location, period)', case when dups = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('duplicate_groups', dups));
  insert into _uat(step, result, detail) values ('2d. total obligations in the database', 'INFO', jsonb_build_object('obligations', n1));
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
