-- LIVE CHECK for migration 0037 (compliance performance + licence pipeline reports). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 37 migrations, 49 tables, 18 views, 24 permissions).
with c(n, check_name, ok) as (values
 (1, '0037: report functions exist',                                                  to_regprocedure('public.report_compliance_performance(text,date,date)') is not null and to_regprocedure('public.report_licence_pipeline(integer)') is not null),
 (2, '0037: report functions run as the caller (SECURITY INVOKER), so RLS and scope apply', (select count(*) = 2 and bool_and(not prosecdef) from pg_proc where oid in ('public.report_compliance_performance(text,date,date)'::regprocedure, 'public.report_licence_pipeline(integer)'::regprocedure))),
 (3, '0037: anon cannot execute the report functions',                                not has_function_privilege('anon', 'public.report_compliance_performance(text,date,date)', 'execute') and not has_function_privilege('anon', 'public.report_licence_pipeline(integer)', 'execute')),
 (4, '0037: authenticated can execute them',                                          has_function_privilege('authenticated', 'public.report_compliance_performance(text,date,date)', 'execute') and has_function_privilege('authenticated', 'public.report_licence_pipeline(integer)', 'execute')),
 (5, '0037: functions are STABLE (read-only)',                                        (select count(*) = 2 and bool_and(provolatile = 's') from pg_proc where oid in ('public.report_compliance_performance(text,date,date)'::regprocedure, 'public.report_licence_pipeline(integer)'::regprocedure))),
 (6, 'pg_cron must be OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'))
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
