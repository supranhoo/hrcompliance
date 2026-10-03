# Implementation Plan & Status

| Phase | Scope | Status |
|---|---|---|
| 0 Repo & env | repo, Vite/TS, CI, env | **done locally**; CI workflow written, never executed on GitHub; no Supabase project connected |
| 1 Audit & architecture | source audit, ERD, plan | architecture/ERD/plan **done**; **source audit BLOCKED** (no files) |
| 2 DB foundation | masters, identity, audit, config, RLS | **done locally** (68 checks). Follow-ups: auto-check "every public table has RLS+FORCE+policy"; employee/contractor masters wait for audit |
| 3 App foundation | auth, guard, layout, theme | **started**: auth shell, guard, layout (11 tests). Missing: error boundary, data layer helpers, smart table, form kit |
| 4 Configuration engine | Field/Section/LOV/Rule/Template/SLA/Numbering UIs + evaluator | not started (schema for fields/LOV/rules/numbering exists) |
| 5–13 | masters → compliance → dashboard → contractor → cases → comms → import/reports → ops → UAT/release | not started |

## Next increments (in order)
1. **Receive source workbooks** → run `scripts/migration/profile_workbooks.py`, complete `docs/migration/SOURCE_DATA_AUDIT.md`.
2. RLS meta-test + `job_run`/`app_setting` + system health RPC (finishes Phase 2/12 stubs).
3. Phase 3 completion: error boundary, typed query layer, SmartTable, form kit.
4. Phase 4: LOV Designer → Field/Section Designer → rule evaluator (shared fixtures with `rule_is_valid`).
5. Phase 5 masters shaped by the audit.

## Dependency rule
No contractor, case or import module is started until masters + compliance data model are stable and audited against source data.
