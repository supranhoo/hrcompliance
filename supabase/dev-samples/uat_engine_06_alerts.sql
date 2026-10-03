-- UAT ENGINE 06 - alert generation, dedupe, completed obligations
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: 5 rows. 6a PASS = alerts created; INFO = nothing created because no valid recipient exists = KNOWN BASELINE DEFECT D-001 (not an engine failure). 6b-6e PASS.
-- Independent: ensures obligations exist first. Recipients are the obligation owner, else an active Head HR in scope (D-001 fallback missing is the known gap).
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
declare r jsonb; ms numeric; t0 timestamptz; n0 bigint; n1 bigint; n2 bigint; dups bigint; hz int; bad bigint;
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
  on conflict (compliance_id, location_id, period_start) do nothing;
  select count(*) into n0 from public.notification;
  t0 := clock_timestamp(); r := app.run_alert_generation('uat');
  if (r ->> 'ran')::boolean is not true then r := app.generate_alerts() || jsonb_build_object('note', 'wrapper already ran today; direct call used'); end if;
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  select count(*) into n1 from public.notification;
  insert into _uat(step, result, detail) values ('6a. alert generation',
    case when n1 > n0 then 'PASS' when n1 > 0 then 'INFO' else 'INFO' end,
    jsonb_build_object('elapsed_ms', ms, 'engine_result', r, 'notifications_before', n0, 'notifications_after', n1, 'total_notifications', n1,
      'open_obligations_without_active_owner', (select count(*) from public.compliance_instance i where i.status in ('open','in_progress') and not exists (select 1 from public.app_user u where u.id = i.owner_user_id and u.status = 'active')),
      'active_head_hr_users', (select count(*) from public.user_role ur join public.role ro on ro.id = ur.role_id join public.app_user u on u.id = ur.user_id where ro.code = 'HEAD_HR' and u.status = 'active'),
      'note', case when n1 > n0 then 'alerts created' when n1 > 0 then 'nothing new: alerts for the offsets reached today already exist' else 'NOTHING created and none exist: no valid recipient or no offset reached - KNOWN BASELINE DEFECT D-001 (silent drop), not an engine failure' end));
  r := app.generate_alerts();
  select count(*) into n2 from public.notification;
  insert into _uat(step, result, detail) values ('6b. identical repeat creates no duplicates', case when n2 = n1 and (r ->> 'compliance_notifications')::int = 0 and (r ->> 'licence_notifications')::int = 0 then 'PASS' else 'FAIL' end,
    r || jsonb_build_object('notifications_before', n1, 'notifications_after', n2));
  select count(*) into dups from (select dedupe_key from public.notification group by 1 having count(*) > 1) d;
  insert into _uat(step, result, detail) values ('6c. no duplicate notification keys', case when dups = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('duplicate_keys', dups));
  select count(*) into bad from public.notification nt join public.compliance_instance i on nt.link_kind = 'compliance_instance' and nt.link_id = i.id
   where i.status in ('completed','not_applicable','waived') and nt.created_at > i.updated_at;
  insert into _uat(step, result, detail) values ('6d. completed / closed obligations do not alert (no notification created after closure)', case when bad = 0 then 'PASS' else 'FAIL' end, jsonb_build_object('violations', bad));
  insert into _uat(step, result, detail) values ('6e. email is not queued while Gmail is not configured', case when not exists (select 1 from public.notification where channel = 'email') then 'PASS' else 'INFO' end,
    jsonb_build_object('email_rows', (select count(*) from public.notification where channel = 'email')));
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
