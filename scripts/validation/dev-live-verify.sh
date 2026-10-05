#!/usr/bin/env bash
# DEV live verification: runs the read-only verification SQL against bfcl-hrc-dev as the dedicated, column-whitelisted, read-only login "ci_verifier".
# Used by .github/workflows/verify-dev-live.yml; also runnable locally against any DEV/throwaway database (scripts/validation/test-live-verifier.sh does exactly that).
#
# Connection settings arrive as libpq environment variables, never as arguments and never echoed:
#   PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD   (PGSSLMODE defaults to "require")
# This script performs NO writes and NO migrations: every SQL file runs inside BEGIN READ ONLY ... ROLLBACK with a statement timeout, as a role that has no write privilege at all.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${PGHOST:?DEV_DB_HOST is not set}" "${PGPORT:?DEV_DB_PORT is not set}" "${PGUSER:?DEV_DB_USER is not set}" "${PGDATABASE:?DEV_DB_NAME is not set}" "${PGPASSWORD:?DEV_DB_PASSWORD is not set}"
[[ "$PGUSER" =~ ^ci_verifier(\..+)?$ ]] || { echo "REFUSED: the live verifier connects only as the dedicated ci_verifier login (ci_verifier.<project-ref> through the Session pooler)."; exit 2; }
export PGSSLMODE="${PGSSLMODE:-require}" PGCONNECT_TIMEOUT=15 PGAPPNAME=bfcl-live-verify
REPORT="$(dirname "$0")/live_verify_report.py"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT     # raw output (incl. the organisation inventory) lives only here and is deleted on exit
sum() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$1" >> "$GITHUB_STEP_SUMMARY"; fi; return 0; }   # job summary is optional (absent when run by hand)
sum "## DEV live verification (read-only)"

PSQL=("$(type -P psql)" -X -q -v ON_ERROR_STOP=1)   # real binary even if a caller exported a psql() shell function (db-test.sh does)

# Refuse SQL that could leave the read-only transaction or alter session settings (the files are reviewed code, this is a seat belt).
guard_sql() {
  if grep -Eiq '^[[:space:]]*((commit|rollback|abort|begin|savepoint|release|reset|start[[:space:]]+transaction|set[[:space:]]+(session|transaction|role|local[[:space:]]+role))([[:space:];]|$)|end[[:space:]]*;|\\)' "$1"; then
    echo "REFUSED: $1 contains transaction control, SET SESSION/ROLE, RESET or a psql meta-command."; exit 2; fi
}

# Runs one file inside READ ONLY, CSV output to $2. Returns psql's status.
run_ro() {
  guard_sql "$1"
  { printf "BEGIN READ ONLY;\nSET LOCAL statement_timeout = '30s';\nSET LOCAL lock_timeout = '5s';\n"; cat "$1"; printf '\nROLLBACK;\n'; } | "${PSQL[@]}" --csv -f - > "$2"
}

# 1. DEV guard: prove the target database labels itself "development" BEFORE anything else runs.
ENVNAME=$(printf "BEGIN READ ONLY;\nselect coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '(not set)');\nROLLBACK;\n" | "${PSQL[@]}" -tA 2>"$WORK/env.err") \
  || { echo "ABORT: could not connect or read system_config as ci_verifier. Check DEV_DB_HOST / DEV_DB_USER / DEV_DB_PASSWORD and that setup_ci_verifier.sql was run."; sed 's/^/  psql: /' "$WORK/env.err" | head -5; exit 3; }
ENVNAME=$(echo "$ENVNAME" | tr -d '[:space:]')
if [ "$ENVNAME" != "development" ]; then echo "ABORT: system_config environment.name is '$ENVNAME', not 'development'. Nothing was run."; sum "❌ **ABORTED**: target is not labelled development. Nothing was run."; exit 3; fi
echo "ok   - target labelled development (system_config environment.name)"

FAILED=0
step() { # kind file title
  local out="$WORK/$1.csv"
  if run_ro "$2" "$out" 2>"$WORK/$1.err"; then python3 "$REPORT" "$1" "$out" || FAILED=1
  else echo "FAIL - $3: the script did not run to completion"; sed 's/^/  psql: /' "$WORK/$1.err" | head -5; sum "### ❌ $3: did not run to completion (see the job log)"; FAILED=1; fi
}

# 2. The verifier must still be exactly the least-privilege role. If not, stop: the other results would not be trustworthy and the role is over-privileged.
run_ro supabase/dev-samples/live_verifier_role_audit.sql "$WORK/audit.csv" 2>"$WORK/audit.err" && python3 "$REPORT" audit "$WORK/audit.csv" \
  || { echo "ABORT: the verifier role audit failed; the three verification scripts were NOT run."; sed 's/^/  psql: /' "$WORK/audit.err" | head -3; exit 4; }

# 3. The three verification scripts (all read-only). All three always run so one report shows everything.
step gate       supabase/tests/live_gate.sql                       "live_gate.sql"
step attachment supabase/dev-samples/live_attachment_check.sql     "live_attachment_check.sql"
step org        supabase/dev-samples/live_org_masters_inventory.sql "live_org_masters_inventory.sql (sanitized summary)"

if [ "$FAILED" = "0" ]; then echo "RESULT: PASS - all live verification checks passed on DEV"; sum "## Result: ✅ PASS"
else echo "RESULT: FAIL - see the FAIL lines above"; sum "## Result: ❌ FAIL"; exit 1; fi
