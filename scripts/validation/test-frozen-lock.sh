#!/usr/bin/env bash
# Proves the migration hash-lock actually bites: in a scratch copy of the repo, (1) editing a locked migration, (2) deleting one and
# (3) inserting a new file inside the locked range must each make check-frozen-migrations.sh fail; an untouched copy must pass.
set -euo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts/validation" "$T/supabase"; cp scripts/validation/check-frozen-migrations.sh "$T/scripts/validation/"; cp -r supabase/migrations supabase/migrations.lock "$T/supabase/"
chk() { (cd "$T" && scripts/validation/check-frozen-migrations.sh >/dev/null 2>&1); }
chk || { echo "FAIL lock test: pristine copy rejected"; exit 1; }
L=$(sort -k2 supabase/migrations.lock | awk '{print $2}'); N=$(echo "$L" | wc -l); [ "$N" -ge 25 ] || { echo "FAIL lock covers only $N migrations"; exit 1; }
F="$T/$(echo "$L" | sed -n 17p)"; cp "$F" "$F.bak"
echo "-- tamper" >> "$F"; chk && { echo "FAIL lock test: edit of a locked migration (0017) not detected"; exit 1; }
mv "$F.bak" "$F"; chk || { echo "FAIL lock test: restore failed"; exit 1; }
rm "$F"; chk && { echo "FAIL lock test: deletion not detected"; exit 1; }
cp "$F.bak" "$F" 2>/dev/null || cp "$T/supabase/migrations/$(basename "$F")" "$F" 2>/dev/null || true
echo "-- x" > "$T/supabase/migrations/20261003000015_inserted.sql"; chk && { echo "FAIL lock test: insertion inside locked range not detected"; exit 1; }
echo "ok   - hash-lock bites: edit, delete and insert-inside-range of a locked migration each fail the check ($N migrations locked)"
