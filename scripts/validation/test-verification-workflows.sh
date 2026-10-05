#!/usr/bin/env bash
# Self-test of check-verification-workflows.py: the unmodified repo must pass, and each deliberate loosening of the wiring (applied to a COPY) must be rejected.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -c 'import yaml' 2>/dev/null || python3 -m pip install --quiet pyyaml
python3 scripts/validation/check-verification-workflows.py >/dev/null && echo "ok   - verification-workflow checks pass on the repository" || { python3 scripts/validation/check-verification-workflows.py; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mutate() { # label  file  python-expression-body (operates on variable s)
  rm -rf "$T/r"; mkdir -p "$T/r/supabase/tests" "$T/r/supabase/dev-samples"
  cp -r .github scripts docs "$T/r/"; cp supabase/dev-samples/*.sql "$T/r/supabase/dev-samples/"; cp supabase/tests/live_gate.sql "$T/r/supabase/tests/"
  python3 - "$T/r/$2" "$3" <<'PY'
import sys
p, code = sys.argv[1], sys.argv[2]
s = open(p).read(); ns = {'s': s}; exec(code, ns); open(p, 'w').write(ns['s'])
PY
  if python3 scripts/validation/check-verification-workflows.py --root "$T/r" >"$T/out" 2>&1; then echo "FAIL - NOT rejected: $1"; exit 1; else echo "ok   - rejected: $1   <= $(sed -n 2p "$T/out" | cut -c1-110)"; fi
}
rm -rf "$T/r"; mkdir -p "$T/r/supabase/tests" "$T/r/supabase/dev-samples"; cp -r .github scripts docs "$T/r/"; cp supabase/dev-samples/*.sql "$T/r/supabase/dev-samples/"; cp supabase/tests/live_gate.sql "$T/r/supabase/tests/"
python3 scripts/validation/check-verification-workflows.py --root "$T/r" >/dev/null && echo "ok   - control: an unmodified copy of the tree passes (so each rejection below is caused by its own mutation)" || { echo "FAIL control copy"; exit 1; }
L=.github/workflows/verify-dev-live.yml; M=.github/workflows/verify-dev-storage-smoke.yml; U=supabase/dev-samples/setup_ci_verifier.sql
mutate "live workflow gains a pull_request trigger" $L "s = s.replace('on:\n  workflow_dispatch:', 'on:\n  workflow_dispatch:\n  pull_request:')"
mutate "live workflow gains a push trigger" $L "s = s.replace('on:\n  workflow_dispatch:', 'on:\n  workflow_dispatch:\n  push:')"
mutate "live workflow gains a free-text input" $L "s = s.replace('  workflow_dispatch:\n', '  workflow_dispatch:\n    inputs:\n      sql:\n        description: x\n', 1)"
mutate "live workflow loses the environment" $L "s = s.replace('    environment: dev-verification\n', '')"
mutate "live workflow loses the branch guard" $L "s = s.replace(\"if: github.ref == 'refs/heads/claude/peaceful-wozniak-gyfjaw'\", \"if: true\")"
mutate "live workflow gains write permission" $L "s = s.replace('contents: read', 'contents: write', 1)"
mutate "live workflow runs supabase db push" $L "s += '      - run: supabase db push\n'"
mutate "live workflow runs an arbitrary psql command" $L "s += '      - run: psql -c \"drop table x\"\n'"
mutate "live workflow uploads an artifact" $L "s += '      - uses: actions/upload-artifact@v4\n        with: {name: x, path: y}\n'"
mutate "live workflow uses an unlisted action" $L "s += '      - uses: someone/else@v1\n'"
mutate "live workflow receives a smoke-user secret" $L "s = s.replace('PGSSLMODE: require', 'PGSSLMODE: require\n          X: \${{ secrets.SMOKE_USER_A_PASSWORD }}')"
mutate "smoke workflow receives DEV_DB_PASSWORD" $M "s = s.replace('SUPABASE_URL: \${{ vars.SUPABASE_URL }}', 'SUPABASE_URL: \${{ vars.SUPABASE_URL }}\n          X: \${{ secrets.DEV_DB_PASSWORD }}')"
mutate "smoke workflow receives the DB host" $M "s = s.replace('DEV_DB_USER:', 'PGHOST: \${{ vars.DEV_DB_HOST }}\n          DEV_DB_USER:')"
mutate "smoke workflow adds a service-role secret" $M "s = s.replace('SUPABASE_URL: \${{ vars.SUPABASE_URL }}', 'SUPABASE_URL: \${{ vars.SUPABASE_URL }}\n          SUPABASE_SERVICE_ROLE_KEY: \${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}')"
mutate "smoke workflow publishes the publishable key as a secret-typed value of another name" $M "s = s.replace('vars.SUPABASE_PUBLISHABLE_KEY', 'vars.SOMETHING_ELSE')"
mutate "another (CI) workflow uses the verifier environment" .github/workflows/ci.yml "s = s.replace('jobs:', 'jobs:\n  x:\n    environment: dev-verification\n    runs-on: ubuntu-latest\n    steps: [{run: echo}]', 1)"
mutate "another (CI) workflow reads a repository secret" .github/workflows/ci.yml "s += '      - run: echo \${{ secrets.DEV_DB_PASSWORD }}\n'"
mutate "pull_request_target appears" .github/workflows/ci.yml "s = s.replace('on:\n  push:', 'on:\n  pull_request_target:\n  push:')"
mutate "setup file carries a real password" $U "s = s.replace(\"v_password    constant text := 'PASTE-A-LONG-RANDOM-PASSWORD-HERE'\", \"v_password    constant text := 'abc123abc123abc123abc123abc123'\")"
mutate "setup file adds a table-level grant" $U "s = s.replace('-- END OF FILE', 'grant select on public.app_user to ci_verifier;\n-- END OF FILE')"
mutate "setup file adds a write grant" $U "s = s.replace('-- END OF FILE', 'grant insert on public.entity to ci_verifier;\n-- END OF FILE')"
mutate "setup file grants USAGE on schema app" $U "s = s.replace('-- END OF FILE', 'grant usage on schema app to ci_verifier;\n-- END OF FILE')"
mutate "setup file makes the role CREATEROLE" $U "s = s.replace('nocreaterole', 'createrole')"
mutate "setup file grants a role to ci_verifier" $U "s = s.replace('-- END OF FILE', 'grant postgres to ci_verifier;\n-- END OF FILE')"
mutate "an inventory SQL gains a data-modifying CTE" supabase/dev-samples/live_org_masters_inventory.sql "s = s.replace('select \'entity\' as master', 'with x as (delete from public.entity returning 1) select \'entity\' as master', 1)"
mutate "an inventory SQL gains a second statement" supabase/dev-samples/live_org_masters_inventory.sql "s = s.replace('-- END OF FILE', 'select 2;\n-- END OF FILE')"
mutate "a verification SQL gains COMMIT" supabase/dev-samples/live_attachment_check.sql "s = s.replace('-- END OF FILE', 'commit;\n-- END OF FILE')"
mutate "a doc contains a connection string with a password" docs/RUNBOOKS.md "s += '\npostgres''ql://ci_verifier.abcdefghij:Sup3rS3cretPw@host.example.com:5432/postgres\n'"
mutate "a script contains a secret key value" scripts/validation/headers-lib.mjs "s += '\n// sb_sec''ret_abcdefghijklmnopqrstuvwx\n'"
mutate "a script contains a service-role env name" scripts/validation/verify-live-headers.mjs "s += '\n// SUPABASE_SERVICE_ROLE_KEY\n'"
mutate "the runner no longer wraps scripts in READ ONLY" scripts/validation/dev-live-verify.sh "s = s.replace('BEGIN READ ONLY', 'BEGIN')"
mutate "the runner runs an unapproved SQL file" scripts/validation/dev-live-verify.sh "s += '\nstep x supabase/dev-samples/uat_engine_demo.sql y\n'"
echo "ALL VERIFICATION WORKFLOW CHECK SELF-TESTS PASSED"
