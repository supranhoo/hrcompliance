#!/usr/bin/env bash
# Regression guard: a numbered SQL suite must never be silently skipped (this happened once: suite 60 sat outside the runner's 4*/5* globs).
# Convention: supabase/tests/NN_name.sql (two digits). Every such file must be executed by db-test.sh, must end with an "ALL ... TESTS PASSED" marker,
# and any other *.sql in that folder must be a known non-suite file. Anything else fails, so a mis-named suite cannot hide.
# Usage: check-sql-suites.sh [--executed <file listing executed suites, one per line>] [--dir <tests dir>]
set -euo pipefail
cd "$(dirname "$0")/../.."
DIR=supabase/tests; EXEC=""
while [ $# -gt 0 ]; do case "$1" in --executed) EXEC="$2"; shift 2;; --dir) DIR="$2"; shift 2;; *) echo "unknown arg $1"; exit 2;; esac; done
KNOWN_NON_SUITES="live_gate.sql live_gate.template.sql security_audit.sql 00_supabase_shim.sql"
bad=0; found=0
for f in "$DIR"/*.sql; do
  b=$(basename "$f")
  case " $KNOWN_NON_SUITES " in *" $b "*) continue;; esac
  if ! echo "$b" | grep -Eq '^[0-9]{2}_[a-z0-9_]+\.sql$'; then echo "UNRECOGNISED SQL FILE in $DIR (suites must be named NN_name.sql; helpers must be listed in KNOWN_NON_SUITES): $b"; bad=1; continue; fi
  found=$((found+1))
  grep -Eq 'ALL [A-Z ]+ TESTS PASSED' "$f" || { echo "SUITE HAS NO 'ALL ... TESTS PASSED' MARKER (it could pass without running anything): $b"; bad=1; }
  if [ -n "$EXEC" ] && ! grep -Fxq "$DIR/$b" "$EXEC"; then echo "NUMBERED SUITE WAS NOT EXECUTED: $DIR/$b"; bad=1; fi
done
if [ -n "$EXEC" ]; then
  while read -r e; do [ -f "$e" ] || { echo "EXECUTED SUITE LIST names a missing file: $e"; bad=1; }; done < "$EXEC"
  [ "$found" -gt 0 ] || { echo "NO NUMBERED SUITES FOUND in $DIR"; bad=1; }
fi
[ "$bad" = 0 ] && echo "ok   - SQL suites: $found numbered suites discovered${EXEC:+ and all executed}"
exit $bad
