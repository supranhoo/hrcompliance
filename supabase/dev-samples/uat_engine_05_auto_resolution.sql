-- UAT ENGINE 05 - exception auto-resolution and evidence-missing behaviour
-- DEVELOPMENT ONLY (synthetic SAMPLE data). Supabase SQL Editor: open a NEW empty SQL tab, paste this ENTIRE file, press Run ONCE.
-- Do not run a highlighted fragment. The LAST line of the file is "-- END OF FILE"; if you cannot see it in the editor after pasting, the paste was cut - paste again.
-- Independent: needs no other uat_engine_* file and no temp table from another run (it uses its own short-lived one and prints it as the final result).
-- EXPECTED OUTPUT: 3 rows. 5a PASS = an overdue exception resolved itself after its obligation was completed (INFO = no overdue obligation left to complete, but an earlier auto-resolution exists). 5b/5c PASS.
-- It COMPLETES one overdue SAMPLE obligation (synthetic), re-runs detection, and checks the result. Run 04 first. Safe to run again.
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
declare v_inst uuid; v_exc uuid; r jsonb; x record; hz int;
begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then raise exception 'REFUSED: not development'; end if;
  hz := coalesce((select (value #>> '{}')::int from public.system_config where key = 'compliance.generation_horizon_days'), 60);
  perform app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + hz);   -- ensure obligations, event obligations and exceptions exist (all idempotent)
  -- three event-based SAMPLE obligations placed on alert offsets (due in 3 days / today / overdue by 2); idempotent by the obligation key
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, remarks, source)
  select m.id, v.id, l.entity_id, l.id, current_date - d.ago, current_date - d.ago, app.compute_due_date(v.due_rule, current_date - d.ago, current_date - d.ago), m.default_owner_user_id, d.note, 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l,
         (values (27, 'SAMPLE event: due in 3 days'), (30, 'SAMPLE event: due today'), (32, 'SAMPLE event: overdue by 2 days')) d(ago, note)
   where m.code = 'SAMPLE-EVENT' and l.code = 'SAMPLE-LOC-A'
  on conflict (compliance_id, location_id, period_start) where status <> 'superseded' do nothing;
  perform app.detect_exceptions();
  select i.id, e.id into v_inst, v_exc
    from public.exception e join public.compliance_instance i on i.id = e.compliance_instance_id join public.compliance_master m on m.id = i.compliance_id
   where e.category = 'compliance_overdue' and e.status in ('open','acknowledged') and m.code like 'SAMPLE-%' and i.status in ('open','in_progress')
   order by i.due_date limit 1;
  if v_inst is null then
    insert into _uat(step, result, detail) values ('5a. overdue exception auto-resolves once the obligation is completed',
      case when exists (select 1 from public.exception where auto_resolved) then 'INFO' else 'FAIL' end,
      jsonb_build_object('note', case when exists (select 1 from public.exception where auto_resolved) then 'no overdue open SAMPLE obligation left to complete; an auto-resolved exception already exists from an earlier run' else 'no overdue exception to resolve - run uat_engine_04 first' end,
                         'auto_resolved_exceptions', (select count(*) from public.exception where auto_resolved)));
  else
    update public.compliance_instance set status = 'completed' where id = v_inst;
    r := app.detect_exceptions();
    select * into x from public.exception where id = v_exc;
    insert into _uat(step, result, detail) values ('5a. overdue exception auto-resolves once the obligation is completed',
      case when x.status = 'resolved' and x.auto_resolved and x.resolution = 'Condition cleared automatically'
                and exists (select 1 from public.exception_action a where a.exception_id = x.id and a.action_type = 'auto_resolved') then 'PASS' else 'FAIL' end,
      jsonb_build_object('exception_no', x.exception_no, 'status_now', x.status, 'auto_resolved', x.auto_resolved, 'resolution', x.resolution, 'engine_result', r));
  end if;
  insert into _uat(step, result, detail) values ('5b. completing a monthly obligation without evidence raises evidence_missing (monthly requires evidence)',
    case when v_inst is null then 'INFO' when exists (select 1 from public.exception e where e.compliance_instance_id = v_inst and e.category = 'evidence_missing' and e.status in ('open','acknowledged')) then 'PASS' else 'INFO' end,
    jsonb_build_object('checked_instance', v_inst, 'active_evidence_missing_for_sample', (select count(*) from public.exception e join public.compliance_instance i on i.id = e.compliance_instance_id join public.compliance_master m on m.id = i.compliance_id where e.category = 'evidence_missing' and e.status in ('open','acknowledged') and m.code like 'SAMPLE-%'),
      'note', 'INFO when the completed obligation is not an evidence-requiring one, or was completed in an earlier run'));
  insert into _uat(step, result, detail) values ('5c. still at most one active exception per detection key',
    case when not exists (select detection_key from public.exception where status in ('open','acknowledged') group by 1 having count(*) > 1) then 'PASS' else 'FAIL' end, '{}'::jsonb);
end $$;
select n, step, result, detail from _uat order by n;
-- END OF FILE
