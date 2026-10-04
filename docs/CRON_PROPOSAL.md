# `pg_cron` schedules — APPROVED by the owner (D-036), NOT ENABLED

`pg_cron` is **off** in `bfcl-hrc-dev`. Nothing here is scheduled. The owner approved these times on 2026-10-03 (daily including weekends; the last four as placeholders only). Scheduling is still blocked by the safeguards below. This document lists the schedules already seeded in `job_definition.schedule_cron` (times are **UTC**) so the owner can approve, change or reject each one. No schedule is activated until the owner approves it in writing.

| Job | Proposed cron (UTC) | Approx. IST | Runner | Notes |
|---|---|---|---|---|
| compliance_generation | `0 1 * * *` | 06:30 | `app.run_compliance_generation(text)` | Creates due obligations. Runs first. |
| due_status_refresh | `15 1 * * *` | 06:45 | none yet | No runner exists; cannot be scheduled. |
| licence_expiry_detection | `30 1 * * *` | 07:00 | none yet | No runner exists; cannot be scheduled. |
| exception_generation | `45 1 * * *` | 07:15 | `app.run_exception_detection(text)` | After obligations exist. |
| alert_generation | `0 2 * * *` | 07:30 | `app.run_alert_generation(text)` | After exceptions, so alerts see them. |
| communication_followup | `15 2 * * *` | 07:45 | none yet | No runner exists. |
| housekeeping | `0 3 * * 0` | Sun 08:30 | none yet | No runner exists. |

## Approval and gates (D-036)
Approved exactly as listed. Rollout gates, all required before any `cron.schedule(...)` call: (1) migration 0032 live-verified; (2) Job Monitor verified live (checklist in docs/UAT_PHASE6_RUNBOOK.md); (3) in production, `UNROUTABLE_ESCALATION` recipients configured and routing validation passing. First rollout: only compliance_generation, exception_generation and alert_generation. The other four stay disabled/unscheduled until runners and tests exist.

## Original questions (answered)
1. Approve or change each time (the order matters: generation → exceptions → alerts).
2. Confirm that only jobs that have a runner are scheduled first (the three above).
3. Confirm the environment: production must not run until `UNROUTABLE_ESCALATION` recipients are configured (D-001).

## Safeguards already in the database
- Every run is idempotent per job and day (`job_run.idempotency_key`); a repeated trigger does not duplicate work.
- Failed runs retry up to `max_attempts` with `retry_backoff_seconds`; `timeout_seconds` bounds a run.
- Jobs can be disabled from the Job Monitor (reason required, audited). Disabling does not stop an in-flight run.
- The Job Monitor shows last run, last success, failures in 24h and a warning when a run succeeded with a problem (e.g. unroutable alerts).

## Not done on purpose
No `cron.schedule(...)` call exists in any migration. Enabling will be a separate, reviewed step after approval.

## Update 2026-10-04 (migration 0035)
The four jobs without a runner (`due_status_refresh`, `licence_expiry_detection`, `communication_followup`, `housekeeping`) are now **disabled definitions**: no runner is invented until the owner agrees the module behaviour and acceptance rules. The placeholder schedules stay recorded here and in `job_definition.schedule_cron`. A database trigger refuses to enable any job that has no runner (Job Monitor, API or SQL), so they cannot be scheduled or switched on by accident. Adding a runner later is a deliberate migration plus tests; only then can the job be enabled and (after the rollout gates) scheduled.
