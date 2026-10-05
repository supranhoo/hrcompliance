#!/usr/bin/env bash
# Generates supabase/tests/live_gate.sql by embedding security_audit.sql into the template, so the gate can never drift from the audit.
# Usage: build-live-gate.sh [--check]   (--check fails if the committed file is stale)
set -euo pipefail
cd "$(dirname "$0")/../.."
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
python3 - > "$TMP" <<'PY'
t = open('supabase/tests/live_gate.template.sql').read()
a = open('supabase/tests/security_audit.sql').read().strip().rstrip(';')
a = '\n'.join(l for l in a.splitlines() if not l.startswith('-- Read-only') and not l.startswith('-- Run in CI'))
import glob
n = len(glob.glob('supabase/migrations/*.sql'))
EXPECTED = {'EXP_TABLES': 53, 'EXP_VIEWS': 19, 'EXP_PERMISSIONS': 25}      # single source of truth: update here when a migration adds tables/views/permissions
out = t.replace('@@AUDIT@@', a).replace('@@MIG_COUNT@@', str(n))
for k, v in EXPECTED.items(): out = out.replace('@@' + k + '@@', str(v))
print(out, end='')
PY
if [ "${1:-}" = "--check" ]; then
  cmp -s "$TMP" supabase/tests/live_gate.sql && echo "ok   - live_gate.sql is up to date with security_audit.sql" || { echo "FAIL live_gate.sql is stale: run scripts/validation/build-live-gate.sh"; exit 1; }
else
  cp "$TMP" supabase/tests/live_gate.sql; echo "wrote supabase/tests/live_gate.sql"
fi
