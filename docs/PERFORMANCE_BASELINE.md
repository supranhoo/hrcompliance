# Performance baseline (synthetic data)

**Status:** measured locally on synthetic data. Not a production figure. Browser/API (network, PostgREST, rendering) timing was **not** measured: it needs a live login, which this environment does not have. Re-run on `bfcl-hrc-dev` before PROD.

## Reproduce
`scripts/perf/run.sh 30` builds a throw-away database `bfcl_perf` (all migrations + `scripts/perf/seed.sql`) and runs `scripts/perf/bench.py`, which writes `scripts/perf/results.md`. Deterministic seed; queries run as role `authenticated` with a JWT subject, so RLS applies exactly as in the app.

Dataset: 4 entities, 24 locations, 8 departments, 60 compliance masters, 10,080 obligations (instances), 2,000 licences, 25,000 exceptions, 21 users (one all-locations, one scoped to 1 entity + 2 departments).
Environment: PostgreSQL 16.14, shared_buffers 128 MB, work_mem 4 MB, warm cache, same host (no network). 30 timed runs after 2 warm-ups; median / p95 / min / max.

## Finding (evidence before any change)
No index was missing. `EXPLAIN (ANALYZE)` showed the time inside row-level-security predicates: `app.has_permission()` and `app.scope_ok()` (+ department lookups) were called once per row. Sequential scans occurred only on tiny tables (`location`, `compliance_master`) and on `exception` for an unfiltered first page. No index was added.

Fix: migration `0039_rls_policy_performance` evaluates permission and scope once per statement (InitPlan) and compares against the user's scope arrays. Semantics are unchanged and proven by SQL suite 64, which compares RLS-visible rows with the original predicate for 12 user profiles across obligations, exceptions, licences and applicability.

## Before / after (median ms)
| Query | Before 0039 | After 0039 |
|---|---:|---:|
| Management dashboard, all locations | 1635 | 424 |
| Management dashboard, scoped user | 1679 | 239 |
| Management dashboard, one location | 91 | 28 |
| Compliance Register first page | 185 | 11 |
| Compliance Register count | 177 | 6 |
| Register filtered (overdue, one location) | 22 | 13 |
| Register text search | 222 | 46 |
| Register first page, scoped user | 192 | 17 |
| Exceptions first page | 547 | 11 |
| Exceptions filtered | 29 | 1.4 |
| Performance report by month / by location | ~127 | 141 / 136 |
| Licence Pipeline report | 13.6 | 1.4 |
| Export 200-row page | 205 | 26 |
| Export to the 10,000-row cap (50 pages) | 12,200 total | 2,992 total |

"Before" used 3 runs; "after" 30 runs (full table incl. p95 in `scripts/perf/results.md`). The performance report did not improve (it is invoker-rights aggregation over all instances; ~140 ms at 10k rows); its scoped variant is 24 ms.

## Remaining observations (not acted on)
- Management dashboard for an all-locations user is ~420 ms at 10k obligations; acceptable for a dashboard, but it scales with obligation count. Revisit only if live timing shows a problem.
- Export uses OFFSET paging; the last of 50 pages costs 266 ms. Acceptable under the 10,000-row cap; keyset paging only if the cap rises.
- Text search uses `ilike` scans (46 ms); a trigram index is a candidate only if live data volume makes it slow.
- Browser/API timing, concurrent users and production hardware are unmeasured.
