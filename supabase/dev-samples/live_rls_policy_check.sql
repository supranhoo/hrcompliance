-- LIVE CHECK for migration 0039 (RLS policies evaluated once per statement). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 39 migrations, 49 tables, 18 views, 24 permissions).
-- Behavioural equivalence is proven in CI by suite 64; after this check, confirm in the app that a scoped user still sees only their scope (Register, Exceptions).
with c(n, check_name, ok) as (values
 (1, '0039: scope helper functions exist',                          to_regprocedure('app.is_scope_all()') is not null and to_regprocedure('app.my_scope_ids(text)') is not null),
 (2, '0039: anon cannot execute the helpers',                       not has_function_privilege('anon', 'app.is_scope_all()', 'execute') and not has_function_privilege('anon', 'app.my_scope_ids(text)', 'execute')),
 (3, '0039: authenticated can execute the helpers',                 has_function_privilege('authenticated', 'app.is_scope_all()', 'execute') and has_function_privilege('authenticated', 'app.my_scope_ids(text)', 'execute')),
 (4, '0039: 18 policies use the once-per-statement scope flag',     (select count(*) from pg_policies where schemaname = 'public' and (coalesce(qual, '') || coalesce(with_check, '')) like '%is_scope_all%') = 18),
 (5, '0039: obligation/exception/licence tables still have RLS on', (select bool_and(relrowsecurity) from pg_class where oid in ('public.compliance_instance'::regclass, 'public.exception'::regclass, 'public.licence'::regclass, 'public.evidence'::regclass, 'public.compliance_applicability'::regclass))),
 (6, 'pg_cron must be OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'extension not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'))
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
