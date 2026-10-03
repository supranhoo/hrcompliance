-- UAT ENGINE 01 - compliance generator, first execution
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: 3 rows. 'obligations exist' = PASS (INFO if they were already generated earlier), 'wrapper' row explains the job result.
-- Run this FIRST. It also creates the three event-based SAMPLE obligations used by files 04-06. Safe to run again.
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
declare t0 timestamptz; ms numeric; r jsonb; r2 jsonb; n0 bigint; n1 bigint; hz int;
begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then raise exception 'REFUSED: not development'; end if;
  hz := coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_horizon_days'), 60);
  select count(*) into n0 from public.compliance_instance where compliance_id in (select id from public.compliance_master where code like 'SAMPLE-%');
  t0 := clock_timestamp();
  r := app.run_compliance_generation('uat');
  r2 := app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz);
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  -- three event-based SAMPLE obligations placed on alert offsets (due in 3 days / today / overdue by 2); idempotent by the obligation key
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, remarks, source)
  select m.id, v.id, l.entity_id, l.id, current_date - d.ago, current_date - d.ago, app.compute_due_date(v.due_rule, current_date - d.ago, current_date - d.ago), m.default_owner_user_id, d.note, 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l,
         (values (27, 'SAMPLE event: due in 3 days'), (30, 'SAMPLE event: due today'), (32, 'SAMPLE event: overdue by 2 days')) d(ago, note)
   where m.code = 'SAMPLE-EVENT' and l.code = 'SAMPLE-LOC-A'
  on conflict (compliance_id, location_id, period_start) where status <> 'superseded' do nothing;
  select count(*) into n1 from public.compliance_instance where compliance_id in (select id from public.compliance_master where code like 'SAMPLE-%');
  insert into _uat(step, result, detail) values
   ('1a. generator ran (job wrapper + 3-month backfill window)', case when r2 ? 'inserted' then 'PASS' else 'FAIL' end,
      jsonb_build_object('elapsed_ms', ms, 'wrapper_result', r, 'backfill_result', r2)),
   ('1b. SAMPLE obligations exist', case when n1 > n0 then 'PASS' when n1 > 0 then 'INFO' else 'FAIL' end,
      jsonb_build_object('before', n0, 'after', n1, 'rows_added', n1 - n0, 'note', case when n1 > n0 then 'new obligations created by this run' when n1 > 0 then 'already generated earlier (run remove_samples.sql + sample_compliance.sql for a fresh first run)' else 'NOTHING generated - defect' end)),
   ('1c. event-based SAMPLE obligations present (3 expected)', case when (select count(*) from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id where m.code = 'SAMPLE-EVENT') = 3 then 'PASS' else 'FAIL' end,
      jsonb_build_object('count', (select count(*) from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id where m.code = 'SAMPLE-EVENT')));
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
