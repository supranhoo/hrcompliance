# Implementation Plan & Status

| Phase | Scope | Status |
|---|---|---|
| 0 Repo & env | repo, Vite/TS, lint, tests, CI, env | **done locally**; CI workflow written, never run on GitHub; Supabase dev project exists but **no migration applied yet** (container cannot reach supabase.com) |
| 1 Audit & architecture | source audit, ERD, plan | architecture/ERD/plan **done**; **source audit BLOCKED** (no files received) |
| 2 DB foundation | masters, identity, audit, config, platform, jobs, RLS | **done locally** (migrations 1–11; 127 checks incl. negative RLS, security audit, concurrency). Employee/contractor masters wait for the audit |
| 3 App foundation | auth, guards, shell, kit, table | **done locally**: shell (collapsible/mobile sidebar, breadcrumbs, profile menu, notification shell, toasts, error boundary, 404/unauthorized), UI kit, server-driven SmartTable, service contracts, Users + System Health pages, PKCE auth callback + return-path guard (59 tests; browser smoke in headless Chromium). **Real Google login untested** (`docs/AUTH.md`) |
| 4 Configuration engine | Field/Section/LOV/Status/Rule/Template/SLA/Numbering UIs + evaluator | schema foundation done (fields, sections, LOV, status, rules, versioned definitions, numbering); **no admin screens, no rule evaluator, no dynamic form renderer yet** |
| 5–13 | masters → compliance → dashboard → contractor → cases → comms → import/reports → ops → UAT/release | not started |

## Next increments (in order)
1. **Apply migrations to `bfcl-hrc-dev`** (done: 1–11 applied; 0012 pending deploy), re-run the security audit there (must be 0 rows), bootstrap the dev admin, then the first real Google login (`docs/AUTH.md` T4–T8).
2. **Source workbooks** → profile → complete `docs/migration/SOURCE_DATA_AUDIT.md` (blocks Phase 5).
3. Phase 4: LOV Designer → Status Designer → Field/Section Designer + dynamic form renderer → rule evaluator (shared fixtures with `rule_is_valid`).
4. Job runner Edge Function skeleton (calls `app.job_start/finish`) + Job Monitor page.
5. Phase 5 masters shaped by the audit.

## Dependency rule
No contractor, case or import module is started until masters + compliance data model are stable and audited against source data.
