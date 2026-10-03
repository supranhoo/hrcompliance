-- LIVE CHECK for migration 0032 (Job Monitor). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 32 migrations, 48 tables, 14 views, 22 permissions).
with c(n, check_name, ok) as (values
 (1, '0032: job_definition.runner column exists',                       exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'job_definition' and column_name = 'runner')),
 (2, '0032: Job Monitor views exist and run as the caller (invoker)',  (select count(*) = 2 and bool_and(coalesce(c.reloptions::text, '') like '%security_invoker=true%') from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('v_job_status','v_job_run'))),
 (3, '0032: job_set_enabled exists, is not executable by anon',        to_regprocedure('public.job_set_enabled(text,boolean,text)') is not null and not has_function_privilege('anon', 'public.job_set_enabled(text,boolean,text)', 'execute')),
 (4, '0032: every declared runner exists',                              (select count(*) = 0 from public.job_definition d where d.runner is not null and to_regprocedure(d.runner) is null)),
 (5, '0032: exactly three jobs have a runner',                          (select count(*) = 3 from public.job_definition where runner is not null)),
 (6, 'pg_cron must be OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'))
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
