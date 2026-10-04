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
| Platform | users / roles / permissions / scope (incl. department scope), Job Monitor | **done and live-verified** (0032, 0033); 0035 (jobs without a runner are disabled) deployed, awaiting live verification |
| 7–13 | contractor → cases → communications → import mappings/reports → ops → UAT/release | not started; contractor, cases, communications and real import mappings **BLOCKED** (dependency rule below) |

Migrations 0001–0034 are hash-locked (`docs/FROZEN.md`); evidence is in `docs/LIVE_VERIFICATION.md`. `pg_cron` is OFF; schedules are approved but not enabled (`docs/CRON_PROPOSAL.md`, D-036/D-040). Open follow-ups: `docs/FOLLOWUPS.md`.

## Next increments (in order)
1. Live-verify migration 0035, then lock it.
2. **Source workbooks** → profile → audit → source-to-target map (template `docs/migration/SOURCE_TO_TARGET_MAP.md`). Still blocked: no files received.
3. Non-blocked product work: register exports / reports over the existing read models (RLS-respecting), operational polish.
4. Job runners for `due_status_refresh`, `licence_expiry_detection`, `communication_followup`, `housekeeping`: only after the owner agrees the behaviour and acceptance rules.
5. Scheduler rollout (`pg_cron`): only after the gates in `docs/CRON_PROPOSAL.md`.
6. Employee/contractor masters, then contractor compliance: after the source audit.

## Dependency rule
No contractor, case or import module is started until masters + compliance data model are stable and audited against source data.
