-- LIVE CHECK for migration 0035 (jobs without a runner are disabled definitions). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 35 migrations, 48 tables, 17 views, 23 permissions).
with c(n, check_name, ok) as (values
 (1, '0035: guard trigger on job_definition is installed',                              exists (select 1 from pg_trigger where tgname = 'job_definition_requires_runner' and tgrelid = 'public.job_definition'::regclass and not tgisinternal)),
 (2, '0035: every job without a runner is disabled',                                    not exists (select 1 from public.job_definition where runner is null and is_enabled)),
 (3, '0035: the four unimplemented jobs are still defined, disabled, with placeholder schedules', (select count(*) = 4 and bool_and(not is_enabled and schedule_cron is not null) from public.job_definition where code in ('due_status_refresh','licence_expiry_detection','communication_followup','housekeeping'))),
 (4, '0035: exactly three jobs have a runner (compliance, exception, alert generation)', (select string_agg(code, ',' order by code) = 'alert_generation,compliance_generation,exception_generation' from public.job_definition where runner is not null)),
 (5, '0035: all seven job definitions still exist',                                     (select count(*) = 7 from public.job_definition)),
 (6, 'pg_cron must be OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'))
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
