# Phase 1 profiling scripts (read-only)
Ad-hoc, read-only openpyxl scripts used for the Phase 1 source audit (see docs/migration/PHASE1_SOURCE_AUDIT.md). They open the workbooks with `openpyxl` (never save) from a read-only copy under `/tmp/claude-0/src_orig/`.
Paths are hard-coded to that session location; adjust before reuse. The workbooks themselves are NOT in the repository (they contain personal data).
- `inv.py` workbook/sheet inventory (state, dimensions, merged cells, hidden rows/columns, formula counts, tables)
- `dump.py <file> <sheet> [from] [to]` row dump with cached values and formula text
- `grc.py` GRC register profile; `cm.py`, `cm2.py` contractor manpower-cost profile and hidden-sheet reconciliation
