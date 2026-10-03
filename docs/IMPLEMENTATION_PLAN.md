# Implementation Plan & Status

| Phase | Scope | Status |
|---|---|---|
| 0 Repo & env | repo, Vite/TS, lint, tests, CI, env | **done locally**; CI workflow written, never run on GitHub; Supabase dev project exists but **no migration applied yet** (container cannot reach supabase.com) |
| 1 Audit & architecture | source audit, ERD, plan | architecture/ERD/plan **done**; **source audit BLOCKED** (no files received) |
| 2 DB foundation | masters, identity, audit, config, platform, jobs, RLS | **done locally** (migrations 1–11; 127 checks incl. negative RLS, security audit, concurrency). Employee/contractor masters wait for the audit |
| 3 App foundation | auth, guards, shell, kit, table | **done locally**: shell (collapsible/mobile sidebar, breadcrumbs, profile menu, notification shell, toasts, error boundary, 404/unauthorized), UI kit, server-driven SmartTable, service contracts, Users + System Health pages, PKCE auth callback + return-path guard (59 tests; browser smoke in headless Chromium). **Real Google login untested** (`docs/AUTH.md`) |
| 4 Configuration engine | Field/Section/LOV/Status/Rule/Template/SLA/Numbering UIs + evaluator | schema foundation done (fields, sections, LOV, status, rules, versioned definitions, numbering); **no admin screens, no rule evaluator, no dynamic form renderer yet** |
| 5 Masters | organisation/reference masters | org + authority + law + document types exist; **employee & contractor masters wait for the source audit**; no master-data entry UI yet (Phase 4 designers) |
| 6 Compliance core | master, applicability, generator, calendar, evidence, exceptions, alerts, dashboard | **database layer done and locally tested (migrations 0014–0022, 11 SQL suites)**; UI done and locally tested: dashboard, compliance/exception/licence/evidence registers, calendar, quick views with status actions; **not yet deployed/verified on the live project**; engines **not scheduled** yet |
| 7–13 | contractor → cases → communications → import/reports → ops → UAT/release | not started |

## Next increments (in order)
1. **Deploy 0014–0022 to `bfcl-hrc-dev`** (push triggers it), re-run `security_audit.sql` (must be 0 rows), optionally load `supabase/dev-samples/sample_compliance.sql`, and walk the Phase 6 UAT script (`docs/UAT.md`).
2. **Source workbooks** → profile → audit → source-to-target map (`docs/migration/SOURCE_TO_TARGET_MAP.md` is the template). Still blocked: no files received.
3. Schedule the engines (enable `pg_cron`, `docs/OPERATIONS.md`) and build the Job Monitor page.
4. Phase 4 admin designers (LOV/Status/Field/Rule/Alert/SLA) and master-data entry screens, shaped by the audit.
5. Phase 5 employee/contractor masters, then Phase 8 contractor compliance.

## Dependency rule
No contractor, case or import module is started until masters + compliance data model are stable and audited against source data.
