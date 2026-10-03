-- Exception engine: detection, idempotency, auto-resolve, recurrence, severity, workflow, scope, ageing.
\set ON_ERROR_STOP on
-- ---------- fixtures (superuser) ----------
insert into public.compliance_master (code, name) values ('EXC-1', 'Exception sample monthly');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, evidence_required, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'high', true, date '2020-01-01' from public.compliance_master where code='EXC-1';
insert into public.compliance_rule_evidence (rule_version_id, document_type_id) select v.id, d.id from public.compliance_rule_version v join public.compliance_master m on m.id=v.compliance_id, public.document_type d where m.code='EXC-1' and d.code='EV-DOC';
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='EXC-1');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) select (select id from public.compliance_master where code='EXC-1'), id, 'applicable', 'sample', date '2020-01-01' from public.location where code='L-E1';
-- other suites' compliances must not add instances now
update public.compliance_master set is_active = (code = 'EXC-1');
select app.generate_compliance_instances(date '2025-01-01', date '2025-01-31');
select app.generate_compliance_instances(date_trunc('month', current_date)::date, date_trunc('month', current_date)::date);
create temp table _x_old as select id from public.compliance_instance where compliance_id=(select id from public.compliance_master where code='EXC-1') and period_start = date '2025-01-01';
create temp table _x_cur as select id from public.compliance_instance where compliance_id=(select id from public.compliance_master where code='EXC-1') and period_start = date_trunc('month', current_date)::date;
grant select on _x_old, _x_cur to authenticated;
create or replace function test.excs(prefix text) returns bigint language sql stable as $$ select count(*) from public.exception where detection_key like prefix || '%' $$;
create or replace function test.exc_status(k text) returns text language sql stable as $$ select string_agg(status, ',' order by detected_at, exception_no) from public.exception where detection_key = k $$;
grant execute on all functions in schema test to authenticated, anon;
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_HR' on conflict do nothing;
select test.eq('fixture: overdue instance exists', (select count(*) from _x_old), 1::bigint);
select test.eq('fixture: current-month instance exists and is not yet due', (select due_date > current_date from public.compliance_instance where id=(select id from _x_cur)), true);

-- ---------- detection ----------
create temp table _r1 as select app.detect_exceptions() r;
select test.eq('overdue exception raised for the past-due obligation', test.excs('compliance_overdue:' || (select id from _x_old)), 1::bigint);
select test.eq('missing-evidence exception raised (past due, nothing uploaded)', test.excs('evidence_missing:' || (select id from _x_old)), 1::bigint);
select test.eq('no exception for the not-yet-due obligation', test.excs('compliance_overdue:' || (select id from _x_cur)) + test.excs('evidence_missing:' || (select id from _x_cur)), 0::bigint);
select test.eq('severity comes from the rule risk (high)', (select severity from public.exception where detection_key = 'compliance_overdue:' || (select id from _x_old)), 'high');
select test.eq('exception number format', (select bool_and(exception_no ~ '^EXC-[0-9]{4}-[0-9]{6}$') from public.exception), true);
select test.eq('scope derived from the parent', (select (x.entity_id = i.entity_id and x.location_id = i.location_id)::text from public.exception x join public.compliance_instance i on i.id=x.compliance_instance_id where x.detection_key = 'compliance_overdue:' || (select id from _x_old)), 'true');
select test.eq('resolution target = detected + 3 days (high)', (select due_date - detected_at::date from public.exception where detection_key = 'compliance_overdue:' || (select id from _x_old)), 3);
select test.eq('timeline starts with "detected"', (select action_type from public.exception_action a join public.exception x on x.id=a.exception_id where x.detection_key = 'compliance_overdue:' || (select id from _x_old)), 'detected');
select test.eq('report counts raised conditions', ((select r from _r1) ->> 'raised')::int >= 2, true);
-- idempotency
create temp table _total as select count(*) n from public.exception;
select test.eq('re-run raises nothing', (app.detect_exceptions() ->> 'raised')::int, 0);
select test.eq('re-run creates no duplicate rows', (select count(*) from public.exception), (select n from _total));
-- 6 parallel-safe: unique active key even if inserted directly
select test.denied('duplicate ACTIVE detection key is impossible', $$insert into public.exception(category,severity,description,compliance_instance_id,entity_id,detection_key) select 'compliance_overdue','high','dup',id,(select id from public.entity limit 1),'compliance_overdue:' || id from _x_old$$);

-- ---------- completed without evidence ----------
update public.compliance_instance set status='completed' where id=(select id from _x_cur);
select app.detect_exceptions();
select test.eq('completed-without-evidence raises evidence_missing', test.excs('evidence_missing:' || (select id from _x_cur)), 1::bigint);
select test.eq('overdue exception stays open while the obligation is still unfinished', test.exc_status('compliance_overdue:' || (select id from _x_old)), 'open');
update public.compliance_instance set status='completed' where id=(select id from _x_old);
select app.detect_exceptions();
select test.eq('completing the obligation auto-resolves the overdue exception', test.exc_status('compliance_overdue:' || (select id from _x_old)), 'resolved');
select test.eq('auto-resolution is flagged and explained', (select auto_resolved::text || ':' || resolution from public.exception where detection_key = 'compliance_overdue:' || (select id from _x_old)), 'true:Condition cleared automatically');
select test.eq('timeline records auto-resolution', (select count(*) from public.exception_action a join public.exception x on x.id=a.exception_id where x.detection_key = 'compliance_overdue:' || (select id from _x_old) and a.action_type = 'auto_resolved'), 1::bigint);
select test.eq('missing evidence stays open until evidence exists', test.exc_status('evidence_missing:' || (select id from _x_old) || ':' || (select id from public.document_type where code='EV-DOC')), 'open');
insert into public.evidence (compliance_instance_id, document_type_id, storage_file_id, file_name, mime_type, size_bytes) select (select id from _x_old), id, 'drive-x-old', 'x.pdf', 'application/pdf', 100 from public.document_type where code='EV-DOC';
select app.detect_exceptions();
select test.eq('uploading the evidence auto-resolves missing-evidence', test.exc_status('evidence_missing:' || (select id from _x_old) || ':' || (select id from public.document_type where code='EV-DOC')), 'resolved');

-- ---------- recurrence: condition returns -> NEW exception, history kept ----------
begin; select set_config('app.audit_reason', 'completed by mistake', true); update public.compliance_instance set status='open' where id=(select id from _x_old); commit;
select app.detect_exceptions();
select test.eq('re-opened obligation raises a fresh overdue exception', test.exc_status('compliance_overdue:' || (select id from _x_old)), 'resolved,open');
select test.eq('old resolved record is retained', test.excs('compliance_overdue:' || (select id from _x_old)), 2::bigint);

-- ---------- evidence rejected / expired ----------
update public.evidence set verification_status='rejected', verification_remarks='illegible' where compliance_instance_id=(select id from _x_old) and is_current;
select app.detect_exceptions();
select test.eq('rejected evidence raises an exception', test.excs('evidence_rejected:'), 1::bigint);
update public.evidence set verification_status='verified', verification_remarks='ok', expiry_date = current_date - 2 where compliance_instance_id=(select id from _x_old) and is_current;
select app.detect_exceptions();
select test.eq('rejected exception clears when evidence is verified', (select count(*) from public.exception where category='evidence_rejected' and status='open'), 0::bigint);
select test.eq('expired evidence raises an exception', (select count(*) from public.exception where category='evidence_expired' and status='open'), 1::bigint);
update public.evidence set expiry_date = current_date + 90 where compliance_instance_id=(select id from _x_old) and is_current;
select app.detect_exceptions();
select test.eq('expired exception clears when expiry is extended', (select count(*) from public.exception where category='evidence_expired' and status='open'), 0::bigint);

-- ---------- licences ----------
select test.eq('licence expiring inside its renewal window is flagged (NO-1: 3 days, lead 30)', (select count(*) from public.exception where category='licence_expiring' and status='open' and licence_id=(select id from public.licence where licence_number='NO-1')), 1::bigint);
select test.eq('expiring severity = licence risk (high)', (select severity from public.exception where category='licence_expiring' and licence_id=(select id from public.licence where licence_number='NO-1')), 'high');
insert into public.licence (licence_type_id, entity_id, location_id, licence_number, expiry_date, risk_level) select (select id from public.licence_type where code='LT-FACT'), l.entity_id, l.id, 'X-EXP-HIGH', current_date - 1, 'high' from public.location l where l.code='L-E1';
insert into public.licence (licence_type_id, entity_id, location_id, licence_number, expiry_date, risk_level) select (select id from public.licence_type where code='LT-FACT'), l.entity_id, l.id, 'X-EXP-LOW', current_date - 1, 'low' from public.location l where l.code='L-E1';
select app.detect_exceptions();
select test.eq('expired licence with high risk -> critical', (select severity from public.exception where category='licence_expired' and licence_id=(select id from public.licence where licence_number='X-EXP-HIGH')), 'critical');
select test.eq('expired licence with low risk -> high', (select severity from public.exception where category='licence_expired' and licence_id=(select id from public.licence where licence_number='X-EXP-LOW')), 'high');
update public.licence set renewal_status='renewed' where licence_number='NO-1';
select app.detect_exceptions();
select test.eq('renewed licence clears its expiring exception', (select count(*) from public.exception where category='licence_expiring' and status='open' and licence_id=(select id from public.licence where licence_number='NO-1')), 0::bigint);
update public.licence set lifecycle_status='cancelled' where licence_number='X-EXP-LOW';
select app.detect_exceptions();
select test.eq('cancelled licence stops raising expiry exceptions', (select status from public.exception where category='licence_expired' and licence_id=(select id from public.licence where licence_number='X-EXP-LOW')), 'resolved');

-- ---------- workflow + manual exceptions (user level) ----------
select test.login('headhr@bfcl.test');
insert into public.exception (category, severity, description, compliance_instance_id, source) select 'manual','medium','Inspector flagged register gap', id, 'manual' from _x_cur;
select test.eq('manual exception created with derived scope and key', (select (detection_key like 'manual:%' and entity_id is not null)::text from public.exception where source='manual'), 'true');
select test.denied('API users cannot raise AUTO exceptions', $$insert into public.exception(category,severity,description,compliance_instance_id,source) select 'compliance_overdue','high','fake',id,'auto' from _x_cur$$);
update public.exception set status='acknowledged', owner_user_id=(select id from public.app_user where email='headhr@bfcl.test') where source='manual';
select test.denied('resolving requires a resolution', $$update public.exception set status='resolved' where source='manual'$$);
update public.exception set status='resolved', resolution='Register completed' where source='manual';
select test.eq('resolver and time stamped', (select (resolved_by is not null and resolved_at is not null)::text from public.exception where source='manual'), 'true');
select test.denied('reopening needs a reason', $$update public.exception set status='open' where source='manual'$$);
select test.denied('identity immutable (category)', $$update public.exception set category='licence_expired' where source='manual'$$);
select test.denied('identity immutable (parent)', $$update public.exception set compliance_instance_id = (select id from _x_old) where source='manual'$$);
insert into public.exception_action (exception_id, action_type, note) select id, 'comment', 'discussed on call' from public.exception where source='manual';
select test.eq('writers can comment', (select count(*) from public.exception_action where action_type='comment'), 1::bigint);
select test.denied('comments only — cannot forge system actions', $$insert into public.exception_action(exception_id,action_type,note) select id,'auto_resolved','x' from public.exception where source='manual'$$);
select test.denied('no delete privilege', 'delete from public.exception');
select test.logout();
select test.eq('manual exceptions are never auto-resolved', (select status from public.exception where source='manual'), 'resolved');
select app.detect_exceptions();
select test.eq('detection leaves manual exceptions alone', (select count(*) from public.exception where source='manual'), 1::bigint);

-- ---------- ageing view ----------
select test.eq('fresh exception is in the 0-7 bucket', (select age_bucket from public.v_exception where category='licence_expired' and licence_id=(select id from public.licence where licence_number='X-EXP-HIGH')), '0-7');
alter table public.exception disable trigger exception_guard;   -- fixture only: detected_at is immutable for every API path
update public.exception set detected_at = now() - interval '40 days', due_date = current_date - 30 where category='licence_expired' and licence_id=(select id from public.licence where licence_number='X-EXP-HIGH');
alter table public.exception enable trigger exception_guard;
select test.eq('40-day-old exception is in 31-90 and its target is breached', (select age_bucket || ':' || age_days || ':' || target_breached from public.v_exception where category='licence_expired' and licence_id=(select id from public.licence where licence_number='X-EXP-HIGH')), '31-90:40:true');
select test.eq('closed exceptions report closed bucket', (select age_bucket from public.v_exception where source='manual'), 'closed');

-- ---------- access ----------
select test.login('plant@bfcl.test');
select test.eq('scoped user sees exceptions in scope', test.count('select * from public.exception') > 0, true);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('viewer without scope sees nothing', test.count('select * from public.exception'), 0::bigint);
select test.eq('viewer without scope sees nothing in the ageing view', test.count('select * from public.v_exception'), 0::bigint);
select test.denied('API role cannot run detection', $$select app.detect_exceptions()$$);
select test.logout();
select test.login('stranger@gmail.com');
select test.eq('unprovisioned sees nothing', test.count('select * from public.exception') + test.count('select * from public.exception_action'), 0::bigint);
select test.logout();

-- ---------- job wrapper ----------
select test.eq('scheduler wrapper runs and logs', (app.run_exception_detection('test') ->> 'ran')::boolean, true);
select test.eq('same-hour rerun refused by job idempotency', app.run_exception_detection('test') ->> 'reason', 'already succeeded');
select test.eq('job recorded as succeeded', (select status from public.job_run where job_code='exception_generation' order by started_at desc limit 1), 'succeeded');
select test.eq('exception activity audited', (select count(*) from public.audit_log where table_name='exception') >= 15, true);
\echo ALL EXCEPTION TESTS PASSED
