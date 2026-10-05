# DEV live verification automation (no manual SQL copy/paste)

**Status: built and tested locally/in CI; NOT YET RUN against bfcl-hrc-dev.** Local/CI evidence is not live evidence. The first live run happens only after the owner confirms the one-time setup below.
Migrations 0001–0040 are unchanged; 0040 stays **unlocked** until both workflows pass on DEV.

## What exists
| Piece | Purpose |
|---|---|
| `.github/workflows/verify-dev-live.yml` — **Verify DEV (live, read-only)** | `workflow_dispatch` only. Runs `live_gate.sql`, `live_attachment_check.sql`, `live_org_masters_inventory.sql` (sanitized summary only). |
| `.github/workflows/verify-dev-storage-smoke.yml` — **Verify DEV storage smoke test** | `workflow_dispatch` only. Synthetic PNG + two synthetic users: A reserve → upload → complete → read; B / anonymous / public URL denied. Never receives a database credential. |
| `scripts/validation/dev-live-verify.sh` (+ `live_verify_report.py`) | The runner: DEV guard → role audit → the three scripts, each in `BEGIN READ ONLY … ROLLBACK`, 30 s statement timeout. |
| `supabase/dev-samples/setup_ci_verifier.sql` | One-time, by hand: creates/rotates the `ci_verifier` login and its exact grants. Placeholder password only. |
| `supabase/dev-samples/live_verifier_role_audit.sql` | Re-proves from the catalogs, as `ci_verifier`, that the role is still exactly what the setup created. First step of every run. |
| `supabase/dev-samples/drop_ci_verifier.sql` | Revoke / remove the login. |
| `scripts/validation/dev-storage-smoke.mjs` | The smoke test (Node, only the publishable key + two synthetic logins). |
| `test-live-verifier.sh`, `test-dev-storage-smoke.mjs`, `test-verification-workflows.sh` (+ `check-verification-workflows.py`) | CI proofs (below). |

## Connection method decision
**Direct PostgreSQL through the Supabase Session pooler (port 5432) as a dedicated read-only login — not the Supabase CLI + project access token.**
* An access token is account-wide (all projects, management API, migrations, API keys); it cannot be scoped to read-only or to one project.
* A database login can be limited by PostgreSQL privileges to exactly what the three scripts read, cannot run migrations, and is checked by the database itself.
* GitHub runners are IPv4-only; `db.<ref>.supabase.co` is IPv6-only, so the **Session pooler** host is used. Copy the exact host from Supabase → **Connect** → Session pooler (never construct it from the region). The login there is `ci_verifier.<project-ref>`.
* Separate PG settings (host/port/user/db/password) instead of one URL: no URL-encoding mistakes, and only the password is secret.

## How the verifier gets global counts over FORCE RLS tables (measured, not assumed)
Every application table has `FORCE ROW LEVEL SECURITY` and policies written for the API roles. A login with plain `SELECT` therefore sees **zero rows**: measured in `test-live-verifier.sh`, `select count(*) from permission` returns 0 without `BYPASSRLS` (25 with it) and the live gate reports 7 false FAILs. The scripts need global facts (permission/role counts, `environment.name`, org masters), so:
* The role has **`BYPASSRLS`, but only over a column whitelist**. `BYPASSRLS` skips row policies; it grants no table access. Everything not granted is `permission denied`.
* **No table-level privilege at all** — only column-level `SELECT` on the 66 columns below. Verified by `live_verifier_role_audit.sql` (check 6: no table-level privilege; check 8: the column set equals the documented list exactly; extra *or* missing columns fail).
* It is `LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION`, owns nothing, is in no role, has no CREATE on any schema or the database, no USAGE on schema `app`/`auth`/`vault` (so internal functions are unreachable), no sequence privilege.
* Defence in depth: `default_transaction_read_only = on`, `statement_timeout 30s`, `lock_timeout 5s`, `idle_in_transaction_session_timeout 60s`, `search_path = pg_catalog`, `CONNECTION LIMIT 3`; the runner wraps each script in `BEGIN READ ONLY … ROLLBACK`, refuses SQL containing `COMMIT/BEGIN/SET SESSION/RESET/\\…`, and every SQL file is a single `SELECT`.

### Exact grants (column-level `SELECT` only)
| Table | Columns | Used for |
|---|---|---|
| `public.permission` | code | permission count |
| `public.role` | id, code | role count, SUPER_ADMIN |
| `public.role_permission` | role_id, permission_code | SUPER_ADMIN holds all; `attachment.admin` holders |
| `public.job_definition` | id | job count |
| `public.numbering_rule` | key | numbering rule count |
| `public.config_definition` | kind, code, status | seeded alert rules |
| `public.status_definition` | module | status definitions |
| `public.lov_set` / `public.lov_value` | id, code / set_id, is_active | RISK values |
| `public.system_config` | key, value | `environment.name` guard (business configuration, never secrets) |
| `public.app_user` | id, status, scope_all, auth_user_id | "dev admin provisioned/active/linked" row — **not** email, name or employee code |
| `public.user_role` | user_id, role_id | same row |
| `public.compliance_instance`, `public.exception`, `public.licence` | id | row **counts** only |
| `public.attachment_target` / `public.attachment` / `public.attachment_access_log` | parent_type / link_status / id | counts and pending count |
| `storage.buckets` | id, public, file_size_limit | private-bucket proof (not `storage.objects`: no object listing) |
| `supabase_migrations.schema_migrations` | version | 40 contiguous migrations |
| `public.entity` | id, code, name, is_active | org inventory (**not** legal name, PAN, GSTIN, CIN) |
| `public.location` | id, code, name, entity_id, is_active | (**not** address, headcounts) |
| `public.business_unit` | id, code, name, entity_id, is_active | |
| `public.unit` | id, code, name, location_id, business_unit_id, is_active | |
| `public.department` | id, code, name, parent_id, is_active | |
| `public.designation` | code, name, grade, is_active | |
| `public.authority` | code, name, authority_type, is_active | (**not** office, address, contact, e-mail, phone) |

Not readable, proven by attempts in `test-live-verifier.sh`: every employee/contractor/medical/disciplinary/grievance/evidence/attachment-content table (all 47 other public tables/views), `app_user.email/full_name`, `entity.pan`, `authority.email`, `storage.objects`; no INSERT/UPDATE/DELETE/TRUNCATE/DDL/CREATE ROLE; `app.*` functions cannot be called; turning read-only off and writing anyway is still denied.

### Changes to existing verification SQL (not migrations)
`information_schema.tables/views/role_table_grants` only show objects and grants **visible to the current role**. A least-privilege login would see none, so "anon has no grants" would pass vacuously and "53 tables" would fail. The checks in `security_audit.sql` (embedded in `live_gate.sql`), `live_gate.template.sql` and `live_attachment_check.sql` now read the catalogs directly (`pg_class`, `pg_class.relacl` via `aclexplode`, `pg_proc`), which every role can see; `to_regprocedure('app.…')` (needs USAGE on `app`) was replaced by a catalog signature lookup. Proven equivalent: output rows identical to the superuser run on the full gate and attachment check, and the old and new audit flag the same planted violations (7 of 7). Frozen migrations are untouched.

## One-time owner actions (nothing runs until you confirm these)
1. **Create `ci_verifier`:** open `supabase/dev-samples/setup_ci_verifier.sql`, replace the one placeholder (`openssl rand -hex 24`), run the whole file in the DEV SQL Editor, then delete the saved snippet. Expected result row: `can_login t`, `superuser f`, `createdb f`, `createrole f`, `replication f`, `bypass_rls t`, `table_non_select_privileges 0`, `role_memberships 0`, `app_schema_usage f`. If it stops with *"cannot create a BYPASSRLS role"* or a *grant* error: **stop and report; do not widen anything and do not use the postgres password.**
2. **Create synthetic users A and B** (Supabase → Authentication → Users → Add user → Create new user, *Auto Confirm*), e.g. `ci-smoke-a@example.test`, `ci-smoke-b@example.test`, random passwords. Email + password sign-in must be enabled (Authentication → Providers → Email); sign-ups can stay off.
3. **Add both in the app (Users) with role VIEWER only**, no scope, no employee mapping. The first sign-in links them (`my_access()` self-link) and sets `last_login_at` on those two synthetic rows — the only non-attachment write the automation causes.
4. **Document type:** an active `document_type` that accepts `image/png` (or has no MIME restriction) must exist. The workflow never creates master data; if none exists it fails with `SETUP REQUIRED: no image/png document type available`.
5. **GitHub → Settings → Environments → `dev-verification`:** *Deployment branches → Selected branches → `claude/peaceful-wozniak-gyfjaw` only.* Optional hardening: add yourself as *Required reviewer* so every run needs an approval click.

   | Variables (`vars`) | Value / source |
   |---|---|
   | `DEV_DB_HOST` | Supabase → Connect → **Session pooler** host (copy exactly) |
   | `DEV_DB_PORT` | `5432` |
   | `DEV_DB_USER` | `ci_verifier.<project-ref>` |
   | `DEV_DB_NAME` | `postgres` |
   | `SUPABASE_URL` | Project Settings → API → Project URL |
   | `SUPABASE_PUBLISHABLE_KEY` | Project Settings → API Keys → **publishable** key (public by design; never the secret/service-role key) |
   | `SMOKE_USER_A_EMAIL`, `SMOKE_USER_B_EMAIL` | the synthetic emails |

   | Secrets | Value |
   |---|---|
   | `DEV_DB_PASSWORD` | the password you put in the setup file |
   | `SMOKE_USER_A_PASSWORD`, `SMOKE_USER_B_PASSWORD` | the synthetic users' passwords |

## Isolation rules (enforced by `check-verification-workflows.py`, run in CI on every push)
* Both workflows: `workflow_dispatch` only, no inputs; job `environment: dev-verification` and `if: github.ref == 'refs/heads/claude/peaceful-wozniak-gyfjaw'`; `permissions: contents: read`; checkout without persisted credentials; only allow-listed actions and a single allow-listed `run` command; no artifacts or caches.
* The live workflow may read only `DEV_DB_PASSWORD`; the smoke workflow only the two synthetic passwords and **no** DB credential (`DEV_DB_USER`, a public variable, is used only to confirm the smoke target is the same project the DB workflow proved to be `development`).
* No other workflow (push / pull request) may reference the environment or those secrets; no `pull_request_target`; no service-role / secret key, access token, JWT or inline-password connection string anywhere in workflows, scripts, docs, samples or the web app.
* `setup_ci_verifier.sql` must keep the placeholder and only column-level `SELECT` grants. 32 deliberate loosenings are proven rejected by `test-verification-workflows.sh`.
* The checks guard the wiring; the real protection is database privileges + READ ONLY + the environment's branch rule.

## What a run produces
* **Job Summary and log only — no artifact.** PASS/FAIL per script, failing checks named with expected/actual, and for the organisation inventory **only**: entity / location / business-unit / unit / department / authority counts and whether GFA, HASP and Common exist (and in which master type). The raw inventory lives in a runner temp directory and is deleted on exit. A detailed inventory is a separate step needing explicit owner approval.
* Exit 1 on any FAIL or N/A (N/A is not acceptable live). Exit 3 if `environment.name` is not `development` (nothing else runs). Exit 4 if the role audit fails (the other scripts are not run).
* Smoke test: `PASS`/`FAIL` per check, tokens masked (`::add-mask::`), nothing secret printed. It leaves one **deactivated** synthetic attachment and one ~70-byte private object — a deliberate 0040 property (no update/delete storage policy, no cleanup job, `pg_cron` OFF). A second run adds another pair.

## Evidence: what is proven where
| Claim | Proven by | Where |
|---|---|---|
| Verifier works with whitelisted columns and equals a superuser run | `test-live-verifier.sh` (real setup file, real login, real runner) | local PG16, CI PG16/17 |
| Verifier cannot read confidential tables / write / create / call internals | same, by attempts | local, CI |
| Runner fails on gate FAIL, public bucket, non-DEV label, role drift, non-verifier login | same | local, CI |
| Smoke test denies B / anonymous / public URL / overwrite and cannot pass vacuously | `test-dev-storage-smoke.mjs` (mock; each removed protection must fail the run) | CI |
| Wiring cannot be loosened silently | `test-verification-workflows.sh` | CI |
| **The real DEV project behaves this way** (BYPASSRLS creatable by the Supabase `postgres` role, grant option on `storage.buckets`, real Storage + RLS) | the first live run | **PENDING (owner confirmation of setup, then run)** |

## Known limits / residual risks (stated, not hidden)
* The Supabase `postgres` role must be allowed to create a `BYPASSRLS` role and grant column privileges on `storage.buckets` and `supabase_migrations.schema_migrations`. Not verifiable from CI; setup stops with a clear message if not.
* Environment secrets are available to any job that names `dev-verification` from the approved branch. The branch rule, the static check and code review protect that; required reviewers on the environment add a human gate.
* `PGSSLMODE=require` encrypts but does not verify the pooler certificate; pin the Supabase CA later if required.
* Actions are pinned by tag (`@v4`, first-party only), consistent with the existing CI.
* The smoke test cannot read `environment.name` through the API as a VIEWER; it ties the target to the project named in `DEV_DB_USER`. Use the same project for both.
* If the `public` schema grants CREATE to PUBLIC on the live project, audit check 9 will report it (the verifier would still be limited to READ ONLY and could not write tables it cannot reach); handle that finding as a platform question, not by widening the role.

## Rotate / revoke
* **Rotate:** re-run `setup_ci_verifier.sql` with a new password, update `DEV_DB_PASSWORD`. Same for the synthetic users' passwords (Supabase Authentication) and their GitHub secrets.
* **Lock out now:** `alter role ci_verifier nologin;` (reversible). **Remove:** run `drop_ci_verifier.sql`, then delete the secret/variables.

## After both workflows pass on DEV
Record the run links and results in `docs/LIVE_VERIFICATION.md` as **owner/live evidence**, then hash-lock 0040 (extend `migrations.lock` through 0040, raise the tamper-test minimum to 40) in a separate commit with full CI.
