-- UAT ENGINE 04 - exception detection and idempotency
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: 5 rows, all PASS (INFO on row 4a only if exceptions already existed from an earlier run).
-- Independent: ensures obligations exist first. Detection is idempotent; a repeat raises nothing.
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
declare r jsonb; ms numeric; t0 timestamptz; e0 bigint; e1 bigint; e2 bigint; dups bigint; hz int;
begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then raise exception 'REFUSED: not development'; end if;
  hz := coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_horizon_days'), 60);
  perform app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz);
  -- three event-based SAMPLE obligations placed on alert offsets (due in 3 days / today / overdue by 2); idempotent by the obligation key
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, remarks, source)
  select m.id, v.id, l.entity_id, l.id, current_date - d.ago, current_date - d.ago, app.compute_due_date(v.due_rule, current_date - d.ago, current_date - d.ago), m.default_owner_user_id, d.note, 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l,
         (values (27, 'SAMPLE event: due in 3 days'), (30, 'SAMPLE event: due today'), (32, 'SAMPLE event: overdue by 2 days')) d(ago, note)
   where m.code = 'SAMPLE-EVENT' and l.code = 'SAMPLE-LOC-A'
  on conflict (compliance_id, location_id, period_start) where status <> 'superseded' do nothing;
  select count(*) into e0 from public.exception;
  t0 := clock_timestamp(); r := app.run_exception_detection('uat');                -- job wrapper: logs the run in job_run
  if (r ->> 'ran')::boolean is not true then r := app.detect_exceptions() || jsonb_build_object('note', 'wrapper already ran this hour; direct call used'); end if;
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  select count(*) into e1 from public.exception;
  insert into _uat(step, result, detail) values ('4a. exceptions raised by detection (or already present)',
    case when e1 > e0 then 'PASS' when exists (select 1 from public.exception) then 'INFO' else 'FAIL' end,
    jsonb_build_object('elapsed_ms', ms, 'engine_result', r, 'before', e0, 'after', e1,
      'active_by_category', (select coalesce(jsonb_object_agg(category, c), '{}') from (select category, count(*) c from public.exception where status in ('open','acknowledged') group by 1) x)));
  r := app.detect_exceptions();
  select count(*) into e2 from public.exception;
  insert into _uat(step, result, detail) values ('4b. identical second detection raises nothing', case when (r ->> 'raised')::int = 0 and e2 = e1 then 'PASS' else 'FAIL' end,
    r || jsonb_build_object('before', e1, 'after', e2));
  select count(*) into dups from (select detection_key from public.exception where status in ('open','acknowledged') group by 1 having count(*) > 1) d;
  insert into _uat(step, result, detail) values ('4c. at most one active exception per detection key', case when dups = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('duplicate_keys', dups));
  insert into _uat(step, result, detail) values ('4d. an overdue SAMPLE obligation has (or had) an overdue exception',
    case when exists (select 1 from public.exception x join public.compliance_instance i on i.id = x.compliance_instance_id join public.compliance_master m on m.id = i.compliance_id where x.category = 'compliance_overdue' and m.code like 'SAMPLE-%') then 'PASS' else 'FAIL' end,
    jsonb_build_object('overdue_exceptions', (select count(*) from public.exception x join public.compliance_instance i on i.id = x.compliance_instance_id join public.compliance_master m on m.id = i.compliance_id where x.category = 'compliance_overdue' and m.code like 'SAMPLE-%')));
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
