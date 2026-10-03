# Synthetic development samples — NOT BFCL data

`sample_compliance.sql` creates a small, **clearly fictional** data set (every code starts with `SAMPLE`) so the dashboard, registers,
calendar, exceptions and alerts can be exercised in the DEVELOPMENT project before real masters are imported.

* Run it in the Supabase **SQL editor** (as `postgres`). Idempotent. It is deliberately **outside** `supabase/seed/` and `migrations/`, so no
  automated process ever applies it.
* **Never run in UAT or production.** Nothing in it is a legal requirement, deadline, authority or applicability.
* Remove it completely with `remove_samples.sql` (deletes only rows whose code starts with `SAMPLE`; the audit log keeps its history by design).
* After loading, the first nightly job run (or the manual calls at the end of the script) generates obligations, exceptions and alerts from it.
