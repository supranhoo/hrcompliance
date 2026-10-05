#!/usr/bin/env bash
# Proves the privacy guard bites: each prohibited path/pattern fails, harmless fixtures pass, and the real repository passes.
set -euo pipefail
cd "$(dirname "$0")/../.."
GUARD="$PWD/scripts/validation/check-no-confidential-files.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { rm -rf "$T/r"; mkdir -p "$T/r"; (cd "$T/r" && git init -q . && git config user.email t@t && git config user.name t && mkdir -p scripts/validation .github/workflows && touch README.md); }
expect_fail() { # label  path-to-add
  mk; (cd "$T/r" && mkdir -p "$(dirname "$2")" && : > "$2" && git add -f "$2" && git commit -qm x)
  if "$GUARD" "$T/r" >/dev/null 2>&1; then echo "FAIL guard did not reject: $1 ($2)"; exit 1; fi
  echo "ok   - guard rejects $1"
}
expect_pass() {
  mk; (cd "$T/r" && mkdir -p "$(dirname "$2")" && : > "$2" && git add -f "$2" && git commit -qm x)
  "$GUARD" "$T/r" >/dev/null 2>&1 || { echo "FAIL guard rejected a legitimate file: $1 ($2)"; exit 1; }
  echo "ok   - guard accepts $1"
}
expect_fail "pseudonym key"            "PSEUDONYM_KEY_CONFIDENTIAL.xlsx"
expect_fail "pseudonym key (txt)"      "notes/pseudonym_key.txt"
expect_fail "FULL_CONFIDENTIAL file"   "out/GRC_cleaned_FULL_CONFIDENTIAL.xlsx"
expect_fail "superseded output"        "SUPERSEDED_DO_NOT_USE__x.txt"
expect_fail "root data directory"      "data/source/anything.txt"
expect_fail "source-data directory"    "source-data/a.txt"
expect_fail "phase output directory"   "phase2_out/a.txt"
expect_fail "nested phase output dir"  "work/phase4_out/a.txt"
expect_fail "original workbook name"   "docs/Contractor_MP_cost_01092026_1_1.csv"
expect_fail "any xlsx workbook"        "tests/a.xlsx"
expect_fail "confidential csv"         "x/people_CONFIDENTIAL.csv"
expect_pass "application fixture json" "apps/web/src/lib/fixtures/dashboard.json"
expect_pass "application fixture csv"  "apps/web/src/lib/fixtures/sample.csv"
expect_pass "documentation"            "docs/migration/PHASE1_SOURCE_AUDIT.md"
# allow-list works for a reviewed workbook
mk; (cd "$T/r" && : > t.xlsx && echo t.xlsx > scripts/validation/confidential-allowlist.txt && git add -f . && git commit -qm x); "$GUARD" "$T/r" >/dev/null 2>&1 && echo "ok   - allow-listed path is accepted (reviewed exception)" || { echo "FAIL allow-list ignored"; exit 1; }
# workflow artifact uploads
mk; (cd "$T/r" && printf 'jobs:\n  a:\n    steps:\n      - uses: actions/upload-artifact@v4\n        with:\n          name: x\n          path: phase2_out/\n' > .github/workflows/w.yml && git add -f . && git commit -qm x)
"$GUARD" "$T/r" >/dev/null 2>&1 && { echo "FAIL guard accepted an artifact upload of a forbidden path"; exit 1; } || echo "ok   - guard rejects an artifact upload of a forbidden path"
mk; (cd "$T/r" && printf 'jobs:\n  a:\n    steps:\n      - uses: actions/upload-artifact@v4\n        with:\n          name: x\n          path: apps/web/dist/report.html\n' > .github/workflows/w.yml && git add -f . && git commit -qm x)
"$GUARD" "$T/r" >/dev/null 2>&1 && echo "ok   - guard accepts a harmless artifact upload" || { echo "FAIL guard rejected a harmless artifact upload"; exit 1; }
"$GUARD" "$PWD" && echo "ok   - the real repository passes the privacy guard"
