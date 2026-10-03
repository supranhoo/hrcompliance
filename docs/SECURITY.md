# Security

## Implemented (locally tested)
* Default deny: `anon` has no privileges; `authenticated` receives only explicit per-table grants (D-003). RLS is `FORCE`d on every table.
* Permission model: `permission` → `role_permission` → `user_role` → `app_user`; scope via `user_scope` (entity/location) and `app_user.scope_all`.
* Fail-closed identity: unprovisioned or disabled users resolve to no `app_user` → every policy denies (tests: stranger, disabled super-admin).
* Location writes are scope-restricted (WITH CHECK also blocks moving a row into an out-of-scope entity).
* System roles and system LOV sets cannot be edited/deleted through the API.
* Audit log is append-only (UPDATE/DELETE/TRUNCATE blocked by trigger; no API write grants); readable only with `audit.read`.
* Rule definitions can only contain whitelisted operators (D-005).
* Secrets: `.env.example` lists names only; `.env*` is git-ignored. The service-role key is never used in the browser.

## RLS test coverage today (`supabase/tests/10_rls_and_rules.sql`)
anon, unprovisioned, disabled, viewer (read-only), scoped writer, super-admin; select/insert/update/delete/truncate negatives on masters, config, audit, counters, identity.
**Automated classification audit** (`supabase/tests/security_audit.sql`, asserted empty in `npm run test:db`, also runnable read-only in the Supabase SQL editor): every `public` table has RLS enabled and forced; `anon` holds no table privilege and cannot execute any public function; `authenticated` has no TRUNCATE/REFERENCES/TRIGGER; any table with API grants has ≥1 policy; default privileges no longer hand out grants to API roles. Internal-only tables (`number_counter`, `audit_log` writes, `job_run` writes) have no API write grants.
Findings fixed by it so far: default `DELETE`/`TRUNCATE` grants (D-003); extension functions exposed to `anon` (D-012).
Negative tests also cover: status/config/job tables, secret-looking `system_config` keys, immutable published config, API roles calling `app.job_start`, `system_health` for unprivileged users.

## To do before UAT
Restrict sign-in to BFCL Workspace domain(s); file type/size enforcement in the Drive upload Edge Function; security headers on Cloudflare; dependency audit in CI; rotate/limit service-role usage; production DB role review; penetration-style review of every RPC.

## Key handling
Browser: publishable key only. Never requested in chat, committed, or `VITE_`-prefixed: database password, `sb_secret_…`/legacy service_role, Google OAuth client secret, Gmail credentials. The previously exposed DB password was rotated by the owner and is not relied on.
`system_config` rejects keys that look like secrets (secret/password/token/api_key/private/credential).
