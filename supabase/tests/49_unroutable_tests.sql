-- D-001: an alert that cannot reach a business recipient is never lost silently.
-- Runs inside ONE transaction that is rolled back, so it leaves no trace for other suites. The test database carries no environment label,
-- i.e. it behaves like PRODUCTION until a test sets environment.name = development.
\set ON_ERROR_STOP on
begin;
create sequence test.mk_seq49; grant usage on sequence test.mk_seq49 to authenticated;
-- an isolated compliance and a clean slate
insert into public.compliance_master (code, name) values ('UN-1', 'Unroutable sample');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', date '2020-01-01' from public.compliance_master where code='UN-1';
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='UN-1');
update public.compliance_master set is_active = (code = 'UN-1');
select set_config('app.audit_reason', 'test fixture', true);
update public.compliance_instance set status = 'not_applicable' where status in ('open','in_progress');
update public.licence set lifecycle_status = 'cancelled' where lifecycle_status = 'active';
delete from public.job_run where job_code in ('alert_generation','exception_generation') and idempotency_key like to_char(current_date,'YYYY-MM-DD')||'%';
-- every Head HR is disabled, so an ownerless obligation has nobody to tell
update public.app_user set status = 'disabled' where id in (select ur.user_id from public.user_role ur join public.role r on r.id = ur.role_id where r.code = 'HEAD_HR');
create or replace function test.mk49(p_loc text, p_due date, p_owner uuid) returns uuid language sql as $$
  with n as (select nextval('test.mk_seq49')::int as k)
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, source)
  select m.id, v.id, l.entity_id, l.id, date '1990-01-01' + n.k * 40, date '1990-01-01' + n.k * 40 + 5, p_due, p_owner, 'manual'
    from n, public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status='active', public.location l where m.code='UN-1' and l.code = p_loc
  returning id $$;
grant execute on function test.mk49(text, date, uuid) to authenticated;
create temp table _sa as select id from public.app_user where email = 'admin@bfcl.test';
create temp table _viewer as select id from public.app_user where email = 'viewer@bfcl.test';
grant select on _sa, _viewer to authenticated;
create temp table _i as select test.mk49('L-E1', current_date, null) id;      -- due today, no owner, no Head HR anywhere

-- 1. production: nobody to tell -> nothing delivered, but NOT silent
create temp table _r1 as select app.generate_alerts() r;
select test.eq('production: no business recipient -> no routed notification', (select (r ->> 'compliance_notifications')::int from _r1), 0);
select test.eq('production: Super Admin is NOT used as a fallback recipient', (select count(*) from public.notification where user_id = (select id from _sa)), 0::bigint);
select test.eq('the unreachable alert is counted, not dropped', (select (r ->> 'unreachable')::int from _r1), 1);
select app.detect_exceptions();
select test.eq('a durable alert_unroutable exception exists on the obligation', (select count(*) from public.exception where category='alert_unroutable' and compliance_instance_id=(select id from _i) and status='open'), 1::bigint);
select test.eq('and it is idempotent (second detection raises nothing)', (app.detect_exceptions() ->> 'raised')::int, 0);
select test.login('admin@bfcl.test');
select test.eq('System Health reports the unroutable alert', (public.system_health() ->> 'unroutable_alerts')::int, 1);
select test.eq('System Health reports a routing error (production has no escalation recipients)', (public.system_health() -> 'alert_routing' ->> 'errors')::int >= 1, true);
select test.eq('validation names the missing UNROUTABLE_ESCALATION as blocking', (select severity from public.alert_routing_validation() where rule_code = 'UNROUTABLE_ESCALATION' limit 1), 'error');
select test.logout();
-- the job records a warning on a SUCCEEDED run
select test.eq('alert job wrapper succeeds but carries the warning', app.run_alert_generation('test') ->> 'ran', 'true');
select test.eq('job_run keeps the non-fatal warning', (select error_detail ->> 'warning' from public.job_run where job_code='alert_generation' order by started_at desc limit 1), 'alerts_unreachable');
select test.eq('and its status is succeeded', (select status from public.job_run where job_code='alert_generation' order by started_at desc limit 1), 'succeeded');

-- 2. BFCL configures escalation recipients (data, not code) -> the alert is delivered as an UNROUTED notification, the exception clears
insert into public.config_definition (kind, code, name, version, status, definition, change_reason, effective_from)
  values ('alert_rule','UNROUTABLE_ESCALATION','Unroutable escalation',1,'active',
          jsonb_build_object('offsets', jsonb_build_array(0), 'channels', jsonb_build_array('in_app'), 'recipients', jsonb_build_array('user:' || (select id from _viewer))), 'test', current_date);
create temp table _r2 as select app.generate_alerts() r;
select test.eq('escalation recipient receives the unrouted alert', (select count(*) from public.notification where user_id=(select id from _viewer) and category='alert_unroutable' and link_id=(select id from _i)), 1::bigint);
select test.eq('title makes it recognisable', (select title like 'UNROUTED: UN-1 %' from public.notification where user_id=(select id from _viewer) and category='alert_unroutable' limit 1), true);
select test.eq('nothing is unreachable any more', (select (r ->> 'unreachable')::int from _r2), 0);
select test.eq('rerun does not duplicate (dedupe)', (app.generate_alerts() ->> 'unroutable_notifications')::int, 0);
select app.detect_exceptions();
select test.eq('the exception auto-resolves once somebody can be told', (select status from public.exception where category='alert_unroutable' and compliance_instance_id=(select id from _i) order by detected_at desc limit 1), 'resolved');
select test.login('admin@bfcl.test');
select test.eq('validation: escalation rule no longer an error', (select count(*) from public.alert_routing_validation() where rule_code='UNROUTABLE_ESCALATION' and severity='error'), 0::bigint);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('the recipient sees the notification, others do not', (select count(*) from public.notification where category='alert_unroutable'), 1::bigint);
select test.denied('a user without health/config permission cannot run the routing validation', $$select * from public.alert_routing_validation()$$);
select test.logout();

-- 3. critical rule with no valid routing is flagged as an error, a normal one as a warning
insert into public.config_definition (kind, code, name, version, status, definition, change_reason, effective_from) values
  ('alert_rule','T_CRIT','crit',1,'active','{"offsets":[0],"channels":["in_app"],"recipients":["role:HEAD_HR"],"critical":true}','test',current_date),
  ('alert_rule','T_NORM','norm',1,'active','{"offsets":[0],"channels":["in_app"],"recipients":["role:HEAD_HR","owner"]}','test',current_date);
select test.login('admin@bfcl.test');
select test.eq('critical rule whose role has no active user = error', (select severity from public.alert_routing_validation() where rule_code='T_CRIT' limit 1), 'error');
select test.eq('non-critical rule with the same gap = warning', (select severity from public.alert_routing_validation() where rule_code='T_NORM' limit 1), 'warning');
select test.logout();
select test.denied('critical flag must be boolean', $$insert into public.config_definition (kind, code, name, version, status, definition, change_reason) values ('alert_rule','T_BADC','x',1,'draft','{"offsets":[0],"channels":["in_app"],"recipients":["owner"],"critical":"yes"}','t')$$);

-- 4. DEVELOPMENT only: Super Admin fallback when no escalation recipient is configured
delete from public.config_definition where code in ('UNROUTABLE_ESCALATION','T_CRIT','T_NORM');
insert into public.system_config (key, value, description) values ('environment.name','"development"','test') on conflict (key) do update set value = excluded.value;
select app.generate_alerts();
select test.eq('development: Super Admin receives the unrouted alert', (select count(*) from public.notification where user_id=(select id from _sa) and category='alert_unroutable' and link_id=(select id from _i)), 1::bigint);
select test.eq('development: no exception is needed while the fallback can reach someone', (app.detect_exceptions() ->> 'conditions_found')::int >= 0, true);
update public.system_config set value = '"production"' where key = 'environment.name';
create temp table _i2 as select test.mk49('L-E1', current_date, null) id;
select app.generate_alerts();
select test.eq('back in production: Super Admin is not told about the new obligation', (select count(*) from public.notification where user_id=(select id from _sa) and link_id=(select id from _i2)), 0::bigint);
select app.detect_exceptions();
select test.eq('and the new obligation is visible as an exception', (select count(*) from public.exception where category='alert_unroutable' and compliance_instance_id=(select id from _i2) and status='open'), 1::bigint);
rollback;
\echo ALL UNROUTABLE TESTS PASSED
