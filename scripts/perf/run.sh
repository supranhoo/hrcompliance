#!/usr/bin/env bash
# Reproducible performance baseline on SYNTHETIC data (see seed.sql). Creates a throwaway database, applies the shim + all migrations, seeds, then times the app's real queries.
# Usage: PGURL=postgresql://postgres@localhost:5432 scripts/perf/run.sh [runs]      (default 30 runs per query; output: scripts/perf/results.md)
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE="${PGURL:-postgresql://postgres@localhost:5432}"; DB="bfcl_perf"; RUNS="${1:-30}"; URL="$BASE/$DB"
psql -q "$BASE/postgres" -c "drop database if exists $DB" -c "create database $DB"
psql -q "$URL" -f supabase/tests/00_supabase_shim.sql >/dev/null
for f in supabase/migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 "$URL" -f "$f" >/dev/null; done
psql -q "$URL" -f scripts/perf/seed.sql
python3 scripts/perf/bench.py "$URL" "$RUNS" > scripts/perf/results.md
echo "wrote scripts/perf/results.md"
