-- LIVE CHECK for migration 0034 (configuration-driven owner fallback routing, FU-001). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 34 migrations, 48 tables, 17 views, 23 permissions).
with c(n, check_name, ok) as (values
 (1, '0034: no role literal remains in the recipient resolvers',          (select count(*) = 0 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname in ('resolve_recipients','unroutable_recipients') and p.prosrc like '%HEAD_HR%')),
 (2, '0034: OWNER_FALLBACK alert rule exists and is active',               exists (select 1 from app.active_alert_rules() where code = 'OWNER_FALLBACK')),
 (3, '0034: OWNER_FALLBACK never lists "owner"',                           not exists (select 1 from app.active_alert_rules() r cross join lateral jsonb_array_elements_text(r.definition -> 'recipients') x where r.code = 'OWNER_FALLBACK' and x = 'owner')),
 (4, '0034: guard trigger on config_definition is installed',              exists (select 1 from pg_trigger where tgname = 'config_definition_owner_fallback_guard' and not tgisinternal)),
 (5, '0034: 4-/2-argument resolvers are wrappers of the single resolver',  (select count(*) = 2 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname in ('resolve_recipients','unroutable_recipients') and p.pronargs in (2, 4) and p.prosrc ~ 'null::uuid')),
 (6, '0034: routing validation reports no OWNER_FALLBACK error (information: warnings allowed)', not exists (select 1 from app.active_alert_rules() r where r.code = 'OWNER_FALLBACK' and (r.definition -> 'recipients') = '[]'::jsonb)),
 (7, 'pg_cron must be OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'))
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
