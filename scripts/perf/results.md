# Performance baseline results (SYNTHETIC data)

- PostgreSQL: `16.14 (Ubuntu 16.14-0ubuntu0.24.04.1)`, shared_buffers `128MB`, work_mem `4MB`, local server (no network).
- Data: departments 8; exceptions 25000; licences 2000; locations 24; obligations 10080
- 30 timed runs per query after 2 warm-ups (warm cache). Times are database execution as seen by psql (ms).

| Query | median | p95 | min | max |
|---|---:|---:|---:|---:|
| Management dashboard (admin, all locations, 12 months) | 424.0 | 458.6 | 70.9 | 481.2 |
| Management dashboard (scoped user: 1 entity + 2 departments) | 238.6 | 242.4 | 174.9 | 262.2 |
| Management dashboard (admin, one location filter) | 27.6 | 28.1 | 26.3 | 32.6 |
| Compliance Register first page (25 rows, sorted by due date) | 10.9 | 11.1 | 10.8 | 11.1 |
| Compliance Register total count (exact count the pager asks for) | 6.1 | 6.2 | 5.9 | 6.2 |
| Compliance Register, filtered: overdue at one location | 13.4 | 14.1 | 13.2 | 17.8 |
| Compliance Register, text search (ilike on number/name) | 46.4 | 49.4 | 45.3 | 51.5 |
| Compliance Register first page (scoped user) | 16.9 | 17.4 | 16.7 | 17.9 |
| Exceptions Register first page (25 rows, newest first) | 11.4 | 11.5 | 11.2 | 12.5 |
| Exceptions Register, filtered: open, top severity | 1.4 | 1.5 | 1.2 | 1.5 |
| Compliance Performance report: by month | 140.6 | 155.4 | 10.0 | 158.0 |
| Compliance Performance report: by location | 136.4 | 158.7 | 8.3 | 163.5 |
| Compliance Performance report: by month (scoped user) | 23.7 | 24.3 | 13.4 | 39.0 |
| Licence Pipeline report (12 months) | 1.4 | 1.7 | 1.3 | 2.0 |
| Export: one 200-row page of the Compliance Register | 26.0 | 26.4 | 25.8 | 34.5 |

**Export to the 10,000-row cap** (50 sequential 200-row pages, as the browser fetches them): total 2992 ms, per page median 26.1 ms, last page 266.3 ms (deep OFFSET).

## Plans: sequential scans on large tables

- **Management dashboard (admin, all locations, 12 months)** — Seq Scan on: none
- **Management dashboard (scoped user: 1 entity + 2 departments)** — Seq Scan on: none
- **Management dashboard (admin, one location filter)** — Seq Scan on: `location` (rows removed by filter: location=23)
- **Compliance Register first page (25 rows, sorted by due date)** — Seq Scan on: `location`
- **Compliance Register total count (exact count the pager asks for)** — Seq Scan on: `location`
- **Compliance Register, filtered: overdue at one location** — Seq Scan on: `location` (rows removed by filter: location=23)
- **Compliance Register, text search (ilike on number/name)** — Seq Scan on: `compliance_master`, `compliance_rule_version`, `location`
- **Compliance Register first page (scoped user)** — Seq Scan on: `location` (rows removed by filter: location=380)
- **Exceptions Register first page (25 rows, newest first)** — Seq Scan on: `exception`
- **Exceptions Register, filtered: open, top severity** — Seq Scan on: none
- **Compliance Performance report: by month** — Seq Scan on: none
- **Compliance Performance report: by location** — Seq Scan on: none
- **Compliance Performance report: by month (scoped user)** — Seq Scan on: none
- **Licence Pipeline report (12 months)** — Seq Scan on: none
- **Export: one 200-row page of the Compliance Register** — Seq Scan on: `location`
