# Register export (migration 0036)

Every register has an **Export** button when the user holds `report.export` (granted by default to SUPER_ADMIN and HEAD_HR; change it on Roles & Permissions).

- **What is exported:** the register's current server query (same filters from the URL, search and sort), read page by page through the normal RLS-protected view. An export can never contain a row the user cannot already see (role permissions AND entity/location/department scope).
- **Limit:** 10,000 rows per export. If more match, the file holds the first 10,000, the toast says so and the log marks it `limit reached`; narrow the filters to export the rest.
- **Columns:** the register's table columns that have a plain field and a text header (computed/visual columns are skipped).
- **Format:** CSV, UTF-8 with a byte-order mark (opens correctly in Excel), RFC 4180 quoting. **Formula injection is neutralised**: text starting with `=`, `+`, `-`, `@`, tab or carriage return is prefixed with an apostrophe; real numbers are untouched.
- **Logged, fail-closed:** the screen writes an `export_log` row first (who, register, filters, row count, truncated) through `export_record`; if that fails nothing is downloaded. The log is append-only through the API.
- **Export History** (Administration): each person sees their own exports; holders of `audit.read` see everyone's.
- **Not covered yet:** XLSX, scheduled/emailed reports and report layouts. They need agreed report definitions from BFCL; the CSV export is generic.

## Reports (migration 0037)
**Reports** (Compliance menu) offers two read-only reports over the same scope-controlled data as the registers (SECURITY INVOKER functions: role permission AND entity/location/department scope apply):
- **Compliance performance** — `report_compliance_performance(dimension, from, to)`: obligations due in the period grouped by month, location, responsible department, category, risk level, domain or owner; completed / on time / late / overdue / not yet due, and the on-time % and compliance % (same definitions as the dashboard; totals are recomputed from counts, never averaged). Dimensions are a fixed whitelist; not-applicable and superseded obligations are excluded.
- **Licence expiry pipeline** — `report_licence_pipeline(months)`: active licences with an expiry date by month of expiry and licence type, with "already expired" separate (6–60 month horizon).
Both can be exported with the same permission and logging as registers (`report.export`).
No report layouts, targets or thresholds are defined here: those need BFCL's agreed report definitions.

## Management dashboard (migration 0038)
The Executive Dashboard opens on the **Management view**; the original dashboard is kept unchanged on the **Detailed view** tab.
- **Filters** (kept in the URL, so a view can be shared): entity, location, department (the master's responsible department, D-038) and a period (last 3/6/12 months, year to date = calendar year, or custom dates). No financial-year rule is assumed.
- **Tiles:** Total applicable (due in the period), Due this month, Overdue (all periods), Critical (open at the highest level of the RISK list, by sort order — not a hardcoded name), Open exceptions (with the count at the highest SEVERITY), Licences expiring (within the longest `licence.expiry_thresholds` value). Compliance % and on-time % are shown as text, never as a coloured status: **no targets or RAG thresholds are defined** (the earlier green/amber/red on the detailed view's compliance tile was removed for the same reason).
- **Panels:** compliance trend by due month (stacked: on time / late / overdue / not yet due, with an accessible table), risk distribution, location and department performance, upcoming 30 days grouped by date, critical exceptions (oldest first) and exception ageing.
- **Colour:** red/amber only for overdue, late and critical exceptions; everything else is neutral/primary.
- **Drill-down:** every tile and row links to the existing registers/reports and carries entity / location / department where the register supports it (licences have no department; the dashboard says so).
- **Security:** `management_dashboard()` runs as the caller over the scope-controlled views, so role permission AND entity/location/department scope apply exactly as on the registers.
