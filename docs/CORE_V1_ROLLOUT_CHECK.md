# Core Compliance V1 — production rollout check (Track A, reassessed 2026-10-05)

**Scope:** only what stands between the **current core** (compliance masters, applicability, generator, calendar, evidence, exceptions, alerts, licences, dashboards/reports/export, administration — migrations 0001–0039, live-verified on DEV) and production. **GRC, Liaison, Contractor, Plant Visit and Disciplinary are not prerequisites** and are not listed. Shared dependencies are flagged. Decisions: group 8 of `docs/OWNER_DECISION_PACK_PHASE4.md`; detail: `docs/PRODUCTION_READINESS.md`, `docs/RUNBOOKS.md`, `docs/UAT_PHASE6_RUNBOOK.md`.
Classes: **BLOCKER** (cannot go live without it and nothing can start it now) · **REQUIRED BEFORE GO-LIVE** (must be done, can be prepared in parallel) · **MAY FOLLOW AFTER GO-LIVE**.

| # | Item | Current state | Class | Notes |
|---|---|---|---|---|
| 1 | PROD environment (separate Supabase project, Cloudflare production project/domain, promotion pipeline from the locked migrations) | only `bfcl-hrc-dev` exists; the live deploy branch is the feature branch | **BLOCKER** | CORE-01; deployment workflow plan exists (`DEPLOYMENT_WORKFLOW.md`), nothing created |
| 2 | Backup / point-in-time recovery and a **proven** restore | **UNPROVEN** — never test-restored | **BLOCKER** | CORE-02; `RUNBOOKS.md` §9 template only |
| 3 | Production Google OAuth client, redirect URLs, secrets custody | DEV login only | **BLOCKER** | CORE-03; needs BFCL Google Cloud owner |
| 4 | Real compliance masters/data (obligations, applicability, evidence rules, owners) | only synthetic samples; no compliance workbook was supplied; legal content must come from BFCL | **BLOCKER** | CORE-04 |
| 5 | Evidence file storage (Drive `NOT_CONFIGURED`; upload disabled) | not configured | **REQUIRED BEFORE GO-LIVE** if evidence upload is part of go-live (else link-only interim) | CORE-06; **shared with GRC attachments (GRC-16/0040)** |
| 6 | User / role / scope setup, role-permission matrix, responsible department on each compliance master | defaults provisional | **REQUIRED BEFORE GO-LIVE** | CORE-05; department assignment strongly affects visibility |
| 7 | UAT with real data (UAT runbook C1–C12 + defect log) | runbook ready, not run on production-like data | **REQUIRED BEFORE GO-LIVE** | needs 4 and 6 first |
| 8 | Manual accessibility testing (checklist) | not performed — PROD gate | **REQUIRED BEFORE GO-LIVE** | `ACCESSIBILITY_CHECKLIST.md` |
| 9 | Operations/support: named support owner, incident contacts, monitoring/uptime alerting choice, runbook drills | runbooks drafted; drills need PROD | **REQUIRED BEFORE GO-LIVE** | CORE-11 |
| 10 | Scheduler decision: production `UNROUTABLE_ESCALATION` recipients configured, routing validation clean; gates in `CRON_PROPOSAL.md` | schedules approved (D-036), `pg_cron` OFF | decision + recipients **REQUIRED BEFORE GO-LIVE**; **enabling** `pg_cron` **MAY FOLLOW** (manual daily runs until gates met) | CORE-08 |
| 11 | Production security checks: `live_gate.sql` and security audit on PROD (0 violations), headers verification of the production domain, dev-only Super Admin fallback off | tooling exists (`Verify DEV Deployment` workflow can be pointed at PROD) | **REQUIRED BEFORE GO-LIVE** | go-live tasks 1–2, 5 |
| 12 | DEV browser/API timing with a real authenticated session (separate from DB timing) | not yet measured | **REQUIRED BEFORE GO-LIVE** (quick) | `PERFORMANCE_BASELINE.md` |
| 13 | Retention policy for audit/export log/evidence/notifications | not defined | **REQUIRED BEFORE GO-LIVE** as a recorded decision (even "keep") | CORE-09; no value proposed |
| 14 | Go-live acceptance criteria and sign-off owner | not defined | **REQUIRED BEFORE GO-LIVE** | CORE-11 |
| 15 | Email delivery for alerts (Gmail/Workspace) | `NOT_CONFIGURED`; in-app notifications work | **MAY FOLLOW** unless email alerts are a go-live requirement | CORE-07; shared with Disciplinary email decision |
| 16 | Four job runners (`due_status_refresh`, `licence_expiry_detection`, `communication_followup`, `housekeeping`) | disabled definitions (0035) | **MAY FOLLOW** | behaviour not agreed |
| 17 | Report layouts/targets/RAG, XLSX/scheduled reports | not defined | **MAY FOLLOW** | D-042/043 |

**Verdict:** the core is functionally complete and live-verified on DEV; going live is gated by environment, backup proof, production OAuth and real compliance data (**blockers 1–4**), then the "required" items. None of the module-expansion tracks is on this list, except the shared file-storage decision (5).
