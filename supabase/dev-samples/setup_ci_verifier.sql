-- ONE-TIME SETUP (DEV ONLY) of the dedicated read-only database login "ci_verifier" used by the GitHub workflow "Verify DEV (live, read-only)".
-- NOT a migration. It is never run by CI and never run automatically. You run it once, by hand, in the Supabase SQL Editor of bfcl-hrc-dev (as the default "postgres" role).
-- Safe to re-run (it re-applies the same state, and rotates the password).  The ONLY line you edit is the password placeholder below.
--
-- WHY THE ROLE LOOKS THE WAY IT DOES (full rationale and the exact grants: docs/LIVE_VERIFICATION_AUTOMATION.md)
--  * Every application table uses FORCE ROW LEVEL SECURITY and its policies are written for the API roles. A plain login that only has SELECT therefore sees ZERO rows,
--    and the global verification counts (permissions, roles, org masters ...) would all be wrong. This was measured: with SELECT but without BYPASSRLS the live gate reports 7 false FAILs.
--  * So the role has BYPASSRLS, but ONLY on a whitelist of COLUMNS (below). BYPASSRLS skips row policies; it does not widen what the role may touch. Anything not granted is "permission denied",
--    in particular every employee, contractor, medical, disciplinary, grievance, evidence and attachment-content table.
--  * It owns nothing, has no CREATE anywhere, no INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER, no USAGE on schema "app" (so none of the internal functions can be called) and is in no other role.
--  * Defence in depth on top of those privileges: default_transaction_read_only = on, short timeouts, a connection limit, and the workflow wraps every script in BEGIN READ ONLY ... ROLLBACK.
--  * supabase/dev-samples/live_verifier_role_audit.sql re-proves all of this from the catalogs, as ci_verifier itself, at the start of every workflow run.
--
-- Before running:  generate a password with  openssl rand -hex 24  (48 hex characters). Paste it in place of the placeholder. Do NOT commit it. After running, close the tab and delete the saved snippet.
-- The GitHub secret DEV_DB_PASSWORD must be the same value. The login name for the Session pooler is  ci_verifier.<project-ref>  (see docs/LIVE_VERIFICATION_AUTOMATION.md).

do $setup$
declare
  v_placeholder constant text := 'PASTE-A-LONG-RANDOM-PASSWORD-HERE';
  v_password    constant text := 'PASTE-A-LONG-RANDOM-PASSWORD-HERE';     -- <== the ONLY line to edit (keep the quotes)
  v_env text;
begin
  if v_password = v_placeholder or length(v_password) < 24 then
    raise exception 'SETUP STOPPED: replace the password placeholder with a random value of at least 24 characters (openssl rand -hex 24).';
  end if;
  select value #>> '{}' into v_env from public.system_config where key = 'environment.name';
  if coalesce(v_env, '') <> 'development' then
    raise exception 'SETUP STOPPED: system_config environment.name is "%" - this script only runs on the DEV database (expected "development").', coalesce(v_env, '(not set)');
  end if;

  begin
    if not exists (select 1 from pg_roles where rolname = 'ci_verifier') then
      execute format('create role ci_verifier login nosuperuser nocreatedb nocreaterole noreplication bypassrls connection limit 3 password %L', v_password);
    else
      execute format('alter role ci_verifier login nosuperuser nocreatedb nocreaterole noreplication bypassrls connection limit 3 password %L', v_password);
    end if;
  exception when insufficient_privilege then
    raise exception 'SETUP STOPPED: this login may not create a BYPASSRLS role. Do NOT work around it by widening grants or using the postgres password. Report this message to the project owner.';
  end;
end
$setup$;

-- Server-side guard rails (apply to every connection of this login, including through the pooler).
alter role ci_verifier set default_transaction_read_only = on;
alter role ci_verifier set statement_timeout = '30s';
alter role ci_verifier set lock_timeout = '5s';
alter role ci_verifier set idle_in_transaction_session_timeout = '60s';
alter role ci_verifier set search_path = pg_catalog;

-- Start from nothing so a re-run (or a later, smaller whitelist) cannot leave stale access behind.
revoke all on all tables in schema public from ci_verifier;
revoke all on all sequences in schema public from ci_verifier;
revoke all on schema public from ci_verifier;
revoke all on schema app from ci_verifier;

-- Schemas: USAGE only where a whitelisted table lives. No CREATE anywhere. No USAGE on "app" (internal functions), "auth" or "vault".
grant usage on schema public to ci_verifier;
grant usage on schema storage to ci_verifier;
grant usage on schema supabase_migrations to ci_verifier;

-- ===== COLUMN-LEVEL SELECT WHITELIST (nothing else is readable; no table-level privilege is granted at all) =====
-- live_gate.sql: structure / seed counts
grant select (code)                                   on public.permission        to ci_verifier;
grant select (id, code)                               on public.role              to ci_verifier;
grant select (role_id, permission_code)               on public.role_permission   to ci_verifier;
grant select (id)                                     on public.job_definition    to ci_verifier;
grant select (key)                                    on public.numbering_rule    to ci_verifier;
grant select (kind, code, status)                     on public.config_definition to ci_verifier;
grant select (module)                                 on public.status_definition to ci_verifier;
grant select (id, code)                               on public.lov_set           to ci_verifier;
grant select (set_id, is_active)                      on public.lov_value         to ci_verifier;
grant select (key, value)                             on public.system_config     to ci_verifier;   -- environment.name guard; business configuration only, never secrets
grant select (id, status, scope_all, auth_user_id)    on public.app_user          to ci_verifier;   -- "dev admin provisioned/active/linked" row; NOT email, name, employee code
grant select (user_id, role_id)                       on public.user_role         to ci_verifier;
grant select (id)                                     on public.compliance_instance to ci_verifier;  -- row COUNT only
grant select (id)                                     on public.exception         to ci_verifier;   -- row COUNT only
grant select (id)                                     on public.licence           to ci_verifier;   -- row COUNT only
-- live_attachment_check.sql
grant select (parent_type)                            on public.attachment_target     to ci_verifier;
grant select (link_status)                            on public.attachment            to ci_verifier;  -- pending count only
grant select (id)                                     on public.attachment_access_log to ci_verifier;  -- row COUNT only
grant select (id, public, file_size_limit)            on storage.buckets              to ci_verifier;  -- private-bucket proof
grant select (version)                                on supabase_migrations.schema_migrations to ci_verifier;
-- live_org_masters_inventory.sql: organisation master data only. Deliberately excluded: entity.pan/gstin/cin/legal_name, location address/headcount, authority contact fields.
grant select (id, code, name, is_active)                                         on public.entity        to ci_verifier;
grant select (id, code, name, entity_id, is_active)                              on public.location      to ci_verifier;
grant select (id, code, name, entity_id, is_active)                              on public.business_unit to ci_verifier;
grant select (id, code, name, location_id, business_unit_id, is_active)          on public.unit          to ci_verifier;
grant select (id, code, name, parent_id, is_active)                              on public.department    to ci_verifier;
grant select (code, name, grade, is_active)                                      on public.designation   to ci_verifier;
grant select (code, name, authority_type, is_active)                             on public.authority     to ci_verifier;

-- Final proof, shown as the result of this script: the role and what it can reach.  Expect: all attribute columns false except can_login and bypass_rls; 0 write grants.
select r.rolname as role,
       r.rolcanlogin as can_login, r.rolsuper as superuser, r.rolcreatedb as createdb, r.rolcreaterole as createrole, r.rolreplication as replication, r.rolbypassrls as bypass_rls,
       (select count(*) from pg_class c, lateral aclexplode(c.relacl) a where a.grantee = r.oid and a.privilege_type <> 'SELECT') as table_non_select_privileges,
       (select count(*) from pg_auth_members m where m.member = r.oid) as role_memberships,
       has_schema_privilege(r.oid, 'app', 'usage') as app_schema_usage
  from pg_roles r where r.rolname = 'ci_verifier';
-- END OF FILE
