# Operator runbooks (DEV)

Environment: Supabase project `bfcl-hrc-dev` (PG17), Cloudflare Pages, GitHub branch `claude/peaceful-wozniak-gyfjaw`. Never paste secrets/keys into tickets or chat. **Backup/restore is documented but NOT proven (never test-restored); see section 9.** pg_cron stays OFF.

## 1. DEV deployment
1. Push to the live branch. CI (web, PG16, PG17) must be green first; every push containing migrations deploys them to `bfcl-hrc-dev`.
2. In the Supabase SQL Editor run `supabase/tests/live_gate.sql` (expect migration count, 49 tables, 18 views, 24 permissions, audit 0 issues) and the new migration's `supabase/dev-samples/live_*_check.sql` (all PASS).
3. Cloudflare Pages builds `apps/web`; then `node scripts/validation/verify-live-headers.mjs https://<pages-host>`.
4. After live PASS, add the migration to `supabase/migrations.lock` (hash-lock) and push again.

## 2. Migration failure / recovery
- A failed deploy leaves the migration unapplied (each file is transactional). Read the Actions log, fix **forward** in a NEW migration; never edit a locked migration (CI fails).
- If a migration applied but is wrong: write a new migration that corrects it (each has a `-- Rollback:` line describing the manual reverse). Do not drop data without owner approval.
- Check `supabase_migrations.schema_migrations` against the folder to see what is applied.

## 3. User lockout recovery
- Another user with `user.admin` re-activates the user in Users (reason required, audited). Guards: you cannot disable yourself without confirmation (AD002).
- If nobody can sign in: use the Supabase SQL Editor (owner access) to set `app_user.status = 'active'` for the admin and insert an `audit_log` row describing why. Prefer the Users screen whenever possible.

## 4. Last-admin recovery
- The database refuses removing the last `role.admin` (AD001). If it somehow occurs, in the SQL Editor insert a `user_role` row for the SUPER_ADMIN role for a known `app_user`, then record the reason in the audit log. Verify with the Roles screen.

## 5. Failed job investigation
- Admin → Job Monitor: open the failed run (status, error, counts). Fix the cause (usually data/config), then use **Run now** (requires `job.manage` + reason). Runs are idempotent; re-running is safe.
- Only three jobs have runners: compliance, exception, alert generation. The other four are disabled placeholders; do not enable them (the database refuses).
- Scheduling is not enabled (pg_cron OFF); runs happen only on manual trigger until the rollout gates in the owner pack are met.

## 6. Alert routing failure / UNROUTABLE
- An alert with no recipient escalates per D-001 and appears in the Notification Centre as UNROUTABLE. Fix routing in Alert Rules: add an owner/department recipient or configure `OWNER_FALLBACK` and `UNROUTABLE_ESCALATION`. Then re-run alert generation. Production needs `UNROUTABLE_ESCALATION` configured (owner decision).

## 7. Export troubleshooting
- Needs `report.export`. Export History lists every export (who, register, filters, rows, whether the 10,000-row cap was hit). Cap hit → narrow filters.
- Empty/short file: filters and scope apply (RLS); verify the user's scopes. A failed export writes nothing partial (fail-closed).
- Excel shows odd text: cells starting with `= + - @` are deliberately prefixed against formula injection.

## 8. Authentication / Google sign-in failure
- Check Supabase Auth → Providers → Google enabled, redirect URL matches the Pages host, and the user exists in Users with status active (sign-in succeeds but no access if no `app_user` row/role).
- "No access" screen after login = no role or no scope, not an outage. Check the user in Users.
- Browser console CSP errors mentioning supabase.co → compare with `apps/web/public/_headers` `connect-src`.

## 9. Backup / restore (NOT PROVEN)
- Supabase provides managed backups (plan dependent; PITR needs the paid add-on). **No restore has been performed or verified.** Before PROD: enable PITR, take a manual backup, restore into a scratch project, run `live_gate.sql` against it, and record the result and time taken here.
- Schema is reproducible from `supabase/migrations`; data is not.

## 10. Rollback principles
- Roll forward, not back: frozen migrations are never edited; use a new corrective migration.
- Front end: redeploy a previous Cloudflare Pages deployment (instant, schema-compatible only if no breaking migration shipped between).
- Prefer feature-off (disable job/permission) over destructive reversal; every destructive action needs owner approval and a reason in the audit log.
