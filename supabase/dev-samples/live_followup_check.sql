-- LIVE FOLLOW-UP CHECK for migrations 0023 (D-001), 0024 (F-1), 0025 (F-2). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Run supabase/tests/live_gate.sql as well (expects 25 migrations).
with c(n, check_name, ok) as (values
 (1,  '0023: notification category allows alert_unroutable',   (select pg_get_constraintdef(oid) like '%alert_unroutable%' from pg_constraint where conname = 'notification_category_check')),
 (2,  '0023: exception category alert_unroutable exists',      exists (select 1 from public.lov_value v join public.lov_set s on s.id = v.set_id where s.code = 'EXCEPTION_CATEGORY' and v.code = 'alert_unroutable')),
 (3,  '0023: routing validation + unroutable recipients exist', to_regprocedure('public.alert_routing_validation()') is not null and to_regprocedure('app.unroutable_recipients(uuid,uuid)') is not null),
 (4,  '0023: system_health() reports unroutable alerts',        pg_get_functiondef('public.system_health()'::regprocedure) like '%unroutable_alerts%'),
 (5,  '0024: applicability SELECT policy is scope-controlled',  (select qual like '%scope_ok%' from pg_policies where tablename = 'compliance_applicability' and policyname = 'appl_sel')),
 (6,  '0024: Location Master read policy is NOT scoped (global)', (select qual not like '%scope%' and qual not like '%in_scope%' from pg_policies where tablename = 'location' and policyname = 'location_sel')),
 (7,  '0024: coverage report is scope-controlled',              pg_get_functiondef('public.compliance_coverage(date)'::regprocedure) like '%scope_ok%'),
 (8,  '0025: human_touched_at + supersession columns exist',    (select count(*) = 4 from information_schema.columns where table_schema = 'public' and table_name = 'compliance_instance' and column_name in ('human_touched_at','superseded_by','superseded_at','supersede_reason'))),
 (9,  '0025: idempotency key is a partial unique index',        (select indexdef like '%WHERE%superseded%' from pg_indexes where indexname = 'compliance_instance_idem_uk')),
 (10, '0025: status superseded defined',                        exists (select 1 from public.status_definition where module = 'compliance' and code = 'superseded')),
 (11, '0025: reconcile + report functions exist',               to_regprocedure('app.reconcile_future_obligations(uuid,date,text)') is not null and to_regprocedure('public.compliance_reconciliation_report(uuid)') is not null),
 (12, '0025: activation calls the reconciliation',              pg_get_functiondef('public.compliance_activate_rule_version(uuid,text)'::regprocedure) like '%reconcile_future_obligations%'),
 (13, '0025: registers/evidence views exclude superseded',      pg_get_viewdef('public.v_compliance_instance'::regclass) like '%superseded%' and pg_get_viewdef('public.v_evidence_requirement'::regclass) like '%superseded%'),
 (14, 'no superseded duplicate live keys',                      not exists (select 1 from public.compliance_instance where status <> 'superseded' group by compliance_id, location_id, period_start having count(*) > 1)),
 (15, 'pg_cron (information only): ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, true)
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
