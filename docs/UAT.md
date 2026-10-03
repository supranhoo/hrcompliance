# UAT

Not started — no UAT environment exists. Scope (to be expanded into scripted cases with defect tracking per module as each phase lands):
Login, Permissions, Dashboard, Masters, Configuration, Compliance, Applicability, Calendar, Contractors, Bills, Licences, Evidence, GRC, ESIC, Disciplinary, Liaison, Plant Visit, Communications, Imports, Reports, Audit, Scheduled Jobs.

## Available now (for developer verification, not UAT)
1. `npm run test:db` — 68 database checks. 2. `npm run validate` — web checks.

## Phase 6 — Compliance core UAT script (designed; **not executed**; needs the live dev project with 0014–0022 applied)
Pre-requisite: load `supabase/dev-samples/sample_compliance.sql` (synthetic) **or** real masters; sign in as the dev SUPER_ADMIN.
| # | Scenario | Steps | Expected |
|---|---|---|---|
| C1 | Dashboard from data | Open Executive Dashboard | KPIs match the Compliance Register counts when drilled; no placeholder numbers; empty database shows the "no data in your scope" state with "—" percentages |
| C2 | Drill-down | Click Overdue, Critical exceptions, Next 30 days, Licence bars, Evidence gaps | Each lands on the filtered register; the filter is visible in the URL and removable chips; sharing the URL reproduces the view |
| C3 | Applicability | In SQL: add a location-specific `not_applicable` row; run generation | No new obligation for that location; `compliance_coverage()` lists unmapped pairs |
| C4 | Idempotent generation | Run `select app.run_compliance_generation();` twice | Second call reports "already succeeded"; direct `generate_compliance_instances` re-run inserts 0 |
| C5 | Rule change | Create a draft rule version with a new due day, activate with a reason | Old instances keep their due dates; new periods use the new rule |
| C6 | Status workflow | Open an obligation → Update status → Complete; then reopen | Completion stamps date; reopen demands a reason; reason appears under History (needs `audit.read`) |
| C7 | Exception lifecycle | Let an obligation go overdue; run `app.run_exception_detection()`; complete the obligation; run again | Exception raised once (rerun creates none); auto-resolved when the condition clears; timeline shows both events |
| C8 | Evidence | (Document storage not connected) check Evidence register states; insert evidence rows by SQL if needed | Missing/pending/verified/rejected/expired derive correctly; replacing evidence keeps the old version |
| C9 | Licence expiry | View Licences with expired/soon/valid samples | Categories and renewal window follow `licence.expiry_thresholds`; changing the setting changes categories without code |
| C10 | Alerts | Run `app.run_alert_generation()` | In-app notifications created once per obligation/offset; none for completed items; email not queued while Gmail is NOT_CONFIGURED |
| C11 | Scope | Create a user scoped to one location | Sees only that location in registers, calendar and dashboard |
| C12 | Calendar | Month / Week / Agenda; navigate; click a day | Items on the right dates, colour + text states, day panel links to the register |
