# Register export (migration 0036)

Every register has an **Export** button when the user holds `report.export` (granted by default to SUPER_ADMIN and HEAD_HR; change it on Roles & Permissions).

- **What is exported:** the register's current server query (same filters from the URL, search and sort), read page by page through the normal RLS-protected view. An export can never contain a row the user cannot already see (role permissions AND entity/location/department scope).
- **Limit:** 10,000 rows per export. If more match, the file holds the first 10,000, the toast says so and the log marks it `limit reached`; narrow the filters to export the rest.
- **Columns:** the register's table columns that have a plain field and a text header (computed/visual columns are skipped).
- **Format:** CSV, UTF-8 with a byte-order mark (opens correctly in Excel), RFC 4180 quoting. **Formula injection is neutralised**: text starting with `=`, `+`, `-`, `@`, tab or carriage return is prefixed with an apostrophe; real numbers are untouched.
- **Logged, fail-closed:** the screen writes an `export_log` row first (who, register, filters, row count, truncated) through `export_record`; if that fails nothing is downloaded. The log is append-only through the API.
- **Export History** (Administration): each person sees their own exports; holders of `audit.read` see everyone's.
- **Not covered yet:** XLSX, scheduled/emailed reports and report layouts. They need agreed report definitions from BFCL; the CSV export is generic.
