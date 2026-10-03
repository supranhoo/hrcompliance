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
**Gap:** tests exist for each *current* table family but not yet auto-enumerated for "every protected table" — an automated check that every table in `public` has RLS enabled, FORCE and ≥1 policy is a Phase 2 follow-up (see IMPLEMENTATION_PLAN).

## To do before UAT
Restrict sign-in to BFCL Workspace domain(s); file type/size enforcement in the Drive upload Edge Function; security headers on Cloudflare; dependency audit in CI; rotate/limit service-role usage; production DB role review; penetration-style review of every RPC.
