#!/usr/bin/env bash
# Privacy guard (owner-approved PRV-02): fails when a TRACKED file looks like confidential source data, the pseudonym key, or a scratch/output data directory,
# and when a workflow would upload such files as an artifact. Targets source/confidential data by NAME and LOCATION; it does not ban ordinary application fixtures (csv/json) by extension.
# Usage: check-no-confidential-files.sh [repo-root]    (default: the repository containing this script)
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT"
ALLOW="scripts/validation/confidential-allowlist.txt"      # one tracked path per line, reviewed; empty by default
fail=0
bad() { echo "FAIL privacy guard: $1"; fail=1; }
allowed() { [ -f "$ALLOW" ] && grep -Fxq -- "$1" "$ALLOW"; }
while IFS= read -r f; do
  [ -n "$f" ] || continue
  allowed "$f" && continue
  lc=$(printf '%s' "$f" | tr 'A-Z' 'a-z')
  case "$lc" in
    *pseudonym*key*|*pseudonym_key*)                         bad "pseudonym key file tracked: $f" ;;
    *full_confidential*|*full-confidential*)                 bad "FULL_CONFIDENTIAL file tracked: $f" ;;
    *superseded_do_not_use*)                                 bad "superseded confidential output tracked: $f" ;;
    *confidential*.xlsx|*confidential*.xls|*confidential*.xlsm|*confidential*.xlsb|*confidential*.csv) bad "confidential spreadsheet/CSV tracked: $f" ;;
    data/*|raw/*|source-data/*|source_data/*|*/source-data/*|*/source_data/*) bad "raw/source-data directory tracked: $f" ;;
    phase[0-9]*_out/*|*/phase[0-9]*_out/*)                   bad "phase scratch/output data directory tracked: $f" ;;
    *contractor_mp_cost_*|*liaison_with_esic*|*grc_register_final*|*liaisoning_with_govt*|*daily_plant_visit*) bad "original BFCL source workbook name tracked: $f" ;;
    *.xlsx|*.xlsm|*.xlsb|*.xls)                              bad "spreadsheet workbook tracked (add to $ALLOW only after review): $f" ;;
  esac
done < <(git ls-files)
# Workflow artifacts: no upload of source/confidential/output paths (and no root-wide uploads).
for w in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$w" ] || continue
  if grep -q 'upload-artifact' "$w"; then
    paths=$(awk '/upload-artifact/{f=1} f && /path:/{print; f=0}' "$w")
    echo "$paths" | grep -qiE 'data|raw|source|phase[0-9]|confidential|pseudonym|\.xlsx?|\.csv|\*\*|path: *\.? *$|path: */' && bad "workflow $w uploads a forbidden or overly broad path as an artifact: $paths"
    [ -n "$paths" ] || bad "workflow $w uses upload-artifact without a checkable path"
  fi
done
[ "$fail" = 0 ] && echo "ok   - privacy guard: no confidential/source-data file or artifact upload among $(git ls-files | wc -l) tracked files" || exit 1
