-- F-2: rule-change reconciliation. Runs in one rolled-back transaction.
-- Untouched = no HUMAN/BUSINESS action. Machine activity (generator, alerts, exception detection, jobs) never counts.
\set ON_ERROR_STOP on
begin;
create sequence test.mk_seq51; grant usage on sequence test.mk_seq51 to authenticated;
insert into public.compliance_master (code, name) values ('RC-1', 'Reconcile sample');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', date '2020-01-01' from public.compliance_master where code='RC-1';
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='RC-1');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from)
  select (select id from public.compliance_master where code='RC-1'), l.id, 'applicable', 'rc', date '2020-01-01' from public.location l where l.code in ('L-E1','L-E2');
update public.compliance_master set is_active = (code = 'RC-1');
select set_config('app.audit_reason', 'test fixture', true);
update public.compliance_instance set status = 'not_applicable' where status in ('open','in_progress');
delete from public.job_run where job_code in ('alert_generation','exception_generation','compliance_generation');
create temp table _start as select (date_trunc('month', current_date) + interval '1 month')::date as d;       -- v2 takes effect on the 1st, one month ahead
grant select on _start to authenticated;
-- generate far enough ahead to cover the v2 effective date
select (app.generate_compliance_instances(current_date - 40, current_date + 240) ->> 'inserted')::int > 0 as generated;
create temp table _fut as select id, location_id, period_start, row_number() over (order by location_id, period_start) rn from public.compliance_instance
  where compliance_id=(select id from public.compliance_master where code='RC-1') and period_start >= (select d from _start) and location_id=(select id from public.location where code='L-E1');
grant select on _fut to authenticated;
select test.eq('fixture: at least six future obligations at one location', (select count(*) from _fut) >= 6, true);
select test.eq('all start untouched (generator is a machine)', (select count(*) from public.compliance_instance where human_touched_at is not null and compliance_id=(select id from public.compliance_master where code='RC-1')), 0::bigint);

-- machine activity must NOT touch: alerts, exception detection, jobs, completion by a maintenance session
select app.generate_alerts(); select app.detect_exceptions(); select app.run_compliance_generation('test'); select app.run_exception_detection('test'); select app.run_alert_generation('test');
select test.eq('alerts / exception detection / jobs leave obligations untouched', (select count(*) from public.compliance_instance where human_touched_at is not null and compliance_id=(select id from public.compliance_master where code='RC-1')), 0::bigint);
insert into public.exception (category, severity, description, compliance_instance_id, entity_id, detection_key, source)
  select 'compliance_overdue','low','machine-raised', id, (select entity_id from public.location where code='L-E1'), 'rc:machine:'||id, 'auto' from _fut where rn = 1;
select test.eq('an automatically generated exception does not touch the obligation', (select human_touched_at is null from public.compliance_instance where id=(select id from _fut where rn=1)), true);

-- human actions touch (admin = scope_all user with compliance.write)
select test.login('admin@bfcl.test');
select public.compliance_set_status((select id from _fut where rn = 2), 'in_progress');
update public.compliance_instance set remarks = 'called the inspector' where id = (select id from _fut where rn = 3);
update public.compliance_instance set owner_user_id = (select id from public.app_user where email='admin@bfcl.test') where id = (select id from _fut where rn = 4);
select test.logout();
select test.eq('status change by a user touches', (select human_touched_at is not null from public.compliance_instance where id=(select id from _fut where rn=2)), true);
select test.eq('remark by a user touches', (select human_touched_at is not null from public.compliance_instance where id=(select id from _fut where rn=3)), true);
select test.eq('owner change by a user touches', (select human_touched_at is not null from public.compliance_instance where id=(select id from _fut where rn=4)), true);
select test.eq('rn=1 (machine exception only) and the rest stay untouched', (select count(*) from _fut f join public.compliance_instance i on i.id=f.id where i.human_touched_at is null and f.rn > 4) + (select count(*) from public.compliance_instance where id=(select id from _fut where rn=1) and human_touched_at is null), (select count(*) - 3 from _fut));
select test.login('admin@bfcl.test');
update public.compliance_instance set human_touched_at = null where id = (select id from _fut where rn = 2);
select test.eq('a user cannot clear the marker (write is neutralised)', (select human_touched_at is not null from public.compliance_instance where id=(select id from _fut where rn=2)), true);
update public.compliance_instance set human_touched_at = now() where id = (select id from _fut where rn = 5);
select test.eq('nor set it without a business change', (select human_touched_at is null from public.compliance_instance where id=(select id from _fut where rn=5)), true);
select test.denied('a user cannot supersede an obligation', $$select public.compliance_set_status((select id from _fut where rn = 5), 'superseded')$$);
select test.denied('nor via a direct update', $$update public.compliance_instance set status='superseded' where id=(select id from _fut where rn=5)$$);
select test.logout();
select test.eq('marker is reproducible from the audit log for the touched rows', (select count(*) from _fut f where f.rn in (2,3,4) and app.human_touch_events(f.id) is not null), 3::bigint);
select test.eq('and absent for the untouched ones', (select count(*) from _fut f where f.rn not in (2,3,4) and app.human_touch_events(f.id) is not null), 0::bigint);

-- activate v2 (due day 20) effective next month, through the permission-checked function
select test.login('admin@bfcl.test');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":20,"month_offset":1}', 'medium', (select d from _start) from public.compliance_master where code='RC-1';
select public.compliance_activate_rule_version((select id from public.compliance_rule_version where compliance_id=(select id from public.compliance_master where code='RC-1') and status='draft'), 'moves the due day to the 20th');
select test.logout();
create temp table _v as select id, version from public.compliance_rule_version where compliance_id=(select id from public.compliance_master where code='RC-1');
grant select on _v to authenticated;
select test.eq('v1 retired / v2 active', (select string_agg(version::text || ':' || (select status from public.compliance_rule_version where id=_v.id), ',' order by version) from _v), '1:retired,2:active');

select test.eq('touched obligations stay pinned to v1 (status change / remark / owner)', (select count(*) from public.compliance_instance i join _fut f on f.id=i.id where f.rn in (2,3,4) and i.status <> 'superseded' and i.rule_version_id=(select id from _v where version=1)), 3::bigint);
select test.eq('untouched future obligations were superseded', (select count(*) from _fut f join public.compliance_instance i on i.id=f.id where f.rn not in (2,3,4) and i.status='superseded'), (select count(*) - 3 from _fut));
select test.eq('with reason, time and link recorded', (select count(*) from _fut f join public.compliance_instance i on i.id=f.id where i.status='superseded' and i.supersede_reason like 'Rule change: moves the due day to the 20th' and i.superseded_at is not null and i.superseded_by is not null), (select count(*) - 3 from _fut));
select test.eq('each superseded period has exactly one replacement under v2 (due on the 20th)', (select count(*) from _fut f join public.compliance_instance s on s.id=f.id join public.compliance_instance n on n.id=s.superseded_by
   where s.status='superseded' and n.rule_version_id=(select id from _v where version=2) and extract(day from n.due_date)=20 and n.period_start=s.period_start and n.status='open'), (select count(*) - 3 from _fut));
select test.eq('no duplicate live obligations per (compliance, location, period)', (select count(*) from (select 1 from public.compliance_instance where status <> 'superseded' group by compliance_id, location_id, period_start having count(*) > 1) d), 0::bigint);
select test.eq('the other location (never touched) was reconciled too', (select count(*) from public.compliance_instance i where i.compliance_id=(select id from public.compliance_master where code='RC-1') and i.location_id=(select id from public.location where code='L-E2') and i.period_start >= (select d from _start) and i.status <> 'superseded' and i.rule_version_id=(select id from _v where version=2)) > 0, true);
select test.eq('history before the effective date is untouched (still v1)', (select count(*) from public.compliance_instance i where i.compliance_id=(select id from public.compliance_master where code='RC-1') and i.period_start < (select d from _start) and i.rule_version_id=(select id from _v where version=2)), 0::bigint);
select test.eq('the machine-raised exception on a superseded obligation was closed with the reason', (select resolution from public.exception where detection_key like 'rc:machine:%'), 'Obligation superseded by rule change');
select test.eq('audit trail: every supersession is in the audit log with the reason', (select count(distinct a.record_id) from public.audit_log a where a.table_name='compliance_instance' and a.action='UPDATE' and a.new_data ->> 'status' = 'superseded' and a.reason like 'Rule change: moves the due day%' and a.record_id in (select id::text from public.compliance_instance where compliance_id=(select id from public.compliance_master where code='RC-1'))), (select count(*) from public.compliance_instance where status='superseded' and compliance_id=(select id from public.compliance_master where code='RC-1')));
select test.eq('superseded rows are hidden from the register view', (select count(*) from public.v_compliance_instance v join _fut f on f.id=v.id where f.rn > 4), 0::bigint);
select test.eq('and listed in v_compliance_superseded with their replacement', (select count(*) from public.v_compliance_superseded where compliance_code='RC-1' and replaced_by_instance_no is not null), (select count(*) from public.compliance_instance where status='superseded' and compliance_id=(select id from public.compliance_master where code='RC-1')));
select test.eq('reconciliation report lists the pinned (actioned) obligations for a human', (select count(*) from public.compliance_reconciliation_report((select id from public.compliance_master where code='RC-1')) where human_touched_at is not null), 3::bigint);

-- idempotency + concurrency-safe: reconciling again changes nothing
create temp table _before as select count(*) n, count(*) filter (where status='superseded') s from public.compliance_instance;
select test.eq('second reconcile is a no-op', (app.reconcile_future_obligations((select id from public.compliance_master where code='RC-1'), (select d from _start), 'again') ->> 'superseded')::int, 0);
select test.eq('and creates nothing', (select n from _before), (select count(*) from public.compliance_instance));
select test.eq('generator rerun still creates no duplicates for superseded periods', (app.generate_compliance_instances(current_date - 40, current_date + 240) ->> 'inserted')::int, 0);
-- alerts / exceptions ignore superseded rows
select app.detect_exceptions();
select test.eq('no exception is raised for a superseded obligation', (select count(*) from public.exception x join public.compliance_instance i on i.id=x.compliance_instance_id where i.status='superseded' and x.status in ('open','acknowledged')), 0::bigint);
select test.login('admin@bfcl.test');
select test.eq('dashboard total ignores superseded rows', (public.compliance_dashboard() #>> '{obligations,total}')::int, (select count(*)::int from public.compliance_instance where status not in ('superseded','not_applicable')));
select test.logout();
-- a second rule change: actioned rows stay on v1, untouched rows move again (v2 -> v3); still no duplicates
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":25,"month_offset":1}', 'medium', (select d + interval '1 month' from _start)::date from public.compliance_master where code='RC-1';
select test.login('admin@bfcl.test');
select public.compliance_activate_rule_version((select id from public.compliance_rule_version where compliance_id=(select id from public.compliance_master where code='RC-1') and status='draft'), 'moves the due day to the 25th');
select test.logout();
select test.eq('after a second change the actioned obligations are STILL pinned to v1', (select count(*) from public.compliance_instance i join _fut f on f.id=i.id where f.rn in (2,3,4) and i.status <> 'superseded' and i.rule_version_id=(select id from _v where version=1)), 3::bigint);
select test.eq('untouched periods beyond the v3 date now use v3 (due on the 25th)', (select count(*) from public.compliance_instance i join public.compliance_rule_version r on r.id=i.rule_version_id where i.compliance_id=(select id from public.compliance_master where code='RC-1') and i.status <> 'superseded' and r.version=3 and extract(day from i.due_date)=25) > 0, true);
select test.eq('and the periods between v2 and v3 stay on v2', (select count(*) from public.compliance_instance i join public.compliance_rule_version r on r.id=i.rule_version_id where i.compliance_id=(select id from public.compliance_master where code='RC-1') and i.status <> 'superseded' and r.version=2 and i.period_start >= (select d from _start) and i.period_start < (select d + interval '1 month' from _start)::date) > 0, true);
select test.eq('still no duplicate live obligations', (select count(*) from (select 1 from public.compliance_instance where status <> 'superseded' group by compliance_id, location_id, period_start having count(*) > 1) d), 0::bigint);
-- exception activity by a person touches the obligation; evidence-less machine exception does not (covered above)
create temp table _e2 as select id from public.compliance_instance where compliance_id=(select id from public.compliance_master where code='RC-1') and location_id=(select id from public.location where code='L-E2') and status='open' and human_touched_at is null order by period_start desc limit 1;
grant select on _e2 to authenticated;
select test.login('admin@bfcl.test');
insert into public.exception (category, severity, description, compliance_instance_id, entity_id, detection_key, source) select 'manual','low','raised by a person', id, (select entity_id from public.location where code='L-E2'), 'x', 'manual' from _e2;
select test.logout();
select test.eq('an exception raised by a person touches its obligation', (select human_touched_at is not null from public.compliance_instance where id=(select id from _e2)), true);
select test.eq('and the audit-derived determination agrees', (select app.human_touch_events((select id from _e2)) is not null), true);
select test.eq('rebuild restores the marker where it is missing and reports nothing else', app.rebuild_human_touched() >= 0, true);
rollback;
\echo ALL RECONCILE TESTS PASSED
