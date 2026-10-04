#!/usr/bin/env bash
# Proves the suite guard bites: on a scratch copy, a non-executed numbered suite, a mis-named suite and a marker-less suite each fail the check.
set -euo pipefail
cd "$(dirname "$0")/../.."
G=scripts/validation/check-sql-suites.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/t"; cp supabase/tests/*.sql "$T/t/"
ls "$T/t"/[0-9][0-9]_*.sql | grep -v '/00_' | sed "s#^$T/t#supabase/tests#" > "$T/exec.txt"
chk() { "$G" --dir "$T/t" --executed "$T/exec.txt" >/dev/null 2>&1; }
# the executed list uses the project-relative path; re-point the dir prefix so both sides agree
sed -i "s#^supabase/tests#$T/t#" "$T/exec.txt"
chk || { echo "FAIL suite guard: a clean tree was rejected"; exit 1; }
echo "-- x" > "$T/t/99_new_suite.sql"; echo "select 1; -- ALL NEW TESTS PASSED" >> "$T/t/99_new_suite.sql"
chk && { echo "FAIL suite guard: a numbered suite missing from the executed list was not detected"; exit 1; }
echo "$T/t/99_new_suite.sql" >> "$T/exec.txt"; chk || { echo "FAIL suite guard: an executed new suite was rejected"; exit 1; }
echo "select 1;" > "$T/t/98_no_marker.sql"; echo "$T/t/98_no_marker.sql" >> "$T/exec.txt"
chk && { echo "FAIL suite guard: a suite without a pass marker was not detected"; exit 1; }
rm "$T/t/98_no_marker.sql"
echo "select 1; -- ALL X TESTS PASSED" > "$T/t/7_badname.sql"; chk && { echo "FAIL suite guard: a mis-named suite was not detected"; exit 1; }
rm "$T/t/7_badname.sql"
echo "select 1; -- ALL X TESTS PASSED" > "$T/t/61-dash.sql"; chk && { echo "FAIL suite guard: a suite named with a dash was not detected"; exit 1; }
rm "$T/t/61-dash.sql"
echo "ok   - suite guard bites: unexecuted, marker-less and mis-named SQL suites each fail the check"
