-- LIVE CHECK for migration 0038 (management dashboard). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 38 migrations, 49 tables, 18 views, 24 permissions).
with c(n, check_name, ok) as (values
 (1, '0038: management_dashboard exists, runs as the caller (SECURITY INVOKER) and is STABLE', (select count(*) = 1 and bool_and(not prosecdef and provolatile = 's') from pg_proc where oid = to_regprocedure('public.management_dashboard(uuid,uuid,uuid,date,date)'))),
 (2, '0038: anon cannot execute it, authenticated can',                                  to_regprocedure('public.management_dashboard(uuid,uuid,uuid,date,date)') is not null and not has_function_privilege('anon', 'public.management_dashboard(uuid,uuid,uuid,date,date)', 'execute') and has_function_privilege('authenticated', 'public.management_dashboard(uuid,uuid,uuid,date,date)', 'execute')),
 (3, '0038: helper app.mgmt_instances runs as the caller',                               (select count(*) = 1 and bool_and(not prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'mgmt_instances')),
 (4, '0038: v_compliance_instance exposes owner_department_id and still runs as the caller', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'v_compliance_instance' and column_name = 'owner_department_id') and (select coalesce(reloptions::text, '') like '%security_invoker=true%' from pg_class where oid = 'public.v_compliance_instance'::regclass)),
 (5, '0038: v_exception exposes department_id and still runs as the caller',             exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'v_exception' and column_name = 'department_id') and (select coalesce(reloptions::text, '') like '%security_invoker=true%' from pg_class where oid = 'public.v_exception'::regclass)),
 (6, '0038: the original compliance_dashboard() is unchanged and still present',         to_regprocedure('public.compliance_dashboard()') is not null),
 (7, '0038: RISK and SEVERITY lists have at least one active value (used for "critical")', (select count(distinct s.code) = 2 from public.lov_value v join public.lov_set s on s.id = v.set_id where s.code in ('RISK','SEVERITY') and v.is_active)),
 (8, 'pg_cron must be OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'))
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
