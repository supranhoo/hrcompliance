-- LIVE CHECK for migration 0036 (register export). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 36 migrations, 49 tables, 18 views, 24 permissions).
with c(n, check_name, ok) as (values
 (1, '0036: report.export permission exists',                                     exists (select 1 from public.permission where code = 'report.export')),
 (2, '0036: report.export is held by SUPER_ADMIN (default; others are a role-permission change)', exists (select 1 from public.role_permission rp join public.role r on r.id = rp.role_id where r.code = 'SUPER_ADMIN' and rp.permission_code = 'report.export')),
 (3, '0036: export_log has RLS enforced',                                         (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.export_log'::regclass)),
 (4, '0036: authenticated can only SELECT and INSERT export_log (append-only through the API)', (select coalesce(string_agg(privilege_type, ',' order by privilege_type), '') = 'INSERT,SELECT' from information_schema.role_table_grants where table_schema = 'public' and table_name = 'export_log' and grantee = 'authenticated')),
 (5, '0036: anon has no access to export_log',                                    not exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name = 'export_log' and grantee = 'anon')),
 (6, '0036: export_record exists and anon cannot execute it',                     to_regprocedure('public.export_record(text,jsonb,integer,boolean)') is not null and not has_function_privilege('anon', 'public.export_record(text,jsonb,integer,boolean)', 'execute')),
 (7, '0036: v_export_log runs as the caller (invoker)',                           (select coalesce(reloptions::text, '') like '%security_invoker=true%' from pg_class where oid = 'public.v_export_log'::regclass)),
 (8, '0036: insert policy requires own user AND report.export',                   (select bool_and(coalesce(with_check, '') like '%report.export%' and coalesce(with_check, '') like '%current_user_id%') from pg_policies where schemaname = 'public' and tablename = 'export_log' and cmd = 'INSERT')),
 (9, 'pg_cron must be OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'))
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
