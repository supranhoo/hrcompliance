-- Periods, due dates, idempotent generation, rule-version history, status model, scope. Reuses fixtures from earlier suites.
\set ON_ERROR_STOP on
-- ---------- period math ----------
select test.eq('monthly Jan-Mar 2026 = 3 periods', (select count(*) from app.compliance_periods('monthly', 1, date '2026-01-01', date '2026-03-31')), 3::bigint);
select test.eq('monthly window mid-month includes the overlapping month', (select min(period_start) from app.compliance_periods('monthly', 1, date '2026-02-15', date '2026-02-16')), date '2026-02-01');
select test.eq('monthly period end', (select period_end from app.compliance_periods('monthly', 1, date '2026-02-10', date '2026-02-10')), date '2026-02-28');
select test.eq('leap February end', (select period_end from app.compliance_periods('monthly', 1, date '2028-02-10', date '2028-02-10')), date '2028-02-29');
select test.eq('quarterly calendar (Jan start) Q2', (select period_start || '..' || period_end from app.compliance_periods('quarterly', 1, date '2026-05-10', date '2026-05-10')), '2026-04-01..2026-06-30');
select test.eq('quarterly FY (Apr start) quarter containing Feb 2026 = Jan-Mar', (select period_start || '..' || period_end from app.compliance_periods('quarterly', 4, date '2026-02-10', date '2026-02-10')), '2026-01-01..2026-03-31');
select test.eq('quarterly FY (Apr start) quarter containing May 2026 = Apr-Jun', (select period_start || '..' || period_end from app.compliance_periods('quarterly', 4, date '2026-05-10', date '2026-05-10')), '2026-04-01..2026-06-30');
select test.eq('half-yearly FY (Apr) containing Nov 2026 = Oct-Mar', (select period_start || '..' || period_end from app.compliance_periods('half_yearly', 4, date '2026-11-10', date '2026-11-10')), '2026-10-01..2027-03-31');
select test.eq('annual FY (Apr) containing Feb 2026 = Apr 2025-Mar 2026', (select period_start || '..' || period_end from app.compliance_periods('annual', 4, date '2026-02-10', date '2026-02-10')), '2025-04-01..2026-03-31');
select test.eq('annual calendar year', (select period_start || '..' || period_end from app.compliance_periods('annual', 1, date '2026-06-10', date '2026-06-10')), '2026-01-01..2026-12-31');
select test.eq('weekly periods are Monday-Sunday', (select period_start || '..' || period_end from app.compliance_periods('weekly', 1, date '2026-10-07', date '2026-10-07')), '2026-10-05..2026-10-11');
select test.eq('daily periods', (select count(*) from app.compliance_periods('daily', 1, date '2026-10-01', date '2026-10-10')), 10::bigint);
select test.eq('event_based is never auto-generated', (select count(*) from app.compliance_periods('event_based', 1, date '2026-01-01', date '2026-12-31')), 0::bigint);
select test.eq('empty/inverted window -> nothing', (select count(*) from app.compliance_periods('monthly', 1, date '2026-03-01', date '2026-01-01')), 0::bigint);

-- ---------- derived due state ----------
select test.eq('overdue', app.due_state('open', date '2026-10-01', date '2026-10-03', 7), 'overdue');
select test.eq('due today = due soon (not overdue)', app.due_state('open', date '2026-10-03', date '2026-10-03', 7), 'due_soon');
select test.eq('due in 7 days = due soon (boundary)', app.due_state('in_progress', date '2026-10-10', date '2026-10-03', 7), 'due_soon');
select test.eq('due in 8 days = upcoming', app.due_state('open', date '2026-10-11', date '2026-10-03', 7), 'upcoming');
select test.eq('completed stays completed even if late', app.due_state('completed', date '2020-01-01', date '2026-10-03', 7), 'completed');
select test.eq('not_applicable', app.due_state('not_applicable', date '2020-01-01', date '2026-10-03', 7), 'not_applicable');

-- ---------- fixtures (superuser): one monthly compliance, v1 (due 20th next month) then v2 from July (due 25th) ----------
insert into public.compliance_master (code, name) values ('GEN-1', 'Generator sample monthly');
create temp table _g as select id from public.compliance_master where code='GEN-1';
grant select on _g to authenticated;
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, criticality, effective_from)
 select id, 'statutory', 'monthly', '{"type":"day_of_month","day":20,"month_offset":1}', 'high', 'critical', date '2026-01-01' from _g;
update public.compliance_rule_version set status='active' where compliance_id=(select id from _g) and version=1;
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, criticality, effective_from)
 select id, 'statutory', 'monthly', '{"type":"day_of_month","day":25,"month_offset":1}', 'high', 'critical', date '2026-07-01' from _g;
update public.compliance_rule_version set status='retired', effective_to = date '2026-06-30' where compliance_id=(select id from _g) and version=1;
update public.compliance_rule_version set status='active' where compliance_id=(select id from _g) and version=2;
-- applicability: Entity One applicable; L-E1B explicitly not applicable; E2 unmapped
insert into public.compliance_applicability (compliance_id, entity_id, status, reason, effective_from) select (select id from _g), id, 'applicable', 'E1 sites', date '2025-01-01' from public.entity where code='E1';
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) select (select id from _g), id, 'not_applicable', 'office, no workmen', date '2025-01-01' from public.location where code='L-E1B';
-- earlier suites left other compliances ("CM-1","AP-*","CM-2") without active rule versions except CM-1 (v2 active, monthly): neutralise them for exact counts
update public.compliance_master set is_active = false where code <> 'GEN-1';
grant execute on all functions in schema test to authenticated, anon;

-- ---------- generation ----------
select test.eq('first run: 1 applicable location x 6 months = 6', (app.generate_compliance_instances(date '2026-01-01', date '2026-06-30') ->> 'inserted')::int, 6);
select test.eq('rerun is idempotent (0 inserted)', (app.generate_compliance_instances(date '2026-01-01', date '2026-06-30') ->> 'inserted')::int, 0);
select test.eq('rerun reports them as already existing', (app.generate_compliance_instances(date '2026-01-01', date '2026-06-30') ->> 'already_existing')::int, 6);
select test.eq('overlapping window only adds the new months', (app.generate_compliance_instances(date '2026-05-01', date '2026-09-30') ->> 'inserted')::int, 3);
select test.eq('total instances = 9 (6+3)', (select count(*) from public.compliance_instance), 9::bigint);
select test.eq('only the applicable location has instances', (select string_agg(distinct l.code, ',') from public.compliance_instance i join public.location l on l.id=i.location_id), 'L-E1');
select test.eq('no instances for not_applicable / unmapped locations', (select count(*) from public.compliance_instance i join public.location l on l.id=i.location_id where l.code in ('L-E1B','L-E2')), 0::bigint);
select test.eq('instance numbers are unique & sequential', (select count(distinct instance_no) from public.compliance_instance), 9::bigint);
select test.eq('instance number format', (select instance_no ~ '^CMP-[0-9]{4}-[0-9]{6}$' from public.compliance_instance limit 1), true);
select test.eq('due date under v1 (Jan period -> 20 Feb)', (select due_date from public.compliance_instance where period_start = date '2026-01-01'), date '2026-02-20');
select test.eq('due date under v1 (Jun period -> 20 Jul): rule in force at period start', (select due_date from public.compliance_instance where period_start = date '2026-06-01'), date '2026-07-20');
select test.eq('due date under v2 (Jul period -> 25 Aug)', (select due_date from public.compliance_instance where period_start = date '2026-07-01'), date '2026-08-25');
select test.eq('instances keep the rule version that created them', (select count(distinct rule_version_id) from public.compliance_instance), 2::bigint);
select test.eq('historical instances not rewritten by later rule change', (select v.version from public.compliance_instance i join public.compliance_rule_version v on v.id=i.rule_version_id where i.period_start = date '2026-01-01'), 1);
-- applicability change: a newly applicable site gets instances going forward, existing ones untouched
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) select (select id from _g), id, 'applicable', 'now has workmen', date '2026-08-01' from public.location where code='L-E1B';
select test.eq('new applicability generates from its effective date only', (app.generate_compliance_instances(date '2026-06-01', date '2026-09-30') ->> 'inserted')::int, 2);
select test.eq('L-E1B instances start Aug', (select min(period_start) from public.compliance_instance i join public.location l on l.id=i.location_id where l.code='L-E1B'), date '2026-08-01');
-- inactive master generates nothing
update public.compliance_master set is_active=false where code='GEN-1';
select test.eq('inactive master generates nothing', (app.generate_compliance_instances(date '2027-01-01', date '2027-03-31') ->> 'inserted')::int, 0);
update public.compliance_master set is_active=true where code='GEN-1';

-- ---------- scheduler wrapper ----------
select test.eq('job run executes once', (app.run_compliance_generation('test') ->> 'ran')::boolean, true);
select test.eq('job logged as succeeded', (select status from public.job_run where job_code='compliance_generation' and idempotency_key = to_char(current_date,'YYYY-MM-DD')), 'succeeded');
select test.eq('second run same day is refused (idempotent job)', app.run_compliance_generation('test') ->> 'reason', 'already succeeded');
select test.denied('API role cannot run the generator', $$set role authenticated; select app.generate_compliance_instances(current_date, current_date)$$);
reset role;
select test.denied('API role cannot run the job wrapper', $$set role authenticated; select app.run_compliance_generation()$$);
reset role;

-- ---------- status model (configuration-driven) ----------
create temp table _i as select id from public.compliance_instance where period_start = date '2026-01-01';
grant select on _i to authenticated;
select test.login('headhr@bfcl.test');
update public.compliance_instance set status='in_progress' where id=(select id from _i);
update public.compliance_instance set status='completed' where id=(select id from _i);
select test.eq('completion stamps date and user', (select (completed_on = current_date)::text || ':' || (completed_by is not null)::text from public.compliance_instance where id=(select id from _i)), 'true:true');
select test.denied('reopening a completed obligation requires a reason', $$update public.compliance_instance set status='open' where id=(select id from _i)$$);
begin;
 select set_config('app.audit_reason', 'completed against wrong period; correcting', true);
 update public.compliance_instance set status='open' where id=(select id from _i);
commit;
select test.eq('reopen with reason works and clears completion', (select status || ':' || coalesce(completed_on::text,'null') from public.compliance_instance where id=(select id from _i)), 'open:null');
select test.eq('reopen reason recorded in audit', (select reason from public.audit_log where table_name='compliance_instance' and action='UPDATE' and changed_fields @> array['status'] order by id desc limit 1), 'completed against wrong period; correcting');
select test.denied('not_applicable needs a reason', $$update public.compliance_instance set status='not_applicable' where id=(select id from _i)$$);
select test.denied('unknown status refused', $$update public.compliance_instance set status='archived' where id=(select id from _i)$$);
select test.denied('transition not configured is refused (completed -> not_applicable)', $$update public.compliance_instance set status='completed' where id=(select id from _i); update public.compliance_instance set status='not_applicable' where id=(select id from _i)$$);
select test.denied('due date is immutable', $$update public.compliance_instance set due_date = date '2030-01-01' where id=(select id from _i)$$);
select test.denied('period is immutable', $$update public.compliance_instance set period_start = date '2030-01-01' where id=(select id from _i)$$);
select test.denied('instance number is immutable', $$update public.compliance_instance set instance_no = 'CMP-2026-999999' where id=(select id from _i)$$);
select test.denied('direct insert is not allowed (generator only)', $$insert into public.compliance_instance(instance_no,compliance_id,rule_version_id,entity_id,location_id,period_start,period_end,due_date) select 'X',compliance_id,rule_version_id,entity_id,location_id,date '2031-01-01',date '2031-01-31',date '2031-02-20' from public.compliance_instance limit 1$$);
select test.denied('direct delete is not allowed', 'delete from public.compliance_instance');
update public.compliance_instance set owner_user_id=(select id from public.app_user where email='headhr@bfcl.test'), remarks='working on it' where id=(select id from _i);
select test.eq('owner/remarks are editable', (select remarks from public.compliance_instance where id=(select id from _i)), 'working on it');
select test.logout();

-- ---------- view, calendar, scope ----------
select test.login('headhr@bfcl.test');
select test.eq('view derives due_state for past-due open items', (select due_state from public.v_compliance_instance where period_start = date '2026-01-01'), 'overdue');
select test.eq('view exposes days_overdue', (select days_overdue > 0 from public.v_compliance_instance where period_start = date '2026-01-01'), true);
select test.eq('calendar returns items in the window', (select count(*) from public.compliance_calendar(date '2026-02-01', date '2026-02-28')), 1::bigint);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('viewer without scope sees no instances (fail closed)', test.count('select * from public.compliance_instance'), 0::bigint);
select test.eq('viewer sees nothing in the calendar', test.count($$select * from public.compliance_calendar(date '2026-01-01', date '2026-12-31')$$), 0::bigint);
update public.compliance_instance set remarks='x' where true;   -- no permission and no scope: RLS filters every row
-- (verified below as owner that no row changed)
select test.logout();
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_HR' on conflict do nothing;
select test.login('plant@bfcl.test');
select test.eq('Entity-One-scoped user sees instances of E1', test.count('select * from public.compliance_instance') > 0, true);
select test.logout();
select test.eq('viewer update changed nothing', (select count(*) from public.compliance_instance where remarks='x'), 0::bigint);
select test.login('stranger@gmail.com');
select test.eq('unprovisioned sees no instances', test.count('select * from public.compliance_instance'), 0::bigint);
select test.denied('unprovisioned cannot call manual instance RPC', $$select public.compliance_create_manual_instance((select id from _g), (select id from public.location limit 1), current_date)$$);
select test.logout();

-- ---------- manual (event-based) instances ----------
insert into public.compliance_master (code, name) values ('EVT-1', 'Event based sample');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from) select id, 'event_based', 'event_based', '{"type":"days_after_event","days":30}', 'medium', date '2026-01-01' from public.compliance_master where code='EVT-1';
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='EVT-1');
insert into public.compliance_applicability (compliance_id, entity_id, status, reason, effective_from) select (select id from public.compliance_master where code='EVT-1'), id, 'applicable', 'all E1', date '2025-01-01' from public.entity where code='E1';
create temp table _e as select id from public.compliance_master where code='EVT-1';
grant select on _e to authenticated;
select test.login('headhr@bfcl.test');
select public.compliance_create_manual_instance((select id from _e), (select id from public.location where code='L-E1'), date '2026-09-10', 'accident reported');
select test.eq('manual instance due = event + 30', (select due_date from public.compliance_instance where compliance_id=(select id from _e)), date '2026-10-10');
select public.compliance_create_manual_instance((select id from _e), (select id from public.location where code='L-E1'), date '2026-09-10', 'duplicate click');
select test.eq('manual creation is idempotent per event date', (select count(*) from public.compliance_instance where compliance_id=(select id from _e)), 1::bigint);
select test.denied('periodic compliance cannot be created manually', $$select public.compliance_create_manual_instance((select id from _g), (select id from public.location where code='L-E1'), date '2026-10-10')$$);
select test.denied('not-applicable location refused', $$select public.compliance_create_manual_instance((select id from _e), (select id from public.location where code='L-E2'), date '2026-09-10')$$);
select test.logout();
select test.eq('generator ignores event-based rules', (app.generate_compliance_instances(date '2026-01-01', date '2026-12-31') ->> 'inserted')::int >= 0, true);
select test.eq('still exactly one event instance', (select count(*) from public.compliance_instance where compliance_id=(select id from _e)), 1::bigint);
\echo ALL GENERATOR TESTS PASSED
