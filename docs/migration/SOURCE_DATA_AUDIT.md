# Source Data Audit — STATUS: **INCOMPLETE / BLOCKED — no source files supplied**

> Last checked: 2026-10-03 (end of Phase 6 build) — `/mnt/user-data/uploads`, `/mnt/attach`, `data/source/` all empty. Every section below stays marked incomplete until the workbooks are uploaded; nothing may be imported or mapped before every workbook and every worksheet (including hidden/utility sheets) has been inspected.

Inspected on 2026-10-03: the repository (empty), `/mnt/user-data/uploads`, `/mnt/attach`, `/mnt/user-data/working` and a filesystem search for
`*.xlsx|xls|xlsm|csv` — **no workbooks found**. Nothing below is derived from data; no sheet, column, formula, error or duplicate is claimed.

**Needed from BFCL:** the workbooks named in the brief (Liaison with ESIC; GRC/Grievance Register; Government Liaison; Disciplinary Action; Labour Supply / Contractor Bills; Contractor Compliance HASP; Plant Visit) placed in the repo's `data/source/` (git-ignored) or the session uploads, plus any employee/contractor master lists.

## Audit checklist (items 1–26 of the brief) and how each is satisfied
| # | Item | Source | State |
|---|---|---|---|
| 1–2 | files, worksheets inspected | profiler `profile.json` | pending files |
| 3 | business purpose per sheet | human review of profile | pending |
| 4 | fields & types | profiler (kinds, blanks, distinct) | pending |
| 5–7 | formulas, broken formulas, `#NAME?`/`#REF!` etc. | profiler (formula list, cached error cells, cross-sheet refs) | pending |
| 8–11 | duplicates, inconsistent dates/statuses, missing keys | profiler (duplicate rows/values, mixed date/text, distinct status values) | pending |
| 12–16 | master / transaction / calculated / configurable / historical-only classification | analyst judgement on profile | pending |
| 17–18 | source→target mapping, cross-module relations | after classification | pending |
| 19–21 | target tables, config tables | see `DATA_MODEL.md` (proposal) | **proposal only**, to be revised |
| 22 | business rules | requirements in brief; legal rules must come from BFCL (req. 79) | partially captured |
| 23–26 | dashboard IA, dependencies, order, risks | `IMPLEMENTATION_PLAN.md`, below | done (provisional) |

## Provisional dashboard information architecture (from the brief, not from data)
Executive (overall %, open/overdue, critical exceptions, next-30-day, risk exposure, exception ageing) → drill to Compliance register; Contractor (score, holds, financial exposure) → Contractor/Bill; Licences (expiry buckets); Cases (GRC SLA, ESIC ageing, disciplinary ageing, liaison follow-ups, CAPA) → each register. Every tile must drill to a filtered, server-paginated list.

## Risks identified so far
1. **No source data** — mapping, key definitions (employee code, contractor id, invoice uniqueness) and duplicate rules cannot be validated; any table built before the audit may need rework.
2. Legal applicability/deadlines cannot be invented; compliance master content must be supplied/approved by BFCL.
3. Supabase/Google/Cloudflare access not provided; Drive/Gmail integration untestable until then.
4. Google sign-in domain restriction needs BFCL's Workspace domain(s) (D-008).
5. Supabase default grants can silently expose tables (found and mitigated, D-003).
