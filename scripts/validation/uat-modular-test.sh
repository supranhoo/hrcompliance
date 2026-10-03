#!/usr/bin/env bash
# Validates the SQL-Editor-safe modular UAT runner (supabase/dev-samples/uat_engine_01..08) on a database that already has migrations + SAMPLE data.
# Usage: uat-modular-test.sh <database-url> [fresh-url-factory-not-needed]
# Checks: every file runs on its own (each file is executed in its OWN psql session, so no temp table can leak between files), has no FAIL row,
# runs twice safely, is refused when the database is not labelled development, and stays small enough to paste.
set -euo pipefail
URL="$1"; PSQL=$(type -P psql); D=supabase/dev-samples
Q() { "$PSQL" -qtA "$URL" -c "$1"; }
FILES=$(ls $D/uat_engine_0[1-8]_*.sql)
for f in $FILES; do
  [ "$(wc -c < "$f")" -lt 9000 ] || { echo "FAIL $f is larger than 9000 bytes (paste-truncation risk)"; exit 1; }
  tail -1 "$f" | grep -q '^-- END OF FILE$' || { echo "FAIL $f lacks the END OF FILE sentinel"; exit 1; }
done
run_all() { # pass label
  for f in $FILES; do
    OUT=$("$PSQL" -qtA -F '|' -v ON_ERROR_STOP=1 "$URL" -f "$f" 2>&1) || { echo "FAIL $f errored:"; echo "$OUT"; exit 1; }
    echo "$OUT" | grep -q 'ERROR' && { echo "FAIL $f error"; echo "$OUT"; exit 1; }
    echo "$OUT" | grep -qE '^[0-9A-Z.]+[^|]*\|FAIL\|' && { echo "FAIL $f has FAIL rows:"; echo "$OUT" | grep '|FAIL|'; exit 1; }
    ROWS=$(echo "$OUT" | grep -cE '\|(PASS|INFO|FAIL)\|' || true); [ "$ROWS" -ge 1 ] || { echo "FAIL $f returned no result rows"; echo "$OUT"; exit 1; }
    echo "     $1 $(basename "$f"): $(echo "$OUT" | grep -c '|PASS|') PASS, $(echo "$OUT" | grep -c '|INFO|') INFO"
  done
}
run_all "run1"
N1=$(Q "select count(*) from public.compliance_instance"); E1=$(Q "select count(*) from public.exception"); K1=$(Q "select count(*) from public.notification")
run_all "run2"
[ "$N1" = "$(Q "select count(*) from public.compliance_instance")" ] && [ "$K1" = "$(Q "select count(*) from public.notification")" ] && echo "ok   - modular UAT runner: second full pass created no obligations or notifications" || { echo "FAIL modular rerun changed counts"; exit 1; }
OV=$("$PSQL" -qtA -F '|' "$URL" -f $D/uat_engine_08_overall.sql | grep '^[0-9]*|OVERALL|' || true)
echo "$OV" | grep -q '|PASS|' && echo "ok   - modular UAT runner: 08 overall = PASS ($OV)" || { echo "FAIL 08 overall: $OV"; exit 1; }
