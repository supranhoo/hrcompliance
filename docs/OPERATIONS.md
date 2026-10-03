# Operations

**Status: design only.** Nothing here is configured or tested yet.

* **Bootstrap first Super Admin** (once per environment, by the project owner in the SQL editor): dev uses `supabase/seed/dev_bootstrap_admin.sql`; UAT/production use the same two inserts with the BFCL Workspace owner's email. The person then signs in with Google.
* **Jobs:** definitions are seeded; runners (Edge Function/pg_cron) must call `app.job_start(job, idempotency_key)` and `app.job_finish(...)` with a server-side key. Implemented/tested in SQL only; no runner exists yet.
* **Backups (to define before go-live):** Supabase PITR/daily backups, a monthly restore drill into a scratch project, exported configuration (`field_definition`, `lov_*`, `rule_definition`, `numbering_rule`…) committed or stored in Drive, Drive folder ownership held by a BFCL service account with a second owner. **No backup is configured or verified today.**
* **Jobs / health (Phase 12):** `job_run` table, Job Monitor and System Health pages. Not started.
