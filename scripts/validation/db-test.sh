#!/usr/bin/env bash
# Applies all migrations + seed to a throwaway Postgres database and runs SQL tests (RLS, audit, ids, rules).
# Usage: PGURL=postgresql://postgres@localhost:5432 scripts/validation/db-test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
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
VIOL=$("$PSQL" -qtA -F ' | ' "$URL" -f supabase/tests/security_audit.sql)
[ -z "$VIOL" ] && echo "ok   - security audit: 0 violations across all public tables/functions" || { echo "FAIL security audit:"; echo "$VIOL"; exit 1; }
# Concurrency: 40 parallel allocations must yield 40 distinct, gapless ids.
seq 1 40 | xargs -P 20 -I{} "$PSQL" -qtA "$URL" -c "select app.next_business_id('GRC', date '2026-01-01')" > "${TMPDIR:-/tmp}/ids_$$.txt"
U=$(sort -u "${TMPDIR:-/tmp}/ids_$$.txt" | wc -l); M=$(sort "${TMPDIR:-/tmp}/ids_$$.txt" | tail -1)
rm -f "${TMPDIR:-/tmp}/ids_$$.txt"
# Concurrency: 20 parallel claims of the same job key -> exactly one runner.
seq 1 20 | xargs -P 20 -I{} "$PSQL" -qtA "$URL" -c "select should_run from app.job_start('compliance_generation','2026-10')" > "${TMPDIR:-/tmp}/jobs_$$.txt"
T=$(grep -c '^t$' "${TMPDIR:-/tmp}/jobs_$$.txt"); rm -f "${TMPDIR:-/tmp}/jobs_$$.txt"
[ "$T" = "1" ] && echo "ok   - 20 concurrent job claims: exactly 1 runner" || { echo "FAIL job concurrency: runners=$T"; exit 1; }
[ "$U" = "40" ] && [ "$M" = "GRC-2026-000040" ] && echo "ok   - 40 concurrent allocations: 40 unique, max $M" || { echo "FAIL concurrency: unique=$U max=$M"; exit 1; }
