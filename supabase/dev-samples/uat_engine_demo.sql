-- ENGINEERING / CLI USE (psql). For the live Supabase SQL Editor use the small modular runner uat_engine_01..08 instead (see docs/UAT_PHASE6_RUNBOOK.md): this file is one large DO block that the editor paste can truncate.
-- LIVE ENGINE DEMONSTRATION (DEVELOPMENT ONLY). Run AFTER sample_compliance.sql, as postgres, in the SQL editor of bfcl-hrc-dev.
-- Runs the generator, exception detector and alert engine step by step, records elapsed time and affected-row counts, and prints one
-- result table at the end. It changes only synthetic SAMPLE obligations (it completes one overdue SAMPLE obligation to show auto-resolution).
-- PASS/FAIL are decided by the script; INFO means the step could not demonstrate the behaviour (explained in detail) - it is never hidden.
-- !! RUN THE COMPLETE FILE, TOP TO BOTTOM, IN ONE EXECUTION. !! In the Supabase SQL editor: click into the editor, select all (Ctrl/Cmd+A) or
-- select nothing, then Run. Do NOT run a highlighted fragment: the statements below are PL/pgSQL (inside DO blocks) and use a session temp table
-- that exist only when the whole file runs. A fragment such as "select ... into lb, hz" run outside its DO block fails with
-- 'syntax error at or near ","' (outside PL/pgSQL, SELECT ... INTO means 'create table' and takes one name). That error means partial execution,
-- not a database fault.
-- Safe to re-run: engines are idempotent; steps that need a fresh state report INFO instead of failing.
-- SAFETY GUARD: refuses to run unless this database is explicitly labelled DEVELOPMENT. Set it once, by hand, in the dev project only:
--   insert into public.system_config (key, value, description) values ('environment.name', '"development"', 'Environment label') on conflict (key) do update set value = excluded.value;
-- UAT and production must carry 'uat' / 'production' (or no label), so these synthetic-data scripts can never run there by accident.
do $guard$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name). Synthetic SAMPLE data must never be loaded outside the DEVELOPMENT project.';
  end if;
end $guard$;
create temp table _demo (n serial primary key, step text, result text, elapsed_ms numeric, detail jsonb);

do $$
declare
  t0 timestamptz; ms numeric; r jsonb; r2 jsonb;
  inst0 bigint; inst1 bigint; exc0 bigint; exc1 bigint; ntf0 bigint; ntf1 bigint; dups bigint; hz int;
  v_inst uuid; v_overdue_exc uuid; n_other bigint;
  non_sample bigint;
begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name).';
  end if;
  if (select count(*) from public.compliance_master where code like 'SAMPLE-%') < 3 then
    raise exception 'Load supabase/dev-samples/sample_compliance.sql first (SAMPLE masters not found)';
  end if;
  select count(*) into non_sample from public.compliance_master where code not like 'SAMPLE-%' and is_active;
  insert into _demo(step, result, detail) values ('0. precondition', case when non_sample = 0 then 'PASS' else 'INFO' end,
    jsonb_build_object('sample_compliances', (select count(*) from public.compliance_master where code like 'SAMPLE-%'), 'non_sample_active_compliances', non_sample,
      'note', case when non_sample = 0 then 'only synthetic data is active: engine counts below are sample-only' else 'real masters are active: engine counts include them (the engines act on ALL active data)' end));
  select coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_horizon_days'), 60) into hz;

  select count(*) into inst0 from public.compliance_instance;
  select count(*) into exc0 from public.exception;
  select count(*) into ntf0 from public.notification;

  -- 1. generator, first execution via the job wrapper (logged in job_run). Window widened to 3 months back so sample history exists.
  t0 := clock_timestamp();
  r := app.run_compliance_generation('uat');
  if (r ->> 'ran')::boolean is not true then r := app.generate_compliance_instances(current_date - 90, current_date + hz) || jsonb_build_object('note', 'wrapper already ran today; direct call used'); end if;
  r2 := app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz);
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into inst1 from public.compliance_instance;
  insert into _demo(step, result, elapsed_ms, detail) values ('1. generator - first execution (wrapper + 3-month backfill window)',
    case when inst1 > inst0 then 'PASS' else 'INFO' end, round(ms, 1),
    jsonb_build_object('wrapper_result', r, 'backfill_result', r2, 'obligations_before', inst0, 'obligations_after', inst1, 'rows_added', inst1 - inst0,
      'note', case when inst1 > inst0 then 'new obligations created' else 'nothing new: already generated earlier (re-run after remove_samples.sql for a fresh first run)' end));

  -- 2. wrapper again the same day -> refused by job idempotency
  t0 := clock_timestamp(); r := app.run_compliance_generation('uat'); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  insert into _demo(step, result, elapsed_ms, detail) values ('2a. generator - second wrapper call same day is refused',
    case when (r ->> 'ran')::boolean is false and r ->> 'reason' = 'already succeeded' then 'PASS' else 'FAIL' end, round(ms, 1), r);

  -- 2b. identical direct execution: zero inserts, everything reported as already existing
  select count(*) into inst0 from public.compliance_instance;
  t0 := clock_timestamp(); r := app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into inst1 from public.compliance_instance;
  insert into _demo(step, result, elapsed_ms, detail) values ('2b. generator - identical second execution creates nothing',
    case when (r ->> 'inserted')::int = 0 and inst0 = inst1 and (r ->> 'already_existing')::int = (r ->> 'applicable_obligations')::int then 'PASS' else 'FAIL' end,
    round(ms, 1), r || jsonb_build_object('obligations_before', inst0, 'obligations_after', inst1));
  select count(*) into dups from (select 1 from public.compliance_instance group by compliance_id, location_id, period_start having count(*) > 1) d;
  insert into _demo(step, result, detail) values ('2c. no duplicate obligations (compliance, location, period)', case when dups = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('duplicate_groups', dups));
  select count(*) into n_other from public.compliance_instance i join public.location l on l.id = i.location_id
   where l.code = 'SAMPLE-LOC-B' and i.compliance_id = (select id from public.compliance_master where code = 'SAMPLE-QUARTERLY');
  insert into _demo(step, result, detail) values ('2d. applicability: conditional rule (50+ employees) kept the small office out of the quarterly obligation',
    case when n_other = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('quarterly_obligations_at_office_B', n_other));

  -- 2e. three event-based SAMPLE obligations placed ON alert offsets today (the same effect as a person raising events via compliance_create_manual_instance;
  --     inserted directly because this script runs as postgres, not as an app user). Idempotent by the obligation key.
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, remarks, source)
  select m.id, v.id, l.entity_id, l.id, current_date - d.ago, current_date - d.ago, app.compute_due_date(v.due_rule, current_date - d.ago, current_date - d.ago), m.default_owner_user_id, d.note, 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l,
         (values (27, 'SAMPLE event: due in 3 days (T-3 reminder reached today)'), (30, 'SAMPLE event: due today (T0 reminder)'), (32, 'SAMPLE event: overdue by 2 days (D+1 reminder, overdue exception)')) d(ago, note)
   where m.code = 'SAMPLE-EVENT' and l.code = 'SAMPLE-LOC-A'
  on conflict (compliance_id, location_id, period_start) do nothing;
  insert into _demo(step, result, detail) values ('2e. event-based SAMPLE obligations on alert offsets (due in 3 days, due today, overdue by 2)',
    case when (select count(*) from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id where m.code = 'SAMPLE-EVENT') = 3 then 'PASS' else 'FAIL' end,
    jsonb_build_object('event_obligations', (select count(*) from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id where m.code = 'SAMPLE-EVENT')));

  -- 3. exception detection, first execution
  select count(*) into exc0 from public.exception;
  t0 := clock_timestamp(); r := app.run_exception_detection('uat');
  if (r ->> 'ran')::boolean is not true then r := app.detect_exceptions() || jsonb_build_object('note', 'wrapper already ran this hour; direct call used'); end if;
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into exc1 from public.exception;
  insert into _demo(step, result, elapsed_ms, detail) values ('3. exceptions - first detection', case when exc1 > exc0 then 'PASS' else 'INFO' end, round(ms, 1),
    jsonb_build_object('result', r, 'exceptions_before', exc0, 'exceptions_after', exc1, 'rows_added', exc1 - exc0,
      'by_category', (select coalesce(jsonb_object_agg(category, c), '{}') from (select category, count(*) c from public.exception where status in ('open','acknowledged') group by 1) x)));

  -- 3b. identical second detection: nothing new
  t0 := clock_timestamp(); r := app.detect_exceptions(); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into exc0 from public.exception;
  insert into _demo(step, result, elapsed_ms, detail) values ('3b. exceptions - identical second detection raises nothing', case when (r ->> 'raised')::int = 0 and exc0 = exc1 then 'PASS' else 'FAIL' end, round(ms, 1),
    r || jsonb_build_object('exceptions_before', exc1, 'exceptions_after', exc0));
  select count(*) into dups from (select detection_key from public.exception where status in ('open','acknowledged') group by 1 having count(*) > 1) d;
  insert into _demo(step, result, detail) values ('3c. at most one active exception per detection key', case when dups = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('duplicate_keys', dups));

  -- 4. auto-resolution: complete one overdue SAMPLE obligation, re-detect
  select i.id, x.id into v_inst, v_overdue_exc
    from public.exception x join public.compliance_instance i on i.id = x.compliance_instance_id
    join public.compliance_master m on m.id = i.compliance_id
   where x.category = 'compliance_overdue' and x.status in ('open','acknowledged') and m.code like 'SAMPLE-%' and i.status in ('open','in_progress')
   order by i.due_date limit 1;
  if v_inst is null then
    insert into _demo(step, result, detail) values ('4. exceptions - auto-resolution when the condition clears', 'INFO', jsonb_build_object('note', 'no open overdue SAMPLE obligation (already completed in an earlier run)'));
  else
    update public.compliance_instance set status = 'completed' where id = v_inst;           -- a legitimate transition (open/in_progress -> completed)
    t0 := clock_timestamp(); r := app.detect_exceptions(); ms := extract(epoch from clock_timestamp() - t0) * 1000;
    insert into _demo(step, result, elapsed_ms, detail)
    select '4. exceptions - overdue exception auto-resolves once the obligation is completed',
           case when x.status = 'resolved' and x.auto_resolved and x.resolution = 'Condition cleared automatically'
                 and exists (select 1 from public.exception_action a where a.exception_id = x.id and a.action_type = 'auto_resolved') then 'PASS' else 'FAIL' end,
           round(ms, 1), jsonb_build_object('exception_no', x.exception_no, 'status_now', x.status, 'auto_resolved', x.auto_resolved, 'engine_result', r,
             'completed_without_evidence_exception_raised', (select count(*) from public.exception e where e.compliance_instance_id = v_inst and e.category = 'evidence_missing' and e.status in ('open','acknowledged')),
             'note', 'a monthly SAMPLE obligation REQUIRES evidence, so completing it with no document correctly raises a new evidence_missing exception')
      from public.exception x where x.id = v_overdue_exc;
  end if;

  -- 5. alerts, first execution
  select count(*) into ntf0 from public.notification;
  t0 := clock_timestamp(); r := app.run_alert_generation('uat');
  if (r ->> 'ran')::boolean is not true then r := app.generate_alerts() || jsonb_build_object('note', 'wrapper already ran today; direct call used'); end if;
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into ntf1 from public.notification;
  insert into _demo(step, result, elapsed_ms, detail) values ('5. alerts - first generation', case when ntf1 > ntf0 then 'PASS' else 'INFO' end, round(ms, 1),
    jsonb_build_object('result', r, 'notifications_before', ntf0, 'notifications_after', ntf1, 'rows_added', ntf1 - ntf0, 'email_queued', (select count(*) from public.notification where channel = 'email'),
      'open_obligations_without_active_owner', (select count(*) from public.compliance_instance i where i.status in ('open','in_progress') and not exists (select 1 from public.app_user u where u.id = i.owner_user_id and u.status = 'active')),
      'active_head_hr_users', (select count(*) from public.user_role ur join public.role ro on ro.id = ur.role_id join public.app_user u on u.id = ur.user_id where ro.code = 'HEAD_HR' and u.status = 'active'),
      'note', case when ntf1 > ntf0 then 'alerts created' else 'NOTHING created: either no offset is reached today or obligations have no routable recipient (defect D-001: such alerts are dropped silently) - check the two counts above' end));

  -- 5b. repeat: no inappropriate duplicates (new alerts appear only when a NEW offset is reached, i.e. on a later day)
  select count(*) into ntf0 from public.notification;
  t0 := clock_timestamp(); r := app.generate_alerts(); ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into ntf1 from public.notification;
  insert into _demo(step, result, elapsed_ms, detail) values ('5b. alerts - identical repeat creates no duplicates', case when ntf1 = ntf0 and (r ->> 'compliance_notifications')::int = 0 and (r ->> 'licence_notifications')::int = 0 then 'PASS' else 'FAIL' end,
    round(ms, 1), r || jsonb_build_object('notifications_before', ntf0, 'notifications_after', ntf1));
  select count(*) into dups from (select dedupe_key from public.notification group by 1 having count(*) > 1) d;
  insert into _demo(step, result, detail) values ('5c. no duplicate notification keys', case when dups = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('duplicate_keys', dups));
  insert into _demo(step, result, detail) values ('5d. completed obligations do not alert',
    case when v_inst is null or not exists (select 1 from public.notification where link_kind = 'compliance_instance' and link_id = v_inst and created_at > now() - interval '1 minute') then 'PASS' else 'FAIL' end,
    jsonb_build_object('checked_instance', v_inst));
end $$;

-- job log for the three engines (what the Job Monitor will show)
insert into _demo(step, result, detail)
select '6. job_run entries for the three engines', case when count(*) filter (where status = 'succeeded') >= 1 then 'PASS' else 'INFO' end,
       coalesce(jsonb_agg(jsonb_build_object('job', job_code, 'key', idempotency_key, 'status', status, 'attempt', attempt, 'records', records_processed,
                 'duration_ms', round(extract(epoch from completed_at - started_at) * 1000), 'env', environment) order by started_at desc), '[]')
  from (select * from public.job_run where job_code in ('compliance_generation','exception_generation','alert_generation') order by started_at desc limit 9) j;

insert into _demo(step, result, detail)
select '7. OVERALL', case when count(*) filter (where result = 'FAIL') = 0 then 'PASS' else 'FAIL' end,
       jsonb_build_object('pass', count(*) filter (where result = 'PASS'), 'fail', count(*) filter (where result = 'FAIL'), 'info', count(*) filter (where result = 'INFO')) from _demo where n < (select max(n) from _demo);

select n, step, result, elapsed_ms, detail from _demo order by n;
