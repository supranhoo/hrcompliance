# Live verification evidence — `bfcl-hrc-dev` (Phase 6)

**Status: NOT YET VERIFIED.** Nothing in this file counts as evidence until the owner pastes results from the live project.
Local/CI results exist (PostgreSQL 16 and 17) but are a different thing from the live project.

## Gate 1 — deployment (run `supabase/tests/live_gate.sql`, paste the whole result)
| Date (UTC) | Run by | OVERALL | FAIL rows | Notes |
|---|---|---|---|---|
| | | | | |

Expected on a correct deployment of migrations 0001–0022: `migrations 22`, versions `20261003000001…22` with no gaps, `audit violations 0`, `tables 45`, `views 4`, `permissions 20`, `roles 5`, `jobs 7`, `numbering rules 11`, `alert rules 3`, `status definitions 8`, `RISK values 4`, `SUPER_ADMIN permissions 20`, RLS un-forced `0`, anon-readable `0`, extensions in public `0`, functions present `20/20`, `my_access` not callable by anon `false`, engines not callable by API `false` → **OVERALL PASS, 19 PASS**.
Information rows: PostgreSQL major version, dev admin status, stored row counts, environment label.

## Gate 2 — samples and engines (DEV only)
| Step | Script | Result | Elapsed (ms) | Row counts | Date |
|---|---|---|---|---|---|
| Label environment | (SQL in `supabase/dev-samples/README.md`) | | | | |
| Load samples | `sample_compliance.sql` | | | masters 3 / rule versions 3 / licences 3 | |
| Engines | `uat_engine_demo.sql` | | gen __ / detect __ / alerts __ | obligations +__ / exceptions +__ / notifications +__ | |
| Scope | `uat_scope_check.sql` | | | | |
| Evidence states | `uat_evidence_fixture.sql` | | | | |
| Ageing | `uat_backdate_exception.sql` | | | | |
| Rule change | `uat_rule_change.sql` | | | | |
| Removal | `remove_samples.sql` then `live_gate.sql` info rows | | | zero SAMPLE rows | |

## Gate 3 — browser UAT (C1–C12)
Results per case are recorded in `docs/UAT_PHASE6_RUNBOOK.md` (tables at the end) and defects in `docs/qa/DEFECT_LOG.md`.

## After the gate passes (engineering does this, not before)
1. `scripts/validation/check-frozen-migrations.sh --freeze 20261003000022` → commit `supabase/migrations.lock` (migrations 0001–0022 become immutable history).
2. Copy the accepted results above into this file and mark the status line **VERIFIED**.
3. Start the master-data UI and generic import framework.
