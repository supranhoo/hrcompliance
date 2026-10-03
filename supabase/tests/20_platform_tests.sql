-- Platform tests: status designer, system_config, versioned config definitions, job framework, system health.
-- Runs after 10_rls_and_rules.sql (reuses its helpers and fixtures: admin/headhr/viewer/stranger).
\set ON_ERROR_STOP on

-- ---------- status designer ----------
select test.login('admin@bfcl.test');
insert into public.status_definition (module, code, label, category, is_initial) values ('grievance','reported','Reported','open',true);
insert into public.status_definition (module, code, label, category) values ('grievance','registered','Registered','open'), ('grievance','closed','Closed','closed');
insert into public.status_transition (module, from_status, to_status) values ('grievance','reported','registered'), ('grievance','registered','closed');
select test.denied('second initial status rejected', $$insert into public.status_definition(module,code,label,category,is_initial) values ('grievance','x','X','open',true)$$);
select test.denied('terminal status must be closed/cancelled', $$insert into public.status_definition(module,code,label,category,is_terminal) values ('grievance','y','Y','open',true)$$);
select test.denied('transition to unknown status rejected (FK)', $$insert into public.status_transition(module,from_status,to_status) values ('grievance','reported','nope')$$);
select test.denied('self transition rejected', $$insert into public.status_transition(module,from_status,to_status) values ('grievance','reported','reported')$$);
select test.denied('status for unknown module rejected', $$insert into public.status_definition(module,code,label,category) values ('nomodule','a','A','open')$$);
select test.eq('configured transition allowed', app.status_transition_allowed('grievance','reported','registered'), true);
select test.eq('unconfigured transition refused', app.status_transition_allowed('grievance','reported','closed'), false);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('viewer can read status definitions', test.count('select * from public.status_definition') >= 3, true);
select test.denied('viewer cannot write status definitions', $$insert into public.status_definition(module,code,label,category) values ('grievance','z','Z','open')$$);
select test.denied('viewer has no DELETE on status_definition', 'delete from public.status_definition');
select test.logout();
select test.login('stranger@gmail.com');
select test.eq('stranger sees no status definitions', test.count('select * from public.status_definition'), 0::bigint);
select test.logout();

-- ---------- system_config ----------
select test.login('admin@bfcl.test');
select test.denied('secret-like config key rejected', $$insert into public.system_config(key,value) values ('drive.client_secret','"x"')$$);
select test.denied('api key-like config key rejected', $$insert into public.system_config(key,value) values ('gmail.api_key','"x"')$$);
insert into public.system_config(key,value) values ('ui.page_size','25');
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('viewer cannot read system_config', test.count('select * from public.system_config'), 0::bigint);
select test.denied('viewer cannot write system_config', $$insert into public.system_config(key,value) values ('a.b','1')$$);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('head hr (config.read) reads system_config', test.count('select * from public.system_config') >= 3, true);
select test.logout();

-- ---------- versioned config definitions ----------
select test.login('viewer@bfcl.test');
select test.denied('viewer cannot publish config version', $$select public.config_new_version('sla_rule','GRC_DEFAULT','GRC SLA','{"days":7}','r')$$);
select test.denied('viewer cannot insert config_definition', $$insert into public.config_definition(kind,code,name,definition) values ('sla_rule','X','x','{}')$$);
select test.logout();
select test.login('admin@bfcl.test');
select public.config_new_version('sla_rule','GRC_DEFAULT','GRC SLA','{"days":7,"calendar":"working"}','initial');
select test.eq('v1 active', (select status from public.config_definition where code='GRC_DEFAULT' and version=1), 'active');
select public.config_new_version('sla_rule','GRC_DEFAULT','GRC SLA','{"days":10,"calendar":"working"}','policy change');
select test.eq('v1 retired after v2', (select status from public.config_definition where code='GRC_DEFAULT' and version=1), 'retired');
select test.eq('v2 active', (select status from public.config_definition where code='GRC_DEFAULT' and version=2), 'active');
select test.eq('v1 content preserved', (select definition ->> 'days' from public.config_definition where code='GRC_DEFAULT' and version=1), '7');
select test.denied('active version definition is immutable', $$update public.config_definition set definition='{"days":1}' where code='GRC_DEFAULT' and version=2$$);
select test.denied('retired version cannot be reactivated', $$update public.config_definition set status='active' where code='GRC_DEFAULT' and version=1$$);
select test.denied('change reason required', $$select public.config_new_version('sla_rule','GRC_DEFAULT','GRC SLA','{"days":3}','  ')$$);
select test.denied('invalid kind rejected', $$select public.config_new_version('shell_script','X','x','{}','r')$$);
select test.denied('non-object definition rejected', $$select public.config_new_version('sla_rule','BAD','bad','[1]','r')$$);
select test.denied('invalid "when" rule rejected', $$select public.config_new_version('alert_rule','A1','a','{"when":{"op":"exec","field":"a","value":1}}','r')$$);
select public.config_new_version('alert_rule','A2','a','{"when":{"op":"eq","field":"status","value":"open"},"offsets":[-30,-7,0]}','r');
select test.denied('no hard delete of config versions', 'delete from public.config_definition');
select test.logout();
select test.eq('version history audited', (select count(*) from public.audit_log where table_name='config_definition' and action='INSERT'), 3::bigint);

-- ---------- jobs ----------
select test.eq('job definitions seeded', (select count(*) from public.job_definition), 7::bigint);
select test.eq('job start #1 runs', (select should_run from app.job_start('housekeeping','2026-W40','development')), true);
select test.eq('job start #2 refused (running)', (select reason from app.job_start('housekeeping','2026-W40')), 'already running');
select app.job_finish((select id from public.job_run where idempotency_key='2026-W40'), true, 12);
select test.eq('success recorded', (select status from public.job_run where idempotency_key='2026-W40'), 'succeeded');
select test.eq('re-run after success refused', (select reason from app.job_start('housekeeping','2026-W40')), 'already succeeded');
select test.eq('different key runs', (select should_run from app.job_start('housekeeping','2026-W41')), true);
-- failure -> retry window -> retry -> exhaust
select app.job_finish((select id from public.job_run where idempotency_key='2026-W41'), false, 3, '{"message":"boom"}');
select test.eq('failure schedules retry', (select status from public.job_run where idempotency_key='2026-W41'), 'retry_wait');
select test.eq('retry blocked inside backoff window', (select reason from app.job_start('housekeeping','2026-W41')), 'waiting for retry window');
update public.job_run set next_retry_at = now() - interval '1 second' where idempotency_key='2026-W41';
select test.eq('retry allowed after window', (select reason from app.job_start('housekeeping','2026-W41')), 'retry');
select test.eq('attempt incremented', (select attempt from public.job_run where idempotency_key='2026-W41'), 2);
select app.job_finish((select id from public.job_run where idempotency_key='2026-W41'), false, null, '{"message":"boom2"}');
update public.job_run set next_retry_at = now() - interval '1 second' where idempotency_key='2026-W41';
select app.job_start('housekeeping','2026-W41');
select app.job_finish((select id from public.job_run where idempotency_key='2026-W41'), false, null, '{"message":"boom3"}');
select test.eq('exhausted attempts end as failed', (select status from public.job_run where idempotency_key='2026-W41'), 'failed');
select test.eq('failed job not retried beyond max', (select reason from app.job_start('housekeeping','2026-W41')), 'max attempts reached');
-- crashed runner: stale 'running' is reclaimed
select app.job_start('housekeeping','2026-W42');
update public.job_run set started_at = now() - interval '2 hours' where idempotency_key='2026-W42';
select test.eq('stale running run reclaimed', (select should_run from app.job_start('housekeeping','2026-W42')), true);
-- disabled job
update public.job_definition set is_enabled = false where code = 'alert_generation';
select test.eq('disabled job does not run', (select should_run from app.job_start('alert_generation','k1')), false);
select test.denied('unknown job rejected', $$select * from app.job_start('nope','k')$$);
select test.login('viewer@bfcl.test');
select test.denied('API role cannot call job_start', $$select * from app.job_start('housekeeping','hack')$$);
select test.eq('viewer cannot read job runs', test.count('select * from public.job_run'), 0::bigint);
select test.denied('viewer cannot write job_run', $$insert into public.job_run(job_code,idempotency_key) values ('housekeeping','x')$$);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('head hr reads job runs', test.count('select * from public.job_run') >= 3, true);
update public.job_definition set is_enabled=false where code='housekeeping';   -- RLS filters the row: 0 rows updated, no error
select test.eq('head hr cannot edit job definition (value unchanged)', (select is_enabled from public.job_definition where code='housekeeping'), true);
select test.logout();

-- ---------- system health ----------
select test.login('viewer@bfcl.test');
select test.denied('viewer cannot call system_health', 'select public.system_health()');
select test.logout();
select test.login('stranger@gmail.com');
select test.denied('stranger cannot call system_health', 'select public.system_health()');
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('health: db connected', (public.system_health() -> 'database' ->> 'connected'), 'true');
select test.eq('health: drive NOT_CONFIGURED', (public.system_health() -> 'integrations' ->> 'google_drive'), 'NOT_CONFIGURED');
select test.eq('health: gmail NOT_CONFIGURED', (public.system_health() -> 'integrations' ->> 'gmail'), 'NOT_CONFIGURED');
select test.eq('health: reports failed job', (public.system_health() -> 'latest_failed_job' ->> 'job_code'), 'housekeeping');
select test.eq('health exposes no secrets', public.system_health()::text ~* '(secret|password|token|key)', false);
select test.logout();
\echo ALL PLATFORM TESTS PASSED
