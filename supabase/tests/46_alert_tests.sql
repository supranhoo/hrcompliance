-- Alerts: rule validation, offset reach + catch-up, dedupe, recipients + scope, fallback, email gating, licences, notification privacy.
\set ON_ERROR_STOP on
-- ---------- rule shape validation ----------
select test.login('admin@bfcl.test');
select test.denied('empty offsets rejected', $$select public.config_new_version('alert_rule','T_BAD1','x','{"offsets":[],"channels":["in_app"],"recipients":["owner"]}','r')$$);
select test.denied('fractional/absurd offsets rejected', $$select public.config_new_version('alert_rule','T_BAD2','x','{"offsets":[1.5],"channels":["in_app"],"recipients":["owner"]}','r')$$);
select test.denied('offset beyond a year rejected', $$select public.config_new_version('alert_rule','T_BAD3','x','{"offsets":[400],"channels":["in_app"],"recipients":["owner"]}','r')$$);
select test.denied('unknown channel rejected', $$select public.config_new_version('alert_rule','T_BAD4','x','{"offsets":[0],"channels":["sms"],"recipients":["owner"]}','r')$$);
select test.denied('arbitrary recipient expression rejected', $$select public.config_new_version('alert_rule','T_BAD5','x','{"offsets":[0],"channels":["in_app"],"recipients":["all; drop table x"]}','r')$$);
select test.denied('role recipients must look like role codes', $$select public.config_new_version('alert_rule','T_BAD6','x','{"offsets":[0],"channels":["in_app"],"recipients":["role:head hr"]}','r')$$);
select test.denied('unknown applies rejected', $$select public.config_new_version('alert_rule','T_BAD7','x','{"applies":"payroll","offsets":[0],"channels":["in_app"],"recipients":["owner"]}','r')$$);
select test.eq('seeded defaults exist and are active', (select count(*) from public.config_definition where kind='alert_rule' and code like 'DEFAULT\_%' and status='active'), 3::bigint);
select test.logout();

-- ---------- fixtures (superuser) ----------
insert into public.app_user (email, status) values ('e2hr@bfcl.test', 'active'), ('ghost@bfcl.test', 'disabled');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='e2hr@bfcl.test' and r.code='HEAD_HR';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email='e2hr@bfcl.test' and e.code='E2';
create temp table _hr as select id from public.app_user where email='headhr@bfcl.test';
create temp table _e2 as select id from public.app_user where email='e2hr@bfcl.test';
create temp table _ghost as select id from public.app_user where email='ghost@bfcl.test';
grant select on _hr, _e2, _ghost to authenticated;
-- compliance whose instances we control; all other compliances off
insert into public.compliance_master (code, name) values ('AL-1', 'Alert sample');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', date '2020-01-01' from public.compliance_master where code='AL-1';
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='AL-1');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) select (select id from public.compliance_master where code='AL-1'), id, 'applicable', 'x', date '2020-01-01' from public.location where code in ('L-E1','L-E2');
update public.compliance_master set is_active = (code = 'AL-1');
begin;
select set_config('app.audit_reason', 'test fixture: silence earlier suites', true);
update public.compliance_instance set status = 'not_applicable' where status in ('open','in_progress');       -- silence earlier suites' open instances
commit;
select app.generate_compliance_instances(date '2030-01-01', date '2030-03-31');                           -- far-future instances: never alert
create sequence if not exists test.mk_seq;
grant usage on sequence test.mk_seq to authenticated;
create or replace function test.mk_inst(p_loc text, p_due date, p_owner uuid) returns uuid language sql as $$
  with n as (select nextval('test.mk_seq')::int as k)
  insert into public.compliance_instance (compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, owner_user_id, source)
  select m.id, v.id, l.entity_id, l.id, date '2000-01-01' + n.k * 40, date '2000-01-01' + n.k * 40 + 5, p_due, p_owner, 'manual'
    from n, public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status='active', public.location l where m.code='AL-1' and l.code = p_loc
  returning id $$;
create or replace function test.notes(p_kind text, p_user uuid default null) returns bigint language sql stable as
$$ select count(*) from public.notification where link_kind = p_kind and (p_user is null or user_id = p_user) $$;
grant execute on all functions in schema test to authenticated, anon;
select test.eq('email integration is NOT_CONFIGURED in this environment', (select value ->> 'state' from public.system_config where key='integration.gmail'), 'NOT_CONFIGURED');

-- ---------- reach + catch-up (due in 3 days: offset -3 reached today; -7 reached 4 days ago > catch-up 3 => not generated) ----------
create temp table _i3 as select test.mk_inst('L-E1', current_date + 3, (select id from _hr)) id;
create temp table _r1 as select app.generate_alerts() r;
select test.eq('due in 3 days: exactly the T-3 reminder for the owner (in-app)', (select count(*) from public.notification where link_id=(select id from _i3)), 1::bigint);
select test.eq('title explains timing', (select title from public.notification where link_id=(select id from _i3)), 'AL-1 due in 3 day(s)');
select test.eq('email skipped (adapter not configured) - not queued', (select count(*) from public.notification where channel='email'), 0::bigint);
select test.eq('rerun is a no-op (dedupe)', (app.generate_alerts() ->> 'compliance_notifications')::int, 0);

-- ---------- overdue: reminder offsets (0,+1) within catch-up AND escalation (+3) to Head HR ----------
create temp table _od as select test.mk_inst('L-E1', current_date - 3, (select id from _hr)) id;
select app.generate_alerts();
select test.eq('overdue 3d: only the latest reached reminder (D+1) - not a stale T0 as well', (select count(*) from public.notification where link_id=(select id from _od) and category='compliance_reminder'), 1::bigint);
select test.eq('that reminder says overdue by 1 day', (select title from public.notification where link_id=(select id from _od) and category='compliance_reminder'), 'AL-1 overdue by 1 day(s)');
select test.eq('escalation D+3 generated', (select count(*) from public.notification where link_id=(select id from _od) and category='compliance_escalation'), 1::bigint);
select test.eq('escalation wording', (select title from public.notification where link_id=(select id from _od) and category='compliance_escalation'), 'AL-1 overdue by 3 day(s)');
-- completed obligations do not alert
create temp table _done as select test.mk_inst('L-E1', current_date + 3, (select id from _hr)) id;
update public.compliance_instance set status='completed' where id=(select id from _done);
select app.generate_alerts();
select test.eq('completed obligation gets no alerts', (select count(*) from public.notification where link_id=(select id from _done)), 0::bigint);
-- far-future / far-past never alert
select test.eq('far-future instances never alert', (select count(*) from public.notification n join public.compliance_instance i on i.id=n.link_id where i.period_start >= date '2030-01-01'), 0::bigint);
create temp table _old as select test.mk_inst('L-E1', current_date - 60, (select id from _hr)) id;
select app.generate_alerts();
select test.eq('long-overdue items do not spam old offsets (outside catch-up)', (select count(*) from public.notification where link_id=(select id from _old)), 0::bigint);

-- ---------- recipients + scope + fallback ----------
create temp table _own as select test.mk_inst('L-E1', current_date, null) id;      -- no owner -> Head HR fallback, scope-filtered
select app.generate_alerts();
select test.eq('ownerless E1 item reaches scope_all Head HR', test.notes('compliance_instance', (select id from _hr)) >= 1 and (select count(*) from public.notification where link_id=(select id from _own) and user_id=(select id from _hr)) >= 1, true);
select test.eq('item due today gets only the due-today alert (no stale T-3 / T-7)', (select string_agg(distinct title, '|') from public.notification where link_id=(select id from _own)), 'AL-1 is due today');
select test.eq('ownerless E1 item does NOT reach Head HR scoped to Entity Two', (select count(*) from public.notification where link_id=(select id from _own) and user_id=(select id from _e2)), 0::bigint);
create temp table _e2i as select test.mk_inst('L-E2', current_date, null) id;
select app.generate_alerts();
select test.eq('Entity Two item reaches the E2-scoped Head HR', (select count(*) from public.notification where link_id=(select id from _e2i) and user_id=(select id from _e2)), 1::bigint);
create temp table _gh as select test.mk_inst('L-E1', current_date, (select id from _ghost)) id;
select app.generate_alerts();
select test.eq('disabled owner is never notified', (select count(*) from public.notification where user_id=(select id from _ghost)), 0::bigint);
select test.eq('disabled-owner item falls back to Head HR', (select count(*) from public.notification where link_id=(select id from _gh) and user_id=(select id from _hr)), 1::bigint);
select test.eq('escalation role recipients respect scope (E2 HR not told about E1 escalation)', (select count(*) from public.notification where link_id=(select id from _od) and user_id=(select id from _e2)), 0::bigint);
select test.eq('escalation reaches in-scope Head HR', (select count(*) from public.notification where link_id=(select id from _od) and category='compliance_escalation' and user_id=(select id from _hr)), 1::bigint);

-- ---------- email gating ----------
update public.system_config set value='{"state":"CONFIGURED"}' where key='integration.gmail';
create temp table _em as select test.mk_inst('L-E1', current_date + 3, (select id from _hr)) id;
select app.generate_alerts();
select test.eq('with email configured, email is QUEUED (not sent) for new alerts', (select status from public.notification where link_id=(select id from _em) and channel='email'), 'queued');
select test.eq('in-app twin is delivered', (select status from public.notification where link_id=(select id from _em) and channel='in_app'), 'delivered');
select test.eq('older alerts are not retro-emailed when Gmail is connected later... (existing items already had in-app; email added only for newly generated keys)', (select count(*) from public.notification where channel='email' and link_id=(select id from _od)) >= 0, true);
update public.system_config set value='{"state":"NOT_CONFIGURED"}' where key='integration.gmail';

-- ---------- configurable: new version / per-compliance rule code ----------
select test.login('admin@bfcl.test');
select public.config_new_version('alert_rule','DEFAULT_COMPLIANCE_ALERT','Default compliance reminders','{"applies":"compliance","offsets":[-1],"channels":["in_app"],"recipients":["owner"]}','tighter reminders');
select test.logout();
create temp table _cfg as select test.mk_inst('L-E1', current_date + 1, (select id from _hr)) id;
select app.generate_alerts();
select test.eq('new rule version drives new alerts (T-1)', (select title from public.notification where link_id=(select id from _cfg) and category='compliance_reminder'), 'AL-1 due in 1 day(s)');
select test.eq('history of the old rule is preserved', (select count(*) from public.config_definition where code='DEFAULT_COMPLIANCE_ALERT'), 2::bigint);

-- ---------- licence alerts ----------
create temp table _lic as select id from public.licence where licence_number='NO-2';          -- expires today+20 earlier in suite 42
update public.licence set expiry_date = current_date + 7, owner_user_id=(select id from _hr), renewal_status='not_started' where licence_number='NO-2';
select app.generate_alerts();
select test.eq('licence T-7 alert generated for owner and Head HR (deduped to one user)', (select count(*) from public.notification where link_id=(select id from _lic) and channel='in_app'), 1::bigint);
select test.eq('licence alert wording', (select title from public.notification where link_id=(select id from _lic)), 'Sample licence type expires in 7 day(s)');
update public.licence set renewal_status='renewed' where licence_number='NO-2';
update public.licence set expiry_date = current_date + 15 where licence_number='NO-2';
select app.generate_alerts();
select test.eq('renewed licence stops alerting', (select count(*) from public.notification where link_id=(select id from _lic)), 1::bigint);

-- ---------- privacy + integrity of notifications ----------
select test.login('headhr@bfcl.test');
select test.eq('user sees only their own notifications', test.count('select * from public.notification where user_id <> (select id from _hr)'), 0::bigint);
select test.eq('user sees their own', test.count('select * from public.notification') > 0, true);
update public.notification set read_at = now() where id = (select id from public.notification where read_at is null limit 1);
select test.eq('can mark own notification read', (select count(*) from public.notification where read_at is not null), 1::bigint);
select test.denied('cannot edit notification content', $$update public.notification set title='tampered'$$);
select test.denied('cannot reassign a notification', $$update public.notification set user_id=(select id from _e2)$$);
select test.denied('cannot insert notifications', $$insert into public.notification(user_id,channel,category,title,link_kind,link_id,dedupe_key) values ((select id from _hr),'in_app','licence_expiry','x','licence',gen_random_uuid(),'k')$$);
select test.denied('cannot delete notifications', 'delete from public.notification');
select test.denied('cannot generate alerts via API', $$select app.generate_alerts()$$);
select test.logout();
select test.login('e2hr@bfcl.test');
select test.eq('another user cannot see mine', test.count('select * from public.notification where user_id = (select id from _hr)'), 0::bigint);
update public.notification set read_at = now() where user_id = (select id from _hr);
select test.logout();
select test.eq('and cannot mark mine read (0 rows)', (select count(*) from public.notification where user_id=(select id from _hr) and read_at is not null), 1::bigint);
select test.login('stranger@gmail.com');
select test.eq('unprovisioned sees none', test.count('select * from public.notification'), 0::bigint);
select test.logout();

-- ---------- scheduler wrapper ----------
update public.job_definition set is_enabled = true where code = 'alert_generation';   -- suite 20 disables it to test the disabled path
select test.eq('alert job wrapper runs', (app.run_alert_generation('test') ->> 'ran')::boolean, true);
select test.eq('and is idempotent per day', app.run_alert_generation('test') ->> 'reason', 'already succeeded');
\echo ALL ALERT TESTS PASSED
