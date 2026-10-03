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
