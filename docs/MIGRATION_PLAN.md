# Migration Plan

Source files (ESIC liaison, GRC, Government Liaison, Disciplinary, Labour Supply/Contractor Bills, Contractor Compliance HASP, Plant Visit, later workbooks) are **requirement evidence + historical data**, not the target schema.

**Status: no source files received. No profiling, mapping or import has been performed.**

## Process
1. Preserve originals read-only outside Git (`data/source/` is git-ignored; checksum list kept in `docs/migration/`).
2. Profile: `python3 scripts/migration/profile_workbooks.py data/source docs/migration/profile` (all sheets, columns, formulas, error cells, mixed dates, status variants, duplicates).
3. Human review of profile → complete `SOURCE_DATA_AUDIT.md` → agree mapping.
4. Normalise & validate in staging tables (`import_batch/row/error`), idempotent by business key + file checksum.
5. Preview → import to UAT → reconcile counts (source / inserted / updated / duplicate / skipped / error / unmapped) and financial totals → report → production import after authorisation.

## Reconciliation report (template)
| Source file/sheet | Source rows | Imported | Updated | Duplicate | Skipped | Error | Unmapped | Financial total (src vs db) |
|---|---|---|---|---|---|---|---|---|
| _none yet_ | | | | | | | | |
