# Synthetic development samples — NOT BFCL data

`sample_compliance.sql` creates a small, **clearly fictional** data set (every code starts with `SAMPLE`) so the dashboard, registers,
calendar, exceptions and alerts can be exercised in the DEVELOPMENT project before real masters are imported.

* Run it in the Supabase **SQL editor** (as `postgres`). Idempotent. It is deliberately **outside** `supabase/seed/` and `migrations/`, so no
  automated process ever applies it.
* **Environment guard:** both scripts refuse to run unless `system_config` has `environment.name = "development"` (set it once by hand in the dev project; the one-line SQL is at the top of each script). The live gate shows this label.
* **Never run in UAT or production.** Nothing in it is a legal requirement, deadline, authority or applicability.
* Remove it completely with `remove_samples.sql` (deletes only rows whose code starts with `SAMPLE`; the audit log keeps its history by design).
* Loading is **data only** (masters, rule versions, applicability, licences). Then run `uat_engine_demo.sql`: it executes the generator, exception detector and
  alert engine step by step, prints a PASS/FAIL/INFO table with timings and row counts, and shows idempotency and auto-resolution. It adds three synthetic
  event-based obligations placed on alert offsets so alert generation is demonstrable on any day.
* Synthetic markers: every code starts with `SAMPLE`; names say "SAMPLE"; remarks say "SAMPLE event"; entity `SAMPLE-ENT`, locations `SAMPLE-LOC-A/B`.


**Always run each script as the complete file in one execution.** Running a highlighted fragment in the SQL editor breaks PL/pgSQL (`syntax error at or near ","` from `select ... into a, b` outside a `DO` block) and loses the session temp table. Paste the whole file into an empty tab.

**Live UAT uses the modular runner** `uat_engine_01_generator.sql` … `uat_engine_08_overall.sql` (each small, independent, DEVELOPMENT-guarded, ends with `-- END OF FILE`). `uat_engine_demo.sql` is the single large script kept for CLI/engineering use; the SQL Editor can truncate it.


## Live verification automation (read-only; docs/LIVE_VERIFICATION_AUTOMATION.md)
`setup_ci_verifier.sql` (one-time, by hand, placeholder password; creates the column-whitelisted read-only login `ci_verifier`), `drop_ci_verifier.sql` (revoke/remove), `live_verifier_role_audit.sql` (re-proves the login is still least-privilege; runs first in every workflow run), `live_attachment_check.sql`, `live_org_masters_inventory.sql`. None of these is ever run automatically except the three read-only checks by the manual GitHub workflow.
