-- LIVE VERIFIER ROLE AUDIT (read-only, one SELECT, changes nothing). Run by the workflow "Verify DEV (live, read-only)" as the FIRST step, as ci_verifier itself.
-- It proves from the catalogs that the login is still exactly what supabase/dev-samples/setup_ci_verifier.sql created. The workflow stops if any row is FAIL.
-- Everything is read from pg_catalog (visible to every role); nothing here depends on the verifier's own table privileges.
-- EXPECTED: every row PASS (INFO rows are information), last row OVERALL PASS.
with me as (select r.* from pg_roles r where r.rolname = current_user),
col_grants as (   -- every column-level privilege held by the verifier, as table.column:PRIVILEGE
  select c.relnamespace::regnamespace::text || '.' || c.relname || '.' || a.attname || ':' || x.privilege_type as g
    from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    cross join lateral aclexplode(a.attacl) x join me on x.grantee = me.oid),
tbl_grants as (   -- every table-level privilege held by the verifier
  select c.relnamespace::regnamespace::text || '.' || c.relname || ':' || x.privilege_type as g
    from pg_class c cross join lateral aclexplode(c.relacl) x join me on x.grantee = me.oid),
expected(g) as (values
  ('public.permission.code'), ('public.role.id'), ('public.role.code'), ('public.role_permission.role_id'), ('public.role_permission.permission_code'),
  ('public.job_definition.id'), ('public.numbering_rule.key'), ('public.config_definition.kind'), ('public.config_definition.code'), ('public.config_definition.status'),
  ('public.status_definition.module'), ('public.lov_set.id'), ('public.lov_set.code'), ('public.lov_value.set_id'), ('public.lov_value.is_active'),
  ('public.system_config.key'), ('public.system_config.value'), ('public.app_user.id'), ('public.app_user.status'), ('public.app_user.scope_all'), ('public.app_user.auth_user_id'),
  ('public.user_role.user_id'), ('public.user_role.role_id'), ('public.compliance_instance.id'), ('public.exception.id'), ('public.licence.id'),
  ('public.attachment_target.parent_type'), ('public.attachment.link_status'), ('public.attachment_access_log.id'),
  ('storage.buckets.id'), ('storage.buckets.public'), ('storage.buckets.file_size_limit'), ('supabase_migrations.schema_migrations.version'),
  ('public.entity.id'), ('public.entity.code'), ('public.entity.name'), ('public.entity.is_active'),
  ('public.location.id'), ('public.location.code'), ('public.location.name'), ('public.location.entity_id'), ('public.location.is_active'),
  ('public.business_unit.id'), ('public.business_unit.code'), ('public.business_unit.name'), ('public.business_unit.entity_id'), ('public.business_unit.is_active'),
  ('public.unit.id'), ('public.unit.code'), ('public.unit.name'), ('public.unit.location_id'), ('public.unit.business_unit_id'), ('public.unit.is_active'),
  ('public.department.id'), ('public.department.code'), ('public.department.name'), ('public.department.parent_id'), ('public.department.is_active'),
  ('public.designation.code'), ('public.designation.name'), ('public.designation.grade'), ('public.designation.is_active'),
  ('public.authority.code'), ('public.authority.name'), ('public.authority.authority_type'), ('public.authority.is_active')),
c(n, check_name, ok, info) as (values
 (1, 'the connection is the dedicated login ci_verifier', (select count(*) = 1 from me where rolname = 'ci_verifier'), null::text),
 (2, 'not SUPERUSER, CREATEDB, CREATEROLE or REPLICATION; can log in',
     (select count(*) = 1 and bool_and(rolcanlogin and not rolsuper and not rolcreatedb and not rolcreaterole and not rolreplication) from me), null),
 (3, 'INFO: BYPASSRLS (needed so global counts work over FORCE RLS tables; reach is limited to the column whitelist)', null, (select rolbypassrls::text from me)),
 (4, 'member of no other role (nothing inherited)', not exists (select 1 from pg_auth_members m join me on m.member = me.oid), null),
 (5, 'owns no table, view, sequence, function or schema', not exists (select 1 from pg_class c join me on c.relowner = me.oid) and not exists (select 1 from pg_proc p join me on p.proowner = me.oid) and not exists (select 1 from pg_namespace s join me on s.nspowner = me.oid), null),
 (6, 'holds NO table-level privilege at all (access is column-level only)', not exists (select 1 from tbl_grants), null),
 (7, 'holds only SELECT at column level (no INSERT / UPDATE / REFERENCES on any column)', not exists (select 1 from col_grants where g not like '%:SELECT'), null),
 (8, 'the readable column set is EXACTLY the documented whitelist (nothing extra, nothing missing)',
     not exists (select 1 from col_grants where replace(g, ':SELECT', '') not in (select g from expected)) and not exists (select 1 from expected e where not exists (select 1 from col_grants cg where cg.g = e.g || ':SELECT')), null),
 (9, 'no CREATE privilege on any schema or on the database',
     not exists (select 1 from pg_namespace s where has_schema_privilege(current_user, s.oid, 'create')) and not has_database_privilege(current_user, current_database(), 'create'), null),
 (10, 'no USAGE on schema app (internal functions unreachable), nor on auth / vault where present',
     not exists (select 1 from pg_namespace s where s.nspname in ('app', 'auth', 'vault') and has_schema_privilege(current_user, s.oid, 'usage')), null),
 (11, 'no privilege on any sequence (cannot advance a counter)',
     not exists (select 1 from pg_class c where c.relkind = 'S' and (has_sequence_privilege(current_user, c.oid, 'usage') or has_sequence_privilege(current_user, c.oid, 'update'))), null),
 (12, 'role setting default_transaction_read_only = on is stored',
     exists (select 1 from pg_db_role_setting s join me on s.setrole = me.oid where 'default_transaction_read_only=on' = any (s.setconfig)), null),
 (13, 'role settings include a statement_timeout',
     exists (select 1 from pg_db_role_setting s join me on s.setrole = me.oid where exists (select 1 from unnest(s.setconfig) x where x like 'statement_timeout=%')), null),
 (14, 'THIS transaction is read-only (the workflow wraps every script in BEGIN READ ONLY)', current_setting('transaction_read_only') = 'on', null),
 (15, 'the target is a DEV database: system_config environment.name = development',
     coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') = 'development', null),
 (16, 'INFO: whitelisted columns granted', null, (select count(*)::text || ' of ' || (select count(*) from expected)::text from col_grants))
)
select n, check_name, case when info is not null then 'INFO' when coalesce(ok, false) then 'PASS' else 'FAIL' end as result, info from c
union all
select 99, 'OVERALL', case when bool_and(info is not null or coalesce(ok, false)) then 'PASS' else 'FAIL' end, null from c
order by 1;
-- END OF FILE
