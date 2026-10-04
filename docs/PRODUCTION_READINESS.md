# Production Readiness Gap Report

Status as of 2026-10-04. Evidence: `docs/LIVE_VERIFICATION.md` (migrations 0001–0038 live-verified on `bfcl-hrc-dev`, PostgreSQL 17, and hash-locked), CI (web, PostgreSQL 16 and 17) on every push. Nothing here is a go-live approval; it lists what stands between the current build and production, grouped by who can unblock it.

## 1. Can be completed now (no one else needed)
| Item | State |
|---|---|
| UX hardening audit: every screen at desktop / tablet / 390px phone width, WCAG A/AA scan (axe-core), no horizontal overflow, headings, no script errors | **automated in the browser test (CI)**; findings and fixes in `docs/UX_AUDIT.md` |
| Security response headers (CSP, frame, referrer, HSTS, permissions policy, asset caching) for Cloudflare Pages | `apps/web/public/_headers`, unit-tested; verify once on the real Pages URL |
| Seeded-defaults register refreshed to match what is now configurable | `docs/DEFAULTS_DECISIONS.md` |
| Repeated-request and stale-data review | review in `docs/UX_AUDIT.md`; fixes only where a defect was found |
| Runbooks: backup/restore drill, migration rollback drill, incident contact sheet | to write (templates in `docs/runbooks/`); the *drills themselves* need the production project |
| Performance baseline on a larger synthetic data set (registers, reports, dashboard at 10k–100k rows) | can be scripted against the local database; live timing needs production-sized data |
| Remaining refactors that do not touch business rules (shared page layout, table density) | optional polish |

## 2. Needs the BFCL source workbooks
| Item | Why blocked |
|---|---|
| Source audit, profiling and the source-to-target map (`docs/migration/SOURCE_TO_TARGET_MAP.md` is the template) | files never received |
| Employee master and Contractor master (structure, keys, codes) | shape comes from the audit |
| Real import mappings (the generic import framework, 0031, is live-verified and ready) | needs the audit |
| Data migration plan, trial loads and reconciliation reports against source | needs the audit and mappings |
| Contractor compliance, case management, communications modules | depend on audited masters (dependency rule in `docs/IMPLEMENTATION_PLAN.md`) |
| Real compliance register content: which obligations apply to which sites, evidence per obligation, owners | currently only generic structure and synthetic samples |

## 3. Needs an owner business decision
| Decision | Notes |
|---|---|
| Scheduler rollout: switch `pg_cron` on for the three jobs with runners | schedules are approved (D-036); gates in `docs/CRON_PROPOSAL.md`: production `UNROUTABLE_ESCALATION` recipients configured and routing validation clean |
| `UNROUTABLE_ESCALATION` recipients for production; review of `OWNER_FALLBACK` (seeded as Head HR) | configured on the Alert Rules screen |
| Behaviour and acceptance rules for `due_status_refresh`, `licence_expiry_detection`, `communication_followup`, `housekeeping` | no runners are invented (D-040); disabled until agreed |
| Report definitions: layouts, targets, any traffic-light thresholds, financial-year rule | none are assumed (D-042, D-043) |
| Responsible department on each compliance master (department scope hides department-owned obligations from users without that department) | data entry decision, high impact on visibility |
| Role-permission matrix per BFCL role, who holds `report.export`, `role.admin`, `user.admin`, `config.write` | editable on Roles & Permissions; defaults are provisional (`docs/DEFAULTS_DECISIONS.md`) |
| Alert timing, due-soon days, licence expiry buckets, exception SLA days, evidence file rules | seeded defaults marked UAT-provisional |
| Data retention and evidence retention policy; audit/export log retention | not yet defined |
| Go-live acceptance criteria and sign-off owner | not yet defined |

## 4. Needs external integration or credentials
| Item | Needed from |
|---|---|
| Email delivery (Gmail integration is `NOT_CONFIGURED`; the email channel exists in alert rules but creates nothing until connected) | Google Workspace admin: service account / OAuth, sending address |
| Evidence file storage (Google Drive integration `NOT_CONFIGURED`; evidence upload is disabled in the UI until a store is connected) | Google Workspace admin: Drive / shared drive access; or decision to use Supabase Storage |
| Production Google OAuth client and redirect URLs | BFCL Google Cloud project owner |
| Production Supabase project (separate from `bfcl-hrc-dev`), custom domain, Cloudflare Pages production project and DNS | BFCL account owners |
| Error monitoring / uptime alerting service for the production site | choice and account |
| Backup / point-in-time-recovery plan on the production database | Supabase plan and settings |

## 5. Go-live-only tasks (after 1–4)
1. Create the production Supabase project; apply migrations 0001–latest from the locked history; run `supabase/tests/live_gate.sql` and `security_audit.sql` (0 violations).
2. Set `environment.name` to production (disables the development-only Super Admin alert fallback); bootstrap the first Super Admin with a BFCL-controlled account (never the development bootstrap).
3. Configure `UNROUTABLE_ESCALATION` and review `OWNER_FALLBACK`; require `alert_routing_validation()` to be clean.
4. Load approved master data and (once mapped) migrated data; reconcile counts against source.
5. Configure Cloudflare Pages production build variables (publishable key only), custom domain, headers; run the browser smoke test against the production URL.
6. Enable backups/PITR; perform one restore drill.
7. Final UAT and owner sign-off; freeze; tag the release.
8. Enable `pg_cron` for the three runner jobs only, after the gates in `docs/CRON_PROPOSAL.md`; watch the first runs in Job Monitor.
9. Hypercare period with daily review of System Health, Job Monitor, unroutable alerts and Export History.

## Verified-today summary (not a go-live claim)
Live-verified: identity/RBAC with department scope, compliance engines, alerts and notification centre, master-data administration, generic import framework, user/role/permission administration, Job Monitor, register export with logging, reports, management dashboard. CI: 27 SQL suites on PostgreSQL 16 and 17, unit tests, headless-browser checks including the UX audit.
