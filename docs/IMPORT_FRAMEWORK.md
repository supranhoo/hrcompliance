# Generic Import Framework (migration 0031, `apps/web/src/admin/import/`)

**Standing rule:** the same business data may come from the screens or from a file, and both converge on the *same* tables, triggers, constraints, RLS and audit. An import cannot write
anything the importing user could not enter by hand, because the writes run **as that user** (SECURITY INVOKER) through the real INSERT/UPDATE.

**Scope of this milestone:** the framework only. The templates registered are *generic reference-master structures* (compliance master, licence type, law, authority, department, category,
document type, location, licence). **There is no BFCL source mapping and no business data**; those wait for the source workbooks (docs/migration/*).

## Flow
1. **Template** (`import_template`, read from the database): columns (key, label, type, required, limits, pattern, reference `{table, match}`), natural key for duplicate detection, required write
   permission, row limit. Importable **custom fields** from the Field Designer (`field_definition.is_importable`) are appended automatically as `custom_<key>`.
2. **Download** a blank CSV template (header of friendly labels) and a column guide (shown on screen).
3. **Upload** `.csv` or `.xlsx` (every sheet listed; choose one). The file is parsed in the browser, fingerprinted (SHA-256 of the bytes) and its columns **auto-matched** by name (override per column).
4. **Stage** (`import_stage`): creates batch `IMP-yyyy-nnnnnn` + rows. **Idempotent:** the same file (hash) cannot be staged twice for a template unless the first batch was cancelled.
5. **Validate** (`import_validate`, re-runnable): per row — required, type, range, pattern, reference lookup by code, duplicate **inside the file**, duplicate **in the database** (policy chosen at upload:
   *skip* (warning), *update*, or *error*), and then a **dry run of the real write, rolled back**, so the database's own constraints, triggers (LOV checks, MIME checks, …) and RLS decide.
   Results per row: `valid | warning | error`, action `insert | update | skip`, messages `{column, message}`. Validation writes nothing and consumes no business numbers.
6. **Review**: counts, filters (errors / warnings / valid …), **Download problems (CSV)** with the original values to fix and re-upload.
7. **Commit** (`import_commit`): *all-or-nothing* by default (refused while any row has errors); or *valid rows only* after confirmation. Each target change is audited with reason `Import IMP-…`.
   A committed batch is closed history. **Cancel** (`import_cancel`, reason mandatory) is possible until commit; a cancelled file can be uploaded again.
8. **History** (`/admin/imports`): batches with counters; staged rows are visible only to the person who uploaded them (they may contain data outside others' scope).

## Safety properties (tested in `supabase/tests/56_import_tests.sql`)
Idempotent staging · dry-run parity with the screens (e.g. invalid LOV value, bad MIME type) · RLS parity (an out-of-scope row is refused exactly like in the UI) · no side effects from validation ·
status machine enforced by trigger · batch/file/template immutable · privacy of staged rows · re-commit/re-validate of a closed batch refused.

## Adding a template
Insert an `import_template` row (a migration; the guard trigger checks that every table, column, reference and permission exists). No code is needed; the screens render it. Complex multi-table
imports (e.g. a rule version with evidence) need their own function that calls the same RPCs the screens use — add it as a new migration, never a side door.

## Limits (by design, documented)
Rows are independent (a row cannot reference another row of the same file); up to 5,000 rows/file (template-configurable up to 20,000); files up to 10 MB; dates must be `YYYY-MM-DD` (Excel date cells are converted automatically).
