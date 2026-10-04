# Live verification evidence — `bfcl-hrc-dev` (Phase 6)

**Status: PHASE 6 BASELINE CLOSED (2026-10-03) — migrations 0001–0025 live-verified on `bfcl-hrc-dev`, PostgreSQL 17; D-001, F-1 and F-2 live verified.** Browser UAT C1–C13 and the Part-3 scripts are tracked below.
Evidence is labelled by source. **Live (owner-reported)** = results the owner ran in the Supabase SQL Editor of `bfcl-hrc-dev` and reported to Claude (Claude cannot reach the live project, so these are transcribed from the owner's reports, not independently observed). **CI/local** = automated PostgreSQL 16 and 17 runs of the same files against a throwaway database. The two are never mixed.

## Gate 1 — deployment — LIVE (owner-reported), PASS
| Check | Live result |
|---|---|
| `supabase/tests/live_gate.sql` | **OVERALL PASS** |
| migrations applied | 22 |
| `public` application tables | 45 |
| views | 4 |
| permissions | 20 |
| roles | 5 |
| scheduled-job definitions | 7 |
| numbering rules | 11 |
| `security_audit.sql` | 0 violations |
| dev SUPER_ADMIN | active, linked |
| `system_config environment.name` | `development` |
| `pg_cron` | OFF |

## Gate 2 — samples and engines (DEV, synthetic) — LIVE (owner-reported), PASS
| Step | Script | Live result |
|---|---|---|
| Load samples | `sample_compliance.sql` | `sample_compliances = 3`, `sample_licences = 3`, `obligations_now = 0` |
| Engine 01 | `uat_engine_01_generator.sql` | PASS (obligations created) |
| Engine 02 | `uat_engine_02_idempotency.sql` | PASS — second wrapper call refused; identical direct run inserted 0; 0 duplicate keys |
| Engine 03 | `uat_engine_03_applicability.sql` | all PASS (no quarterly obligation at SAMPLE-LOC-B) |
| Engine 04 | `uat_engine_04_exceptions.sql` | all PASS (detection, second detection raised 0, one active exception per key) |
| Engine 05 | `uat_engine_05_auto_resolution.sql` | all PASS (auto-resolution; evidence-missing behaviour) |
| Engine 06 | `uat_engine_06_alerts.sql` | all PASS including alert generation (routing existed on dev; D-001 INFO did **not** occur live) |
| Engine 07 | `uat_engine_07_job_log.sql` | all 3 engine job runs PASS |
| Engine 08 | `uat_engine_08_overall.sql` | 12 PASS, 0 FAIL, 0 INFO, **OVERALL = PASS**; SAMPLE obligations = 17; notifications = 3 |

Second-pass requirement: accepted by the owner on the strength of the live idempotency proofs in files 02, 04 and 06 (identical re-execution inserted/raised 0) plus the automated two-pass runs below. Exact timings and row counts were not transcribed.

## CI / local (NOT live) — PostgreSQL 16 and 17, throwaway database
| What | Result |
|---|---|
| `db-test.sh`: 22 migrations + all SQL suites + security audit + 3 concurrency checks | PASS (CI run 15, commit `a38e669`, PG 16 and 17 jobs) |
| Live gate on a pristine DB | OVERALL PASS, 19 PASS |
| Modular engine runner 01–08, two full passes, each file also run alone | PASS; second pass created no obligations/notifications; 08 OVERALL PASS; also PASS with no users (alerts INFO = D-001) |
| `uat_scope_check.sql`, `uat_evidence_fixture.sql`, `uat_backdate_exception.sql`, `uat_rule_change.sql` | PASS in `db-test.sh` (scope: nothing leaks across locations; evidence: all five states; ageing: 0-7/8-30/31-90/90+; rule change: v1 retired/v2 active with reason, old obligations keep the 15th, new period uses the 20th) |
| Sample removal | leaves nothing behind |
| Web: typecheck, lint, 127 unit/component tests, build, 23 headless-browser checks | PASS |

## Hash-lock — recorded
`supabase/migrations.lock` now holds the SHA-256 of **all 22** migrations (0001–0013 unchanged, 0014–0022 added). Enforced by `scripts/validation/check-frozen-migrations.sh` (first step of `npm run test:db`, therefore of CI) and proven to bite by `scripts/validation/test-frozen-lock.sh` (edit / delete / insert-inside-range each fail). See `docs/FROZEN.md`.

## Still live-only
See "Remaining live-only checks" in `docs/UAT_PHASE6_RUNBOOK.md` (one consolidated list).


## FINAL LIVE GATE — migrations 0001–0025 — LIVE `bfcl-hrc-dev`, PostgreSQL 17 (owner-reported, 2026-10-03)
`supabase/tests/live_gate.sql` — **OVERALL = PASS, 0 FAIL**
| Check | Live result |
|---|---|
| migrations applied / exact versions 0001–0025 | 25/25, no gaps — PASS |
| security audit violations | 0 — PASS |
| public tables / views | 45 / 5 — PASS |
| permissions / roles | 20 / 5 — PASS |
| scheduled job definitions / numbering rules / active alert defaults | 7 / 11 / 3 — PASS |
| compliance + exception statuses / RISK values | 9 / 4 — PASS |
| SUPER_ADMIN permissions | 20 — PASS |
| tables without forced RLS / anon-readable tables / extensions in public | 0 / 0 / 0 — PASS |
| required functions present | 24/24 — PASS |
| `my_access()` anon-callable / engines API-callable | false / false — PASS |
| PostgreSQL | 17 |
| dev admin | active, `scope_all = true`, linked |
| environment | development |
| instances / exceptions / licences stored (information) | 17 / 11 / 3 |

`supabase/dev-samples/live_followup_check.sql` — **all 15 checks PASS, OVERALL = PASS**
0023 D-001 routing/unroutable implementation; System Health unroutable visibility; 0024 applicability scope; Location Master remains global; coverage scope; 0025 `human_touched_at`/supersession; partial unique idempotency index; superseded status; reconciliation/report functions; activation triggers reconciliation; registers/evidence exclude superseded; no duplicate live keys; `pg_cron` not installed.

| Item | Status |
|---|---|
| D-001 (migration 0023) | **LIVE VERIFIED** |
| F-1 (migration 0024) | **LIVE VERIFIED** |
| F-2 (migration 0025) | **LIVE VERIFIED** |
| `pg_cron` | not installed (scheduling OFF) |
| Migration lock | 0001–0025 hash-locked; future fixes start at migration 0026 |


## LIVE VERIFIED — migrations 0026–0031 (Master Data Administration + Generic Import Framework) — LIVE `bfcl-hrc-dev`, PostgreSQL 17 (owner-reported, 2026-10-03)
| Check | Live result |
|---|---|
| `supabase/tests/live_gate.sql` | **OVERALL = PASS** |
| migrations applied | 31 |
| public application tables / views | 48 / 12 |
| permissions | 22 |
| security audit violations | 0 |
| `supabase/dev-samples/live_admin_check.sql` | **OVERALL = PASS** — checks 1–14 all PASS (master identity guard, rule-version/applicability RPCs, read models, coverage view, LOV/status/settings guards, protected values, system statuses, evidence-requirement configuration, alert-rule views, import tables with RLS forced, import functions, generic reference templates, import permissions held by SUPER_ADMIN, `pg_cron` information row) |
| `pg_cron` | not installed (scheduling OFF) |

Migration lock: `supabase/migrations.lock` now holds the SHA-256 of **all 31** migrations (0001–0025 unchanged, 0026–0031 added, no migration content modified). New schema work starts at migration 0032.

## LIVE VERIFIED — migration 0032 (Job Monitor) — LIVE `bfcl-hrc-dev`, PostgreSQL 17 (owner-reported, 2026-10-04)
| Check | Live result |
|---|---|
| `supabase/tests/live_gate.sql` | **OVERALL = PASS** (32 migrations, 48 tables, 14 views, 22 permissions) |
| `supabase/dev-samples/live_job_monitor_check.sql` | **OVERALL = PASS** |
| Job Monitor screen (live UI) | page loads |
| Enable / disable | reason is required; audit row written |
| `job.read` without `job.manage` | cannot modify jobs |
| `pg_cron` | not installed; nothing scheduled |

Migration lock: `supabase/migrations.lock` now holds the SHA-256 of **all 32** migrations (0001–0031 unchanged, 0032 added, no migration content modified). Scheduler schedules are approved (D-036) but NOT enabled; rollout gates are in docs/CRON_PROPOSAL.md.

## LIVE VERIFIED — migration 0033 (Users, Roles, Permissions, Scope + Department Scope) — LIVE `bfcl-hrc-dev`, PostgreSQL 17 (owner-reported, 2026-10-04)
| Check | Live result |
|---|---|
| `supabase/tests/live_gate.sql` | **OVERALL = PASS** (33 migrations, 48 tables, 17 views, 23 permissions) |
| `supabase/dev-samples/live_user_admin_check.sql` | **OVERALL = PASS** |
| Users / Roles / Permissions / Scope UI | verified live |
| Department scope | verified live |
| Scope changes | reason required; audited |
| Self-lockout confirmation | appeared and was CANCELLED; no admin access removed |
| `pg_cron` | not installed; nothing scheduled |

Migration lock: `supabase/migrations.lock` now holds the SHA-256 of **all 33** migrations (0001–0032 unchanged, 0033 added, no migration content modified). New schema work starts at migration 0034.
