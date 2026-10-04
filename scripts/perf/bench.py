#!/usr/bin/env python3
"""Times the application's real database queries with psql (no driver needed). For each query: N timed runs (server-side execution time as psql \\timing reports it, which includes the
round trip to a local server), median / p95 / min / max; plus EXPLAIN (ANALYZE, BUFFERS) scanned for sequential scans. Runs as the same database roles the app uses: `authenticated` with a JWT subject (RLS applies)."""
import re, statistics, subprocess, sys

url, runs = sys.argv[1], int(sys.argv[2])
def psql(sql, user=None, extra=()):
    pre = ""
    if user: pre = f"select set_config('request.jwt.claim.sub', (select auth_user_id::text from public.app_user where email = '{user}'), false); set role authenticated;\n"
    return subprocess.run(["psql", "-q", "-At", url, *extra], input=pre + sql, capture_output=True, text=True).stdout

def time_query(sql, user):
    script = "".join(f"{sql};\n" for _ in range(runs + 2))              # 2 warm-up runs are discarded
    pre = f"select set_config('request.jwt.claim.sub', (select auth_user_id::text from public.app_user where email = '{user}'), false);\nset role authenticated;\n\\timing on\n\\o /dev/null\n"
    out = subprocess.run(["psql", "-q", url], input=pre + script, capture_output=True, text=True)
    ts = [float(m) for m in re.findall(r"Time: ([0-9.]+) ms", out.stdout + out.stderr)][2:]
    if len(ts) < runs: raise SystemExit(f"query failed: {sql[:80]}\n{out.stderr[:400]}")
    ts.sort(); p95 = ts[max(0, int(round(0.95 * len(ts))) - 1)]
    return statistics.median(ts), p95, ts[0], ts[-1]

def explain(sql, user):
    plan = psql(f"explain (analyze, buffers, costs off, timing off) {sql}", user)
    seq = re.findall(r"Seq Scan on (\S+).*?\n?", plan)
    big = re.findall(r"Seq Scan on (\S+)[^\n]*\n(?:[^\n]*\n)*?\s*Rows Removed by Filter: (\d+)", plan)
    return plan, sorted(set(seq)), big

ADMIN, SCOPED = "perf_admin@perf.test", "perf_scoped@perf.test"
REG = "id,instance_no,compliance_code,compliance_name,location_code,location_name,period_start,period_end,due_date,status,due_state,risk_level,criticality,frequency,evidence_required,days_overdue,days_to_due"
EXC = "id,exception_no,category,severity,description,status,detected_at,due_date,age_days,age_bucket,target_breached,resolution,compliance_instance_id,licence_id,evidence_id"
Q = [
 ("Management dashboard (admin, all locations, 12 months)", "select public.management_dashboard()", ADMIN),
 ("Management dashboard (scoped user: 1 entity + 2 departments)", "select public.management_dashboard()", SCOPED),
 ("Management dashboard (admin, one location filter)", "select public.management_dashboard(null, (select id from public.location where code='PL03'), null)", ADMIN),
 ("Compliance Register first page (25 rows, sorted by due date)", f"select {REG} from public.v_compliance_instance order by due_date asc limit 25 offset 0", ADMIN),
 ("Compliance Register total count (exact count the pager asks for)", "select count(*) from public.v_compliance_instance", ADMIN),
 ("Compliance Register, filtered: overdue at one location", f"select {REG} from public.v_compliance_instance where due_state = 'overdue' and location_code = 'PL03' order by due_date asc limit 25", ADMIN),
 ("Compliance Register, text search (ilike on number/name)", f"select {REG} from public.v_compliance_instance where instance_no ilike '%PCI-00042%' or compliance_name ilike '%Obligation 17%' order by due_date asc limit 25", ADMIN),
 ("Compliance Register first page (scoped user)", f"select {REG} from public.v_compliance_instance order by due_date asc limit 25 offset 0", SCOPED),
 ("Exceptions Register first page (25 rows, newest first)", f"select {EXC} from public.v_exception order by detected_at desc limit 25", ADMIN),
 ("Exceptions Register, filtered: open, top severity", f"select {EXC} from public.v_exception where status in ('open','acknowledged') and severity = 'critical' order by detected_at desc limit 25", ADMIN),
 ("Compliance Performance report: by month", "select * from public.report_compliance_performance('month', date '2025-01-01', current_date)", ADMIN),
 ("Compliance Performance report: by location", "select * from public.report_compliance_performance('location', date '2025-01-01', current_date)", ADMIN),
 ("Compliance Performance report: by month (scoped user)", "select * from public.report_compliance_performance('month', date '2025-01-01', current_date)", SCOPED),
 ("Licence Pipeline report (12 months)", "select * from public.report_licence_pipeline(12)", ADMIN),
 ("Export: one 200-row page of the Compliance Register", f"select {REG} from public.v_compliance_instance order by due_date asc limit 200 offset 5000", ADMIN),
]
out = [f"# Performance baseline results (SYNTHETIC data)\n", f"- PostgreSQL: `{psql('show server_version').strip()}`, shared_buffers `{psql('show shared_buffers').strip()}`, work_mem `{psql('show work_mem').strip()}`, local server (no network).",
       f"- Data: " + "; ".join(f"{a} {b}" for a, b in (l.split('|') for l in psql("select what, count(*) from (select 'obligations' as what from public.compliance_instance union all select 'exceptions' from public.exception union all select 'licences' from public.licence union all select 'locations' from public.location union all select 'departments' from public.department) s group by what order by what").strip().splitlines())),
       f"- {runs} timed runs per query after 2 warm-ups (warm cache). Times are database execution as seen by psql (ms).\n", "| Query | median | p95 | min | max |", "|---|---:|---:|---:|---:|"]
for name, sql, user in Q:
    med, p95, lo, hi = time_query(sql, user); out.append(f"| {name} | {med:.1f} | {p95:.1f} | {lo:.1f} | {hi:.1f} |")
# export up to the 10,000-row cap: 50 pages of 200 rows, sequentially, as the browser does
pages = []
for off in range(0, 10000, 200):
    pages.append(time_query(f"select {REG} from public.v_compliance_instance order by due_date asc limit 200 offset {off}", ADMIN)[0] if off in (0, 5000, 9800) else None)
sampled = [p for p in pages if p is not None]
total = subprocess.run(["psql", "-q", url], input=f"select set_config('request.jwt.claim.sub', (select auth_user_id::text from public.app_user where email = '{ADMIN}'), false);\nset role authenticated;\n\\timing on\n\\o /dev/null\n" + "".join(f"select {REG} from public.v_compliance_instance order by due_date asc limit 200 offset {o};\n" for o in range(0, 10000, 200)), capture_output=True, text=True)
tt = [float(m) for m in re.findall(r"Time: ([0-9.]+) ms", total.stdout)]
out.append(f"\n**Export to the 10,000-row cap** (50 sequential 200-row pages, as the browser fetches them): total {sum(tt[-50:]):.0f} ms, per page median {statistics.median(tt[-50:]):.1f} ms, last page {tt[-1]:.1f} ms (deep OFFSET).\n")
out.append("## Plans: sequential scans on large tables\n")
for name, sql, user in Q:
    plan, seq, big = explain(sql, user)
    flag = ", ".join(f"`{t}`" for t in seq) if seq else "none"
    out.append(f"- **{name}** — Seq Scan on: {flag}" + (" (rows removed by filter: " + ", ".join(f"{t}={n}" for t, n in big) + ")" if big else ""))
print("\n".join(out))
