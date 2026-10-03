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
| `uat_rule_change` row "already-generated obligations keep v1" | future untouched obligations keep the old rule | future untouched (no human action) obligations are superseded to the new rule; actioned/completed stay pinned | F-2 |
Anything else that is not PASS is a **new** defect: paste it verbatim, it goes into `docs/qa/DEFECT_LOG.md` unaltered, and sample data is never edited to hide it.

## Evidence capture sheet (send back, one block per script)
`script name` · timestamp · every result row exactly as shown (or a screenshot) · for the engine demo, run 1 and run 2 separately.
