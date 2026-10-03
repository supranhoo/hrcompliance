-- LIVE CHECK for migrations 0026-0031 (Master Data Administration + Generic Import Framework). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS, last row OVERALL PASS. Also run supabase/tests/live_gate.sql (expects 31 migrations, 48 tables, 12 views, 22 permissions).
with c(n, check_name, ok) as (values
 (1,  '0026: compliance master code is immutable (guard trigger)',        exists (select 1 from pg_trigger where tgname = 'compliance_master_identity' and not tgisinternal)),
 (2,  '0026: rule-version draft/discard + applicability replace exist',   to_regprocedure('public.compliance_rule_new_draft(uuid,date)') is not null and to_regprocedure('public.compliance_rule_discard_draft(uuid)') is not null and to_regprocedure('public.applicability_replace(uuid,jsonb,text)') is not null),
 (3,  '0026: read models exist (master, rule version, applicability)',    to_regclass('public.v_compliance_master') is not null and to_regclass('public.v_compliance_rule_version') is not null and to_regclass('public.v_applicability') is not null),
 (4,  '0027: coverage view + applicability_end exist',                    to_regclass('public.v_compliance_coverage') is not null and to_regprocedure('public.applicability_end(uuid,date,text)') is not null),
 (5,  '0028: LOV / status / settings guards are installed',               (select count(*) = 4 from pg_trigger where tgname in ('lov_set_guard','lov_value_guard','status_definition_guard','system_config_guard') and not tgisinternal)),
 (6,  '0028: engine-used LOV values are protected',                       (select count(*) > 0 and bool_and((v.meta ->> 'protected') = 'true') from public.lov_value v join public.lov_set s on s.id = v.set_id where s.code in ('RISK','SEVERITY','EXCEPTION_CATEGORY','LICENCE_RENEWAL_STATUS'))),
 (7,  '0028: seeded statuses are marked system',                          (select count(*) > 0 and bool_and(is_system) from public.status_definition where module in ('compliance','exception') and code in ('open','completed','resolved','superseded'))),
 (8,  '0029: evidence requirement configuration columns exist',           (select count(*) = 3 from information_schema.columns where table_schema = 'public' and table_name = 'compliance_rule_evidence' and column_name in ('validity_months','requires_verification','help_text'))),
 (9,  '0030: alert-rule read models exist',                               to_regclass('public.v_alert_rule') is not null and to_regclass('public.v_alert_routing_issue') is not null),
 (10, '0031: import tables exist with RLS enforced',                      (select count(*) = 3 and bool_and(relrowsecurity and relforcerowsecurity) from pg_class where relname in ('import_template','import_batch','import_row') and relnamespace = 'public'::regnamespace)),
 (11, '0031: import functions exist',                                     to_regprocedure('public.import_stage(text,text,text,jsonb,jsonb,text)') is not null and to_regprocedure('public.import_validate(uuid)') is not null and to_regprocedure('public.import_commit(uuid,boolean)') is not null and to_regprocedure('public.import_cancel(uuid,text)') is not null),
 (12, '0031: generic reference templates are registered (structure only)', (select count(*) >= 9 from public.import_template where is_active)),
 (13, '0031: import permissions exist and SUPER_ADMIN holds them',        (select count(*) = 2 from public.role_permission rp join public.role r on r.id = rp.role_id where r.code = 'SUPER_ADMIN' and rp.permission_code in ('import.read','import.manage'))),
 (14, 'pg_cron (information only): ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'not installed' end, true)
)
select n, check_name, case when coalesce(ok, false) then 'PASS' else 'FAIL' end as result from c
union all
select 99, 'OVERALL', case when bool_and(coalesce(ok, false)) then 'PASS' else 'FAIL' end from c
order by 1;
-- END OF FILE
