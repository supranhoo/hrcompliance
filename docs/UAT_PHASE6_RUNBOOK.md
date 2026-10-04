# Phase 6 live UAT runbook — `bfcl-hrc-dev` (DEVELOPMENT, synthetic data)

You run this; Claude cannot reach the live project from the cloud container. Paste anything surprising (exact text or screenshot) and it goes into `docs/qa/DEFECT_LOG.md` unaltered.
All SQL is run in **Supabase → SQL Editor** as the default `postgres` role. Files live in the repo (GitHub → `supabase/…`): open the file, **copy the entire contents**, paste, **Run**.
The editor shows the result of the **last** statement only — each script is written to end with the table you need.

## Part 0 — Gate: is the deployment what we think it is?
1. Run `supabase/tests/live_gate.sql`. You get ~23 rows ending with `OVERALL`. **Send it all.** Expect `OVERALL … PASS`, `19 PASS, 0 FAIL`.
2. Anything `FAIL` → stop. Do not continue to Part 1. Send the FAIL rows; I will diagnose only the unapplied migration(s) and dependencies (I will not edit anything already applied).
3. Optional cross-check in the dashboard: Database → Migrations lists 22 versions; Table Editor shows 45 tables in `public`.

## Part 1 — Label the environment, load the synthetic samples
1. Run once (marks this project as development; the sample scripts refuse to run anywhere else):
```sql
insert into public.system_config (key, value, description) values ('environment.name', '"development"', 'Environment label')
on conflict (key) do update set value = excluded.value;
```
2. Run `supabase/dev-samples/sample_compliance.sql`. Result: one row `SAMPLE data loaded (synthetic)…`, `sample_compliances = 3`, `sample_licences = 3`, `obligations_now = 0`.
3. Run it **a second time**: the same row again, nothing duplicated (idempotent).
What it creates (all codes start `SAMPLE`): entity `SAMPLE-ENT`; locations `SAMPLE-LOC-A` (plant, 120 employees) and `SAMPLE-LOC-B` (office, 15); three compliances (monthly with mandatory evidence, quarterly applicable only where 50+ employees, event-based 30 days); three licences (expired, expiring in 15 days, valid); default owner = you.

## Part 2 — Engines, step by step (this is the "prove it before scheduling" gate)
**Why 8 small files:** the Supabase SQL Editor can cut off a large pasted `DO $$ … $$` block (error `unterminated dollar-quoted string`). The engine demo is therefore split into eight small, independent files. Each is under 7 KB, has its own DEVELOPMENT guard, creates its own short-lived result table, prints one small PASS/FAIL/INFO table, and ends with the line `-- END OF FILE`.

**For EVERY file below:** open a **new, empty** SQL tab → copy the **whole** file (GitHub → file → Raw → select all → copy) → paste → check the last visible line is `-- END OF FILE` (if not, the paste was cut: clear the tab and paste again) → press **Run once**. Never run a highlighted fragment. Send me the result table (or a screenshot) for each file.

| Order | File | What it proves | Expected |
|---|---|---|---|
| 1 | `uat_engine_01_generator.sql` | generator first run creates obligations; the 3 event-based SAMPLE obligations exist | 1a–1c PASS (1b INFO only if already generated) |
| 2 | `uat_engine_02_idempotency.sql` | second same-day wrapper call refused; identical direct run inserts 0; no duplicate keys | 2a–2c PASS, 2d INFO (count) |
| 3 | `uat_engine_03_applicability.sql` | quarterly exists at LOC-A, none at LOC-B (15 employees < 50); coverage = not_applicable | 3a–3d PASS |
| 4 | `uat_engine_04_exceptions.sql` | exceptions raised; identical second detection raises 0; one active exception per key; overdue exception exists | 4a–4d PASS (4a INFO on re-runs) |
| 5 | `uat_engine_05_auto_resolution.sql` | completes one overdue SAMPLE obligation → its exception auto-resolves; monthly completed without evidence raises `evidence_missing` | 5a–5c PASS (INFO only on re-runs when nothing overdue is left) |
| 6 | `uat_engine_06_alerts.sql` | alerts created; identical repeat creates 0; no duplicate keys; closed obligations never alert; no email while Gmail NOT_CONFIGURED | 6a PASS, or **INFO = known defect D-001** (no valid recipient); 6b–6e PASS |
| 7 | `uat_engine_07_job_log.sql` | latest succeeded `job_run` for each of the three engines (duration, records) | 3 PASS |
| 8 | `uat_engine_08_overall.sql` | reads the persistent database state + job log (no temp table from other files) and prints `OVERALL` | `OVERALL = PASS` (INFO rows are explained; 8.08 INFO = D-001) |

**Run the whole sequence 1→8 a second time** (new tab each time): every PASS stays PASS, 02/04/06 still show "inserts/raises 0", nothing duplicates. INFO rows on the second pass saying "already generated / wrapper already ran" are expected.
Row 6a `INFO` with 0 notifications is recorded as known baseline defect **D-001**, not an engine failure.
`uat_engine_demo.sql` (the single large script) remains in the repo for engineering/CLI use only; do not use it in the SQL Editor.

## Part 3 — Scope, evidence states, ageing, rule change (SQL evidence)
Run each, in this order, and send the result tables:
1. `uat_scope_check.sql` — impersonates a synthetic user limited to `SAMPLE-LOC-B`. Expect all PASS, one INFO row (coverage report, decision F1), `OVERALL PASS`.
2. `uat_evidence_fixture.sql` — attaches synthetic evidence in four states. Expect the final table to list all five states: `expired, missing, pending_review, rejected, verified`.
3. `uat_backdate_exception.sql` — back-dates three SAMPLE exceptions. Expect buckets `0-7, 8-30, 31-90, 90+` and some `target_breached`.
4. `uat_rule_change.sql` — needs you to have signed in once (linked account). Expect 4 PASS: v1 retired / v2 active with reason; old obligations keep the 15th; a later period uses the 20th.

## Part 4 — Browser UAT, in sequence (sign in at https://hrcompliance.pages.dev as the dev SUPER_ADMIN)
Use a normal window; for the mobile check resize the window to phone width or use the browser's device toolbar.

| # | Case | Steps | Expected | Result (PASS/FAIL, note) |
|---|---|---|---|---|
| C1 | Executive Dashboard | Open the dashboard | KPI tiles show numbers (not "—") after Part 2; subtitle states the compliance % definition; sections: exceptions by severity, ageing, licences, evidence, by location, next due; no placeholder values | |
| C1b | Numbers agree with registers | Note Overdue / Due soon / Next 30 days / Critical exceptions; then drill into each | Register totals ("1–n of N") equal the tile; empty state wording if zero | |
| C2 | KPI drill-downs | Click each tile and each bar/link: Overdue, Due soon, Next 30 days, Critical exceptions, severity bars, ageing bars, "past their target", licence buckets, renewal window, evidence Missing/Rejected/Expired/Pending, a location, a Next-due item | Each lands on the matching register with the filter **in the URL** and shown as a control/chip; Back returns to the dashboard; copying the URL into a new tab reproduces the same filtered view | |
| C2b | URL filters | On Compliance Register: set State=Overdue, Risk=High; reload; remove one filter; "Clear filters"; edit the URL by hand to add `?location_code=SAMPLE-LOC-B` | Filters survive reload; chips removable; page resets to 1 when filters change; unknown URL keys are ignored | |
| C3 | Applicability | Compliance Register, search `SAMPLE-QUARTERLY`; add `?location_code=SAMPLE-LOC-B` | Quarterly obligations exist for LOC-A and **none** for LOC-B. SQL cross-check: `select * from public.compliance_coverage() where compliance_code like 'SAMPLE%'` shows LOC-B quarterly = `not_applicable` | |
| C4 | Idempotent generation | Note the Register total; run `select app.generate_compliance_instances(current_date - 90, current_date + 60);` twice; refresh | Total unchanged (Part 2 rows 2a–2c) | |
| C5 | Rule change | Part 3 step 4 output; then Register: older obligations vs. the new-period obligation | Old due dates unchanged; new period uses the new day; History tab (if audit.read) shows the version change as audit rows | |
| C6 | Status actions + mandatory reasons | Open an open obligation → Summary → "Update status" → In progress → Apply; then Completed. Then try **Open** (reopen) without a reason, then with one. Try **Not applicable** without/with reason | "Reason required" is shown in the dropdown; Apply stays disabled for blank reason; completion stamps today's date; the reason appears under **History** | |
| C7 | Exception register + ageing | Exceptions page. Filter Severity, Status, Age. Open a row: Summary, Timeline, History. Acknowledge; then Resolve with a note; try Resolve with a blank note | Ageing columns/buckets correct after Part 3 step 3; "Target" in red when breached; resolve needs a note; timeline lists detected / status changes / comments; add a comment | |
| C7b | Exception auto-resolution | Part 2 row 4: open that exception | Status Resolved, "Condition cleared automatically", timeline "Auto resolved" | |
| C8 | Evidence states | Evidence page; filter State = each of the five; open one | All five states visible after Part 3 step 2; states match the fixture (pending / verified / rejected / expired; the rest missing); upload not available (storage "NOT CONFIGURED") | |
| C9 | Licence register | Licences page; filters Expiry / Renewal; open each licence | Expired = red badge, ≤15d = red, valid = green; days left correct; renewal window shown; Timeline tab empty state. **Config check:** run `update public.system_config set value='[120,45]' where key='licence.expiry_thresholds';` refresh → categories change without code; then restore `[90,60,30,15,7]` | |
| C10 | Alerts | SQL: `select channel, category, title, created_at from public.notification order by created_at desc;` | In-app rows for owner; titles say "due in 3 day(s)", "is due today", "overdue by … day(s)" (event-based samples); no email rows (Gmail NOT_CONFIGURED); **the bell in the app is a placeholder — in-app notifications are not visible in the UI (gap G-001)** | |
| C11 | Scope | Part 3 step 1 result is the evidence. Optional: create a second Google user via Users + `user_role`/`user_scope` (needs a second account) | Single-location user sees only its location's obligations, exceptions, calendar, dashboard; no licences/evidence of other locations | |
| C12 | Calendar | Calendar: Month, Week, Agenda; ‹ Today ›; click a day; resize to phone | Month = 6 weeks Monday-first; event-based samples on today / +3 / −2 days; day panel lists items with state badges + "Open in register"; legend names every state; Agenda groups by date; no horizontal page scroll on mobile | |
| C13 | Permissions in the UI | Log out → open `/compliance` | Redirected to Login. (A second user without `exception.read` would see the permission message and no menu entry — tested in CI) | |

## Part 5 — Clean up
1. Run `supabase/dev-samples/remove_samples.sql` (removes only `SAMPLE…` rows, the synthetic scoped user, and their notifications/evidence/exceptions; audit history stays by design).
2. Run `supabase/tests/live_gate.sql` again; information row 22 should show your real counts (0/0/0 if nothing else was loaded).
3. Verify nothing is left: `select count(*) from public.entity where code like 'SAMPLE%';` → 0 (same for `compliance_master`, `licence`, `location`).

## Recording results
Fill the table above and `docs/LIVE_VERIFICATION.md`, or just paste outputs/screenshots to Claude, who will record them verbatim. Any FAIL or surprise → one row in `docs/qa/DEFECT_LOG.md` (section "Found during live UAT").


## Baseline expectations vs. owner-approved gaps (so they are not mistaken for new defects)
This baseline runs on migrations 0001-0022 as deployed. Three behaviours differ from the owner decisions on purpose until migrations 0023+ exist; record them as **known baseline gaps**, not as UAT failures:
| Where you will see it | Baseline behaviour | Decided behaviour (after UAT) | Defect |
|---|---|---|---|
| Engine step `uat_engine_06` row 6a `INFO` ("NOTHING created …") | alerts with no valid recipient are dropped silently | durable UNROUTABLE exception + notification, System Health + Notification Centre; Super Admin fallback DEV only | D-001 |
| `uat_scope_check` INFO row "coverage report lists other locations" | applicability / coverage readable regardless of scope | Applicability Matrix and coverage scope-controlled; Location Master stays global | F-1 |
| `uat_rule_change` (after migration 0025) | F-2 implemented: rows show history keeps v1, future untouched obligations superseded + recreated under v2, actioned ones pinned | — | F-2 (fixed in 0025) |
Anything else that is not PASS is a **new** defect: paste it verbatim, it goes into `docs/qa/DEFECT_LOG.md` unaltered, and sample data is never edited to hide it.

## Evidence capture sheet (send back, one block per script)
`script name` · timestamp · every result row exactly as shown (or a screenshot) · for the engine demo, run 1 and run 2 separately.


## Baseline closure status (2026-10-03)
* **Live, owner-reported — PASS:** Gate (live_gate), samples load, engine files 01–08 (OVERALL PASS, 17 obligations, 3 notifications). The full 01–08 sequence is **not** to be repeated by hand: second-pass evidence = live idempotency proofs in 02/04/06 + automated PG16/17 two-pass run (`scripts/validation/uat-modular-test.sh`). Record: `docs/LIVE_VERIFICATION.md`.
* **Automated (CI, PG16/17) — PASS:** scope, evidence-state, ageing and rule-change scripts; headless-browser checks (see below).
* **Remaining live-only checks:** see the consolidated list at the end of this file; the four Part-3 scripts are optional live re-confirmation and need no manual effort unless the owner wants live proof.

## Browser UAT C1–C13: what is automated, what needs a human
Automated = `npm run test:e2e` (headless Chromium, 23 checks, network intercepted and answered from fixtures generated from the real database; runs in CI) + 127 unit/component tests. **These do not talk to the live Supabase/Google**, so the "Live" column is the residual.
| Case | Automated (CI) | Live-only residual (owner, ~10 min total) |
|---|---|---|
| C1 Dashboard | renders server numbers; compliance-% definition shown | eyeball that the numbers look sensible against the sample data |
| C1b/C2 Drill-downs | overdue tile → register with `due_state=overdue` in URL; filter control reflects URL; server range+count queries | none (equality of tile vs register total is checked by SQL below) |
| C2b URL filters | filter ↔ URL sync, unknown keys ignored, `due_within` becomes a date range | none |
| C3 Applicability | SQL (engine 03, CI + live PASS) | none |
| C4 Idempotent generation | SQL (engine 02, live PASS) | none |
| C5 Rule change | SQL (`uat_rule_change.sql`, CI) | none |
| C6 Status actions + mandatory reasons | transition/reason rules in SQL suites; UI logic in unit tests | **one live click-through**: open one obligation → Update status → try Open without reason (blocked) → with reason (works) |
| C7/C7b Exceptions, ageing, auto-resolution | engine 04/05 (live PASS), ageing buckets (CI) | none |
| C8 Evidence states | `uat_evidence_fixture.sql` (CI: all five states) | none |
| C9 Licence register | unit + e2e register render; thresholds read from config | glance at badge colours (expired red / valid green) |
| C10 Alerts | engine 06 (live PASS: 3 notifications) | none (bell is a known placeholder, G-001, fixed in 0023 work) |
| C11 Scope | `uat_scope_check.sql` (CI) | none |
| C12 Calendar | e2e: month grid has 42 cells; RPC called for visible range only | glance at month/week/agenda once |
| C13 Permissions/redirects | e2e: no-permission message, nav hides sections, `/no-access`, signed-out → `/login` | none |
| Responsive | e2e: mobile collapses sidebar behind a menu button; no horizontal scroll | glance on a phone-width window |
**Minimum human visual confirmation: C6 (one status change with a reason), plus one look at the dashboard, calendar and licence badges.** Everything else is covered by SQL or CI.
Live tile-vs-register equality (optional single query, SQL Editor): `select (select count(*) from public.v_compliance_instance where due_state='overdue') as overdue_rows;` should equal the Overdue tile.


## Follow-up migrations 0023 (D-001), 0024 (F-1), 0025 (F-2) — live verification
Code-complete and verified on PostgreSQL 16/17 in CI. After they deploy to `bfcl-hrc-dev`, the **only** live step is: run `supabase/tests/live_gate.sql` (expects 25 migrations, 45 tables, 5 views, 20 permissions, OVERALL PASS). Then, optionally, the single consolidated check `supabase/dev-samples/live_followup_check.sql` (read-only).
The modular engine files 01/04/05/06 and `uat_rule_change.sql` require migration 0025 (they use the partial idempotency key).


## PHASE 6 BASELINE CLOSED — 2026-10-03
LIVE `bfcl-hrc-dev` (PostgreSQL 17, owner-reported): `live_gate.sql` OVERALL PASS (25/25 migrations, 45 tables, 5 views, 20 permissions, 5 roles, audit 0, anon exposure 0, 24/24 functions) and `live_followup_check.sql` 15/15 PASS. D-001, F-1, F-2 live verified. Full detail: `docs/LIVE_VERIFICATION.md`. The only remaining manual items are the optional visual confirmations listed under "Browser UAT C1–C13".


## Master Data Administration + Import — LIVE VERIFIED (2026-10-03)
LIVE `bfcl-hrc-dev` (PostgreSQL 17, owner-reported): `live_gate.sql` OVERALL PASS (31 migrations, 48 tables, 12 views, 22 permissions, audit 0) and `live_admin_check.sql` 14/14 PASS. Migrations 0026–0031 are hash-locked. Browser-level behaviour of the admin and import screens is covered by CI (44 headless checks, 224 unit/component tests); a human walk-through on the live site remains optional.

## Job Monitor live verification (migration 0032)
1. SQL Editor: run `supabase/tests/live_gate.sql` (expect 32 migrations, 48 tables, 14 views, 22 permissions, 0 audit violations), then `supabase/dev-samples/live_job_monitor_check.sql` (expect OVERALL PASS).
2. Sign in as SUPER_ADMIN → Administration → Job Monitor. Expect seven jobs, the “schedules are proposals / scheduler off” notice, and “No runner yet” on the four jobs without a runner.
3. Open a job → Disable without a reason: expect “A reason is required”, nothing changes. With a reason: expect disabled; then Enable again with a reason.
4. SQL Editor (read-only): `select at, table_name, action, reason from audit_log where table_name = 'job_definition' order by at desc limit 5;` expect rows with your reasons.
5. Sign in as a user with `job.read` but not `job.manage` (e.g. a role granted only `job.read`): the screen lists jobs and runs but shows no Disable/Enable controls; a direct call to `job_set_enabled` is refused.
6. Sign in as a user without `job.read` (e.g. VIEWER): no Job Monitor menu entry; the route shows no access.
Do not enable `pg_cron`. Report each step as PASS/FAIL.

LIVE `bfcl-hrc-dev` (PostgreSQL 17, owner-reported 2026-10-04): migration 0032 (Job Monitor) verified — `live_gate.sql` OVERALL PASS, `live_job_monitor_check.sql` OVERALL PASS, Job Monitor UI checks passed (reason mandatory, audit written, `job.read` cannot modify). Migration 0032 is hash-locked.

## Users / Roles / Permissions / Scope live verification (migration 0033, after deployment)
1. SQL Editor: run `supabase/tests/live_gate.sql` (expect 33 migrations, 48 tables, 17 views, 23 permissions, audit 0), then `supabase/dev-samples/live_user_admin_check.sql` (expect OVERALL PASS, 12 checks).
2. As SUPER_ADMIN open Administration → **Roles & Permissions**. Open a custom or system role, change one permission, save without a reason (expect “A reason is required”), then with a reason (expect saved; the History tab shows the grant/removal with the reason).
3. Try to remove `role.admin` from SUPER_ADMIN: expect the red “removes an administrative permission” note and, on save, a confirmation dialog (self-lockout). **Cancel** it. (Do not confirm on live: this would remove your own access.)
4. **Users** → open another user → Roles tab: assign/remove a role with a reason; History/Scope history shows it.
5. Users → Scope tab for a test user: choose an entity (or location) and a department, enter a reason, “Replace scope”. “Current access” text shows the effect; Scope history shows granted rows. Choose only a department: expect “A department only narrows…”.
6. Department scope, as the test user (signed in separately): obligations whose Compliance Master has a **Responsible department** are visible only if the user holds that department; obligations with no responsible department follow entity/location only; Location / Compliance Masters stay visible.
7. As a user with `user.admin` but not `role.admin`: can invite and set scope/status, cannot change roles (Roles tab read-only; Roles & Permissions has no editing).
8. Try to disable the only remaining `role.admin` holder via a second SUPER_ADMIN test user only if one exists; otherwise rely on the SQL suite (the guard is covered there).
Report PASS/FAIL per step. Do not enable `pg_cron`.

LIVE `bfcl-hrc-dev` (PostgreSQL 17, owner-reported 2026-10-04): migration 0033 verified — `live_gate.sql` and `live_user_admin_check.sql` OVERALL PASS; Users/Roles/Permissions/Scope UI and department scope verified; self-lockout confirmation shown and cancelled. Migration 0033 is hash-locked.

LIVE `bfcl-hrc-dev` (PostgreSQL 17, owner-reported 2026-10-04): migration 0034 verified — `live_gate.sql` and `live_owner_fallback_check.sql` OVERALL PASS; Alert Rules → Owner fallback shows Configured (v1) with Head HR; no live recipients changed. Migration 0034 is hash-locked.
