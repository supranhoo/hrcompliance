# Architecture Decision Log

## D-001 Monorepo with npm workspaces
Decision: `apps/web` plus SQL/scripts/docs at root; `packages/*` created only when code is actually shared. Reason: avoid folder sprawl.
Alternatives: pnpm/turbo (extra tooling, no benefit at this scale). Impact: single `npm run validate`.

## D-002 Supabase migrations are plain ordered SQL, tested on a throwaway Postgres
Decision: `supabase/migrations/<timestamp>_name.sql`, validated by `scripts/validation/db-test.sh` using a shim of `auth`/roles.
Reason: deterministic, reviewable, runnable without a cloud project. Alternatives: Supabase CLI + Docker (not available in this environment; adopt in CI later).
Impact: shim must mirror Supabase defaults; it already exposed one real risk (D-003).

## D-003 Reset default grants, then grant minimally; RLS is the second layer, not the only one
Reason: Supabase grants ALL on new public tables to anon/authenticated. An absent DELETE policy then silently deletes 0 rows instead of erroring.
Decision: migration 0007 revokes all, grants per table. **Every new migration that adds a table must add its own grants, RLS and policies** (checked by the RLS test suite).

## D-004 Typed core columns + metadata-defined custom fields in JSONB
Decision: critical fields are typed columns. Admin-added fields are rows in `field_definition`; values live in a `custom jsonb` column on each
business table, validated server-side against the definition, GIN-indexed, and promoted to typed columns by migration if a field becomes hot.
Reason: no schema change per UI field; core stays queryable and constrained. Alternatives: EAV table (slow, unconstrained), column-per-field DDL from UI (unsafe).
Impact: reporting/import/export read `field_definition` to expand `custom`. Field versions: one live version per (module,key) enforced by partial unique index.

## D-005 Rules are a whitelisted JSON AST, validated in the database
Decision: `app.rule_is_valid` allows only the approved operators, identifier-shaped field names, scalar values, max depth 8; enforced by CHECK constraints.
Reason: administrators can never inject SQL/JS. Impact: evaluator (Phase 4/6) must interpret the same AST; unit-tested against the same fixtures.

## D-006 Dependencies are added with the first feature that needs them
Reason: "every dependency must have a justified purpose". Currently: react, react-router, supabase-js, TanStack Query, zod, tailwind.

## D-007 Business IDs via atomic counter upsert
Decision: `app.next_business_id(rule_key)`; one `INSERT … ON CONFLICT DO UPDATE … RETURNING` per ID; yearly or non-resetting. Verified with 40 parallel callers (40 unique, gapless).
Impact: callable only with service-role / SECURITY DEFINER wrappers, not by API roles.

## D-008 Pre-provisioned users only
Decision: `app_user` rows are created by an admin by email; the first Google login links `auth.users` to it. Reason: "only authorised BFCL users". Open point: also restrict Google sign-in to the BFCL Workspace domain (hosted-domain claim) — needs BFCL decision on domain(s).

## D-009 Audit via row triggers; reasons via transaction-local settings
Decision: `app.audit_row` writes old/new JSON and changed fields (ignoring stamp columns); append-only enforced by triggers incl. TRUNCATE. Reason text via `set_config('app.audit_reason', …, true)`.
Limitation: service-role/superuser sessions can still disable triggers; production DB role hygiene is covered in SECURITY.md.

## D-010 No maker-checker, no month lock (per product requirement 95/96)

## D-011 One versioned `config_definition` store for rule-like configuration (until audited data justifies typed tables)
Decision: SLA, alert, exception, template, contractor-requirement, score, bill-hold, report and import definitions share `config_definition(kind, code, version, status, definition jsonb)`.
Published versions are immutable (trigger); change = `public.config_new_version()`, which retires the previous version atomically (advisory-locked) and records a mandatory reason. Any `when` clause must pass `app.rule_is_valid`.
Reason: those shapes depend on source-data findings that do not exist yet (rule 103); versioning/audit/RLS are solved once. Alternatives: a table per kind now (premature, likely rework).
Impact: each kind is promoted to typed tables with a data-preserving migration when its module is built. Consumers must read the version in force on the record's effective date to keep history stable.

## D-012 Supabase key model, Data API posture, extensions
Browser uses `VITE_SUPABASE_URL` + `VITE_SUPABASE_PUBLISHABLE_KEY` only. Secret/service keys are server-side secrets, never `VITE_`-prefixed, never in Git or chat.
Posture: Data API on, new-table default privileges revoked (0007), RLS enabled+forced on every table, `supabase/tests/security_audit.sql` must return zero rows (CI + run in the SQL editor against the real project).
Extensions (`citext`, `pg_trgm`) live in the `extensions` schema: found by the audit — in `public` their ~80 functions were executable by `anon` through the API.
Note: functions comparing `citext` need `extensions` on their `search_path` (a missing path silently degraded to case-sensitive text comparison; covered by the mixed-case login test).

## D-013 Migration naming and application
Files are `YYYYMMDDNNNNNN_name.sql` (Supabase CLI version = leading digits). Migrations 1–11 have **not been applied to any database**; until the first apply they may be amended. After the first apply they are immutable: only new migrations.
Seed split: required system data is a migration (idempotent); development-only data lives in `supabase/seed/`.

## D-014 TanStack Table pinned to v8; native controls over extra libraries
`@tanstack/react-table` v9 is now `latest` with a different API; v8 is pinned. Date/time pickers use native inputs; dialog/drawer use native `<dialog>`; no calendar/chart/editor library until a module needs one.

## D-015 Profiles = `app_user`
No separate `profiles` table: `app_user` is the application profile (pre-provisioned by email, linked on first login). One identity table avoids drift.

## D-016 Live-project audit findings and the audit's scope
First run of `security_audit.sql` on the real `bfcl-hrc-dev` project (2026-10-03) returned 2 rows; table-level checks were clean (all 32 tables RLS enabled+forced, no anon grants, no exposed table without policy).
1. `public.rls_auto_enable()` — platform event-trigger helper (owner postgres, SECURITY DEFINER) executable by PUBLIC/authenticated → migration 0012 revokes API execute (guarded; no-op where absent). Re-check after any change to the Automatic-RLS setting.
2. Default privileges owned by `supabase_admin` grant to API roles. Not changeable from migrations and not applicable to tables our migrations create (owner `postgres`, whose defaults were verified clean). The audit now checks default privileges only for roles that own our tables; platform-role defaults are documented here instead of failing the audit. Risk to remember: any table created by `supabase_admin` (not by our migrations or the dashboard SQL editor) would receive API grants.
Verification of the audit itself: negative controls (helper present → flagged; owner default to anon → flagged).

## D-017 First-login linking happens in `my_access()`, not only in an insert trigger
Defect (reproduced locally, 2026-10-03): the AFTER INSERT trigger on `auth.users` only links an `app_user` that already exists at the moment of the first Google login. Login before provisioning (or provisioning with a different timing) left `auth_user_id` NULL → `my_access()` returned `{}` → valid users were sent to `/no-access`.
Decision (migration 0013): `my_access()` links the caller to an unlinked `app_user` whose email equals the caller's CONFIRMED auth email. Never re-links a row that already has an `auth_user_id`, never links unconfirmed emails, never activates a disabled user; audited; idempotent. The trigger stays as a fast path.
Frontend: the access result is never cached (`staleTime 0`, `gcTime 0`, refetch on focus), `/no-access` offers "Re-check access" (refreshes the session then re-asks the database) and a token-free diagnostics panel.
Non-goal: an `app_user` already linked to a *different* auth identity is not taken over automatically — that needs an explicit admin action.

## D-018 Authentication & access foundation FROZEN
Owner-confirmed live (2026-10-03): Google login → Supabase session → `my_access()` → SUPER_ADMIN dashboard. Scope, evidence and change procedure: `docs/FROZEN.md`. Migrations 0001–0013 are immutable and hash-locked in CI. Diagnostics are DEV-only. Reopening requires a reproducible defect.

## D-019 Compliance identity vs interpretation
`compliance_master` is identity + legal reference; `compliance_rule_version` holds everything that changes how an obligation is generated. Published versions are immutable, activation is atomic and needs a reason, and instances store the version in force at their period start. Alternative (one mutable row with history table) rejected: easy to rewrite history silently.

## D-020 Applicability: specificity, fail-safe ties, no silent drops
Highest specificity wins (location > business unit > entity > state > establishment type / industry > headcount). Equal-specificity conflicts resolve toward **applicable** and are flagged. A (compliance, location) pair with no decision is reported as **unmapped** instead of being ignored. In-effect rows cannot be rewritten (add a new row), so past periods keep the interpretation that applied then. Conditional rows use the same whitelisted rule AST; unknown facts evaluate false **and are reported** (`missing_facts`).

## D-021 Idempotent generation
`UNIQUE (compliance_id, location_id, period_start)` plus `ON CONFLICT DO NOTHING`. Window defaults: look-back 0 days, horizon 60 days (`system_config`); history arrives via the Import Centre. Daily scheduler key = date, so a second run the same day is refused and logged.

## D-022 One exception model; detectors are SQL; conditions that clear auto-resolve
Detection rules implemented: compliance overdue, evidence missing/rejected/expired, licence expired/expiring. New modules add detectors against the same table. Auto-resolution is explicit (`auto_resolved`, timeline entry, reason text). Severity is derived from risk, never typed per obligation.

## D-023 Alerts notify the most recent reached offset
Per obligation and rule only the latest reached offset inside the catch-up window is notified, so an item due today never receives a stale "due in 3 days". Defaults (T-7, T-3, due, D+1; escalation D+3, D+7 to Head HR; licences T-90…D+1) are **starting points for BFCL review**, stored as versioned `alert_rule` configuration.

## D-024 Dashboard numbers are database aggregates with stated definitions
`compliance_dashboard()` runs as the caller (RLS). Definitions are returned with the numbers. Percentages are NULL, not 0, when nothing is measurable. A caller without `compliance.read` gets an error, not zeros.

## D-025 URL is the single source of register filter state; contracts are tested against real database output
Drill-down links are plain URLs with whitelisted keys. Frontend `select` lists, filter keys and Zod schemas are verified against fixtures generated from the actual migrations (`scripts/validation/gen-fixtures.sh`). A real-browser smoke test (`npm run test:e2e`) runs against the dev server with the network intercepted by those fixtures.

## D-026 Synthetic development samples live outside migrations and seeds
`supabase/dev-samples/` (every code `SAMPLE…`) lets the owner exercise the UI in DEV before real masters exist. It is idempotent, removable, tested in CI, and never auto-applied.
