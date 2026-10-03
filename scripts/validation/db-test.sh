#!/usr/bin/env bash
# Applies all migrations + seed to a throwaway Postgres database and runs SQL tests (RLS, audit, ids, rules).
# Usage: PGURL=postgresql://postgres@localhost:5432 scripts/validation/db-test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
scripts/validation/check-frozen-migrations.sh
BASE="${PGURL:-postgresql://postgres@localhost:5432}"
DB="bfcl_test_$$"
PSQL=$(command -v psql)
psql() { "$PSQL" -v ON_ERROR_STOP=1 -q "$@"; }
export -f psql PSQL 2>/dev/null || true
psql "$BASE/postgres" -c "create database $DB"
trap 'psql "$BASE/postgres" -c "drop database if exists $DB" >/dev/null' EXIT
URL="$BASE/$DB"
psql "$URL" -f supabase/tests/00_supabase_shim.sql >/dev/null
for f in supabase/migrations/*.sql; do echo "migrate: $f"; psql "$URL" -f "$f" >/dev/null; done
echo "seed migration: re-run for idempotency"; psql "$URL" -f "$(ls supabase/migrations/*_system_seed.sql)" >/dev/null
run_tests() { # file marker
  OUT=$(command psql -v ON_ERROR_STOP=1 -q "$URL" -f "$1" 2>&1 || true)
  echo "$OUT" | grep -E "ERROR|FAIL|ALL .* PASSED|NOTICE:  ok" | sed -E 's/^psql:[^ ]+ //; s/^(NOTICE|ERROR):  //'
  echo "$OUT" | grep -q "$2" || { echo "SQL TESTS FAILED: $1"; exit 1; }
}
run_tests supabase/tests/10_rls_and_rules.sql "ALL DB TESTS PASSED"
run_tests supabase/tests/20_platform_tests.sql "ALL PLATFORM TESTS PASSED"
run_tests supabase/tests/30_auth_link_tests.sql "ALL AUTH LINK TESTS PASSED"
for t in supabase/tests/4*.sql; do n=$(grep -o "ALL [A-Z ]* TESTS PASSED" "$t" | tail -1); run_tests "$t" "$n"; done
VIOL=$("$PSQL" -qtA -F ' | ' "$URL" -f supabase/tests/security_audit.sql)
[ -z "$VIOL" ] && echo "ok   - security audit: 0 violations across all public tables/functions" || { echo "FAIL security audit:"; echo "$VIOL"; exit 1; }
# Concurrency: 40 parallel allocations must yield 40 distinct, gapless ids.
seq 1 40 | xargs -P 20 -I{} "$PSQL" -qtA "$URL" -c "select app.next_business_id('GRC', date '2026-01-01')" > "${TMPDIR:-/tmp}/ids_$$.txt"
U=$(sort -u "${TMPDIR:-/tmp}/ids_$$.txt" | wc -l); M=$(sort "${TMPDIR:-/tmp}/ids_$$.txt" | tail -1)
rm -f "${TMPDIR:-/tmp}/ids_$$.txt"
# Concurrency: 8 parallel generator runs over the same window must insert each obligation exactly once (idempotency key).
# Expected count is measured, not assumed: a rolled-back dry run inside a transaction tells us how many obligations the window holds.
EXP=$("$PSQL" -qtA "$URL" <<'SQL' | grep -E '^[0-9]+$' | tail -1
begin;
select (app.generate_compliance_instances(date '2028-01-01', date '2028-03-31') ->> 'inserted')::int;
rollback;
SQL
)
GEN=$(seq 1 8 | xargs -P 8 -I{} "$PSQL" -qtA "$URL" -c "select (app.generate_compliance_instances(date '2028-01-01', date '2028-03-31') ->> 'inserted')::int")
SUM=$(echo "$GEN" | awk '{s+=$1} END {print s}')
ROWS=$("$PSQL" -qtA "$URL" -c "select count(*) from public.compliance_instance where period_start between date '2028-01-01' and date '2028-03-31'")
DUPS=$("$PSQL" -qtA "$URL" -c "select count(*) from (select 1 from public.compliance_instance group by compliance_id, location_id, period_start having count(*) > 1) d")
[ "${EXP:-0}" -gt 0 ] && [ "$SUM" = "$EXP" ] && [ "$ROWS" = "$EXP" ] && [ "$DUPS" = "0" ] && echo "ok   - 8 concurrent generator runs: $EXP obligations inserted exactly once, 0 duplicates" || { echo "FAIL generator concurrency: expected=$EXP inserted_sum=$SUM rows=$ROWS duplicates=$DUPS"; exit 1; }
# Concurrency: 20 parallel claims of the same job key -> exactly one runner.
seq 1 20 | xargs -P 20 -I{} "$PSQL" -qtA "$URL" -c "select should_run from app.job_start('compliance_generation','2026-10')" > "${TMPDIR:-/tmp}/jobs_$$.txt"
T=$(grep -c '^t$' "${TMPDIR:-/tmp}/jobs_$$.txt"); rm -f "${TMPDIR:-/tmp}/jobs_$$.txt"
[ "$T" = "1" ] && echo "ok   - 20 concurrent job claims: exactly 1 runner" || { echo "FAIL job concurrency: runners=$T"; exit 1; }
[ "$U" = "40" ] && [ "$M" = "GRC-2026-000040" ] && echo "ok   - 40 concurrent allocations: 40 unique, max $M" || { echo "FAIL concurrency: unique=$U max=$M"; exit 1; }
