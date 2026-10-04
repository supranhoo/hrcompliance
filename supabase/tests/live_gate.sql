-- LIVE VERIFICATION GATE (read-only). Paste the ENTIRE file into the Supabase SQL editor of bfcl-hrc-dev and run it.
-- It returns one row per check: PASS / FAIL / INFO / N/A, plus an OVERALL row. Nothing is written.
-- GENERATED from live_gate.template.sql + security_audit.sql by scripts/validation/build-live-gate.sh - do not edit live_gate.sql by hand.
-- Expected state after migrations 0001-38: 38 migrations, 49 tables, 18 views, 24 permissions, 0 audit violations.
-- (The counts above are the same constants the executable checks below use; they are defined once in scripts/validation/build-live-gate.sh.)
with
audit as (
with t as (
  select c.oid, c.relname, c.relowner, c.relrowsecurity as rls, c.relforcerowsecurity as forced
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
), pol as (select polrelid, count(*) n from pg_policy group by 1)
select relname as object, 'RLS not enabled' as violation from t where not rls
union all select relname, 'RLS not forced' from t where rls and not forced
union all select t.relname, 'anon has privilege ' || g.privilege_type
  from t join information_schema.role_table_grants g on g.table_schema='public' and g.table_name=t.relname and g.grantee='anon'
union all select t.relname, 'authenticated has dangerous privilege ' || g.privilege_type
  from t join information_schema.role_table_grants g on g.table_schema='public' and g.table_name=t.relname and g.grantee='authenticated'
  where g.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER')
union all select t.relname, 'authenticated has grants but no RLS policy (exposed table without rules)'
  from t left join pol on pol.polrelid = t.oid
  where coalesce(pol.n,0) = 0 and exists (select 1 from information_schema.role_table_grants g
        where g.table_schema='public' and g.table_name=t.relname and g.grantee='authenticated')
union all select p.proname, 'public function executable by anon'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and has_function_privilege('anon', p.oid, 'execute')
-- Default privileges are checked for the role(s) that OWN our tables. Defaults owned by platform roles such as
-- supabase_admin cannot be changed from migrations and do not apply to tables created by our migrations.
union all select 'default privileges', 'anon/authenticated still receive default grants on new ' || case d.defaclobjtype when 'r' then 'tables' else 'sequences' end || ' created by ' || d.defaclrole::regrole::text
  from pg_default_acl d join pg_namespace n on n.oid=d.defaclnamespace
  where n.nspname='public' and d.defaclobjtype in ('r','S') and d.defaclrole in (select relowner from t)
    and exists (select 1 from aclexplode(d.defaclacl) a join pg_roles r on r.oid=a.grantee where r.rolname in ('anon','authenticated'))
),
mig as (select array_agg(version order by version) as versions from supabase_migrations.schema_migrations),
expected_mig as (select array(select '202610030000' || lpad(g::text, 2, '0') from generate_series(1, 38) g) as versions),
fn as (
  select count(*) filter (where to_regprocedure(f) is not null) as present, count(*) as total from unnest(array[
    'public.my_access()', 'public.system_health()', 'public.config_new_version(text,text,text,jsonb,text,date)',
    'public.compliance_activate_rule_version(uuid,text)', 'public.compliance_coverage(date)', 'public.compliance_create_manual_instance(uuid,uuid,date,text)',
    'public.compliance_calendar(date,date)', 'public.evidence_replace(uuid,text,text,text,bigint,text,date,text)', 'public.compliance_dashboard()',
    'public.compliance_set_status(uuid,text,text)', 'public.exception_set_status(uuid,text,text)', 'public.alert_routing_validation()', 'app.unroutable_recipients(uuid,uuid)', 'public.compliance_rule_new_draft(uuid,date)', 'public.compliance_rule_discard_draft(uuid)', 'public.applicability_replace(uuid,jsonb,text)', 'public.applicability_end(uuid,date,text)', 'public.import_stage(text,text,text,jsonb,jsonb,text)', 'public.import_validate(uuid)', 'public.import_commit(uuid,boolean)', 'public.import_cancel(uuid,text)', 'public.import_template_columns(text)', 'app.reconcile_future_obligations(uuid,date,text)', 'public.compliance_reconciliation_report(uuid)',
    'app.generate_compliance_instances(date,date)', 'app.run_compliance_generation(text)', 'app.detect_exceptions()', 'app.run_exception_detection(text)',
    'app.generate_alerts()', 'app.run_alert_generation(text)', 'app.job_start(text,text,text,text)', 'app.job_finish(uuid,boolean,integer,jsonb)',
    'app.next_business_id(text,date)']) f),
checks(n, check_name, expected, actual, kind) as (values
  (1,  'migrations recorded as applied', '38', (select coalesce(cardinality(versions)::text, 'n/a') from mig), 'exact'),
  (2,  'migration versions are exactly 20261003000001..38 (no gaps, no extras)', 'match', (select case when (select versions from mig) is null then 'n/a' when (select versions from mig) = (select versions from expected_mig) then 'match' else 'MISMATCH: ' || coalesce(array_to_string((select versions from mig), ','), '') end), 'exact'),
  (3,  'security audit violations', '0', (select count(*)::text from audit), 'exact'),
  (4,  'application tables in public', '49', (select count(*)::text from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'), 'exact'),
  (5,  'views in public', '18', (select count(*)::text from information_schema.views where table_schema = 'public'), 'exact'),
  (6,  'permissions', '24', (select count(*)::text from public.permission), 'exact'),
  (7,  'roles', '5', (select count(*)::text from public.role), 'exact'),
  (8,  'scheduled-job definitions', '7', (select count(*)::text from public.job_definition), 'exact'),
  (9,  'numbering rules', '12', (select count(*)::text from public.numbering_rule), 'exact'),
  (10, 'active seeded alert rules (3 defaults + OWNER_FALLBACK; BFCL-added rules such as UNROUTABLE_ESCALATION are not counted)', '4', (select count(distinct code)::text from public.config_definition where kind = 'alert_rule' and status = 'active' and code in ('DEFAULT_COMPLIANCE_ALERT','DEFAULT_COMPLIANCE_ESCALATION','DEFAULT_LICENCE_ALERT','OWNER_FALLBACK')), 'exact'),
  (11, 'compliance + exception status definitions', '9', (select count(*)::text from public.status_definition where module in ('compliance','exception')), 'exact'),
  (12, 'RISK list values (low, medium, high, critical)', '4', (select count(*)::text from public.lov_value v join public.lov_set s on s.id = v.set_id where s.code = 'RISK' and v.is_active), 'exact'),
  (13, 'SUPER_ADMIN holds every permission', (select count(*)::text from public.permission), (select count(*)::text from public.role_permission rp join public.role r on r.id = rp.role_id where r.code = 'SUPER_ADMIN'), 'exact'),
  (14, 'public tables without ROW LEVEL SECURITY forced', '0', (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relforcerowsecurity), 'exact'),
  (15, 'tables readable by the anon role', '0', (select count(distinct table_name)::text from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon'), 'exact'),
  (16, 'extensions installed in public schema', '0', (select count(*)::text from pg_extension e join pg_namespace n on n.oid = e.extnamespace where n.nspname = 'public' and e.extname in ('citext','pg_trgm')), 'exact'),
  (17, 'required functions present', (select total::text from fn), (select present::text from fn), 'exact'),
  (18, 'frozen-foundation behaviour: my_access() is not callable by anon', 'false', (select has_function_privilege('anon', 'public.my_access()', 'execute')::text), 'exact'),
  (19, 'engines are not callable by the API role', 'false', (select (has_function_privilege('authenticated', 'app.generate_compliance_instances(date,date)', 'execute') or has_function_privilege('authenticated', 'app.detect_exceptions()', 'execute') or has_function_privilege('authenticated', 'app.generate_alerts()', 'execute'))::text), 'exact'),
  (20, 'PostgreSQL major version (information)', '-', (select (current_setting('server_version_num')::int / 10000)::text), 'info'),
  (21, 'dev admin provisioned, active, linked (information)', '-', coalesce((select u.status || ', scope_all=' || u.scope_all || ', linked=' || (u.auth_user_id is not null)::text from public.app_user u join public.user_role ur on ur.user_id = u.id join public.role r on r.id = ur.role_id where r.code = 'SUPER_ADMIN' limit 1), 'none'), 'info'),
  (23, 'environment label in system_config (information; must be "development" before loading SAMPLE data)', '-', coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '(not set)'), 'info'),
  (22, 'instances / exceptions / licences currently stored (information)', '-', (select (select count(*) from public.compliance_instance) || ' / ' || (select count(*) from public.exception) || ' / ' || (select count(*) from public.licence)), 'info')
),
graded as (
  select n, check_name, expected, actual,
         case when kind = 'info' then 'INFO' when actual = 'n/a' then 'N/A' when actual = expected then 'PASS' else 'FAIL' end as status
    from checks)
select n, check_name, expected, actual, status from graded
union all
select 99, 'OVERALL', 'no FAIL', (count(*) filter (where status = 'FAIL'))::text || ' FAIL, ' || (count(*) filter (where status = 'PASS'))::text || ' PASS, ' || (count(*) filter (where status = 'N/A'))::text || ' N/A',
       case when count(*) filter (where status = 'FAIL') = 0 then (case when count(*) filter (where status = 'N/A') > 0 then 'PASS (local: migration list not available)' else 'PASS' end) else 'FAIL' end
  from graded
order by 1;
