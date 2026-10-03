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
psql "$URL" -f supabase/seed/001_system_seed.sql >/dev/null
echo "seed: re-run for idempotency"; psql "$URL" -f supabase/seed/001_system_seed.sql >/dev/null
OUT=$(command psql -v ON_ERROR_STOP=1 -q "$URL" -f supabase/tests/10_rls_and_rules.sql 2>&1 || true)
echo "$OUT" | grep -E "ERROR|FAIL|ALL DB|NOTICE:  ok" | sed -E 's/^psql:[^ ]+ //; s/^(NOTICE|ERROR):  //'
echo "$OUT" | grep -q "ALL DB TESTS PASSED" || { echo "SQL TESTS FAILED"; exit 1; }
# Concurrency: 40 parallel allocations must yield 40 distinct, gapless ids.
seq 1 40 | xargs -P 20 -I{} "$PSQL" -qtA "$URL" -c "select app.next_business_id('GRC', date '2026-01-01')" > "${TMPDIR:-/tmp}/ids_$$.txt"
U=$(sort -u "${TMPDIR:-/tmp}/ids_$$.txt" | wc -l); M=$(sort "${TMPDIR:-/tmp}/ids_$$.txt" | tail -1)
rm -f "${TMPDIR:-/tmp}/ids_$$.txt"
[ "$U" = "40" ] && [ "$M" = "GRC-2026-000040" ] && echo "ok   - 40 concurrent allocations: 40 unique, max $M" || { echo "FAIL concurrency: unique=$U max=$M"; exit 1; }
