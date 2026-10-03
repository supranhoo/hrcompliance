# Live verification evidence — `bfcl-hrc-dev` (Phase 6)

**Status: BASELINE ACCEPTED (2026-10-03) for migrations 0001–0022 and the modular engine UAT.** Browser UAT C1–C13 and the Part-3 scripts are tracked below.
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
