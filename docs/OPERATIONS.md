# Operations

**Status: design only.** Nothing here is configured or tested yet.

* **Bootstrap first Super Admin** (once per environment, by the project owner in the SQL editor): dev uses `supabase/seed/dev_bootstrap_admin.sql`; UAT/production use the same two inserts with the BFCL Workspace owner's email. The person then signs in with Google.
* **Jobs:** definitions are seeded; runners (Edge Function/pg_cron) must call `app.job_start(job, idempotency_key)` and `app.job_finish(...)` with a server-side key. Implemented/tested in SQL only; no runner exists yet.
* **Backups (to define before go-live):** Supabase PITR/daily backups, a monthly restore drill into a scratch project, exported configuration (`field_definition`, `lov_*`, `rule_definition`, `numbering_rule`…) committed or stored in Drive, Drive folder ownership held by a BFCL service account with a second owner. **No backup is configured or verified today.**
* **Jobs / health (Phase 12):** `job_run` table, Job Monitor and System Health pages. Not started.

## Engines and manual runs (Phase 6)
The engines are SQL functions callable only by `postgres`/`service_role` (SQL editor, Edge Function, `pg_cron`). **Nothing schedules them yet.**
```sql
select app.run_compliance_generation('dev');   -- job 'compliance_generation', one logical run per day
select app.run_exception_detection('dev');     -- job 'exception_generation', one logical run per hour
select app.run_alert_generation('dev');        -- job 'alert_generation', one logical run per day
select * from public.job_run order by started_at desc limit 20;   -- observable: status, attempt, records_processed, error_detail
```
**Scheduling (not done; needs your decision/action):** enable the `pg_cron` extension (Dashboard → Database → Extensions), then e.g.
`select cron.schedule('bfcl-compliance-gen', '15 20 * * *', $$select app.run_compliance_generation('prod')$$);` (times are UTC). Each wrapper is idempotent and logs to `job_run`; a failed run is retried by the next invocation until `max_attempts`.
**Remove synthetic samples:** run `supabase/dev-samples/remove_samples.sql`.

## Synthetic samples and live gate
* `supabase/tests/live_gate.sql` — read-only verification after every deployment (regenerate with `scripts/validation/build-live-gate.sh` whenever `security_audit.sql` changes; CI fails if it is stale).
* `supabase/dev-samples/*` — DEVELOPMENT ONLY synthetic data and demonstrations; they refuse to run unless `system_config environment.name = "development"`.
