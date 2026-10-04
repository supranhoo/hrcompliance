# Implementation Plan & Status

| Phase | Scope | Status (2026-10-04) |
|---|---|---|
| 0 Repo & env | repo, Vite/TS, lint, tests, CI, env | **done**; CI (web, PostgreSQL 16 and 17) runs on every push; Supabase `bfcl-hrc-dev` (PostgreSQL 17) deploys migrations from `claude/peaceful-wozniak-gyfjaw` |
| 1 Audit & architecture | source audit, ERD, plan | architecture/ERD/plan **done**; **source audit BLOCKED** (source workbooks never received) |
| 2 DB foundation | masters, identity, audit, config, platform, jobs, RLS | **done and live-verified** (migrations 0001–0013) |
| 3 App foundation | auth, guards, shell, kit, table | **done**; Google sign-in live |
| 4 Configuration engine | LOV / status / settings / alert rules / exception settings | **done and live-verified** (admin screens, migrations 0026–0030, 0034) |
| 5 Masters | organisation / reference / compliance masters | **done and live-verified** (Compliance Master, rule versions, applicability, licences, reference masters, generic import 0031); **employee & contractor masters BLOCKED** on the source audit |
| 6 Compliance core | master, applicability, generator, calendar, evidence, exceptions, alerts, dashboard, notifications | **done and live-verified** (0014–0025) |
| Platform | users / roles / permissions / scope (incl. department scope), Job Monitor | **done and live-verified** (0032, 0033); 0035 (jobs without a runner are disabled) live-verified; register export (0036) live-verified |
| 7 Reporting & analytics | register export, compliance performance report, licence expiry pipeline, management dashboard | export (0036) and reports (0037) **done and live-verified**; management dashboard (0038) built, awaiting live verification; report layouts / XLSX / scheduled reports wait for agreed BFCL report definitions |
| 8 Contractor compliance | contractor compliance | **BLOCKED**: needs the contractor master from the source audit |
| 9 Cases | case management | **BLOCKED**: business rules not agreed; depends on masters audited against source data |
| 10 Communications | templates, follow-up, email delivery | **BLOCKED**: behaviour not agreed; email integration not configured (needs credentials) |
| 11 Import mappings | real BFCL source-to-target mappings | **BLOCKED**: source workbooks never received (the generic import framework, 0031, is done and live-verified) |
| 12 Operations | scheduler rollout, remaining job runners | schedules approved but **not enabled**; runners for 4 jobs not agreed (disabled definitions, 0035) |
| 13 UAT / release | release readiness | not started |

Migrations 0001–0037 are hash-locked (`docs/FROZEN.md`); evidence is in `docs/LIVE_VERIFICATION.md`. `pg_cron` is OFF; schedules are approved but not enabled (`docs/CRON_PROPOSAL.md`, D-036/D-040). Open follow-ups: `docs/FOLLOWUPS.md`.

## Next increments (in order)
1. (done) migrations 0035 and 0036 live-verified and locked.
2. **Source workbooks** → profile → audit → source-to-target map (template `docs/migration/SOURCE_TO_TARGET_MAP.md`). Still blocked: no files received.
3. Non-blocked product work: register export (0036) and reports (0037) done (docs/EXPORTS.md); management dashboard (0038) next to verify; report layouts, XLSX and scheduled reports wait for agreed BFCL report definitions.
4. Job runners for `due_status_refresh`, `licence_expiry_detection`, `communication_followup`, `housekeeping`: only after the owner agrees the behaviour and acceptance rules.
5. Scheduler rollout (`pg_cron`): only after the gates in `docs/CRON_PROPOSAL.md`.
6. Employee/contractor masters, then contractor compliance: after the source audit.

## Dependency rule
No contractor, case or import module is started until masters + compliance data model are stable and audited against source data.
