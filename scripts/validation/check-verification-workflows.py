#!/usr/bin/env python3
"""Static security checks for the DEV verification automation. Runs in CI on every push/PR; needs no credentials and no network.

Safety is enforced mainly by database privileges + a READ ONLY transaction + environment isolation (see docs/LIVE_VERIFICATION_AUTOMATION.md).
These checks guard the *wiring* so that wiring cannot be loosened by accident: which workflows may touch which credentials, from which trigger and branch,
that nothing can run migrations or upload artifacts, and that no password / service-role key is committed.

Usage: check-verification-workflows.py [--root DIR]      exit 0 = all pass, 1 = any violation
"""
import glob, os, re, sys
try:
    import yaml
except ImportError:
    sys.exit('PyYAML is required: python3 -m pip install pyyaml')

root = sys.argv[sys.argv.index('--root') + 1] if '--root' in sys.argv else os.path.join(os.path.dirname(__file__), '..', '..')
root = os.path.abspath(root)
errors = []
def fail(msg): errors.append(msg)
def rd(p):
    with open(os.path.join(root, p), encoding='utf-8') as f: return f.read()
def nocomment(t): return '\n'.join(re.sub(r'(^|\s)#.*$', '', l) for l in t.splitlines())

APPROVED_BRANCH = 'refs/heads/claude/peaceful-wozniak-gyfjaw'
ENVIRONMENT = 'dev-verification'
LIVE, SMOKE = '.github/workflows/verify-dev-live.yml', '.github/workflows/verify-dev-storage-smoke.yml'
SPEC = {
    LIVE:  {'secrets': {'DEV_DB_PASSWORD'}, 'vars': {'DEV_DB_HOST', 'DEV_DB_PORT', 'DEV_DB_USER', 'DEV_DB_NAME'},
            'run': {'scripts/validation/dev-live-verify.sh'}, 'uses': {'actions/checkout@v4'}},
    SMOKE: {'secrets': {'SMOKE_USER_A_PASSWORD', 'SMOKE_USER_B_PASSWORD'}, 'vars': {'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SMOKE_USER_A_EMAIL', 'SMOKE_USER_B_EMAIL', 'DEV_DB_USER'},
            'run': {'node scripts/validation/dev-storage-smoke.mjs'}, 'uses': {'actions/checkout@v4', 'actions/setup-node@v4'}},
}
ALL_VERIFY_SECRETS = set().union(*[s['secrets'] for s in SPEC.values()])

def load(p):
    try: return yaml.safe_load(rd(p))
    except Exception as e: fail(f'{p}: cannot parse ({e})'); return None

for p, spec in SPEC.items():
    text = nocomment(rd(p)) if os.path.exists(os.path.join(root, p)) else None
    if text is None: fail(f'{p}: missing'); continue
    y = load(p)
    if not y: continue
    triggers = y.get(True, y.get('on'))
    if not (isinstance(triggers, dict) and set(triggers) == {'workflow_dispatch'}): fail(f'{p}: the ONLY trigger must be workflow_dispatch (found {triggers})')
    elif triggers['workflow_dispatch'] and triggers['workflow_dispatch'].get('inputs'): fail(f'{p}: workflow_dispatch must take no inputs (nothing user-typed may reach a credentialed job)')
    if y.get('permissions') != {'contents': 'read'}: fail(f'{p}: top-level permissions must be exactly contents: read')
    jobs = y.get('jobs') or {}
    if len(jobs) != 1: fail(f'{p}: exactly one job expected')
    for name, job in jobs.items():
        if job.get('environment') != ENVIRONMENT: fail(f'{p}: job {name} must use environment {ENVIRONMENT}')
        if APPROVED_BRANCH not in str(job.get('if', '')): fail(f'{p}: job {name} must be guarded by `if: github.ref == \'{APPROVED_BRANCH}\'`')
        if 'permissions' in job and job['permissions'] != {'contents': 'read'}: fail(f'{p}: job permissions must stay contents: read')
        if 'services' in job or 'container' in job: fail(f'{p}: no services/containers expected')
        for st in job.get('steps', []):
            if 'uses' in st and st['uses'] not in spec['uses']: fail(f'{p}: action {st["uses"]} is not on the allow-list {sorted(spec["uses"])}')
            if 'run' in st and st['run'].strip() not in spec['run']: fail(f'{p}: run step is not on the allow-list: {st["run"].strip()[:80]!r}')
            if st.get('uses', '').startswith('actions/checkout') and (st.get('with') or {}).get('persist-credentials') is not False: fail(f'{p}: checkout must set persist-credentials: false')
    used_secrets = set(re.findall(r'secrets\.([A-Za-z0-9_]+)', text)); used_vars = set(re.findall(r'\bvars\.([A-Za-z0-9_]+)', text))
    if used_secrets != spec['secrets']: fail(f'{p}: secrets referenced must be exactly {sorted(spec["secrets"])}, found {sorted(used_secrets)}')
    if not used_vars <= spec['vars']: fail(f'{p}: unexpected variables {sorted(used_vars - spec["vars"])}')
    if re.search(r'upload-artifact|actions/cache|download-artifact', text): fail(f'{p}: no artifact/cache steps are allowed (nothing from DEV may be stored)')
    if re.search(r'\$\{\{\s*(github\.event|inputs\.)', text): fail(f'{p}: no event/inputs expression may be interpolated')
    if re.search(r'(?i)\b(supabase\s+(db|migration|link|login|start|functions)|db push|pg_dump|psql|curl|wget)\b', '\n'.join(s.get('run', '') for j in jobs.values() for s in j.get('steps', []))): fail(f'{p}: workflow steps must not call supabase/psql/curl directly')

# the smoke workflow must not receive any database credential; the live workflow must not receive any smoke-user credential
smoke = nocomment(rd(SMOKE)) if os.path.exists(os.path.join(root, SMOKE)) else ''
if re.search(r'DEV_DB_PASSWORD|PGPASSWORD|DEV_DB_HOST|DEV_DB_NAME|PGHOST', smoke): fail(f'{SMOKE}: must not reference any database credential/host (DEV_DB_USER, a public variable, is the only DEV_DB_* allowed)')
live = nocomment(rd(LIVE)) if os.path.exists(os.path.join(root, LIVE)) else ''
if re.search(r'SMOKE_USER|SUPABASE_URL|PUBLISHABLE', live): fail(f'{LIVE}: must not reference smoke-test or API credentials')

# no OTHER workflow may use the environment or any of these secrets; push/PR workflows may use no secret but GITHUB_TOKEN
for p in sorted(glob.glob(os.path.join(root, '.github/workflows/*.y*ml'))):
    rel = os.path.relpath(p, root)
    if rel in SPEC: continue
    t = open(p, encoding='utf-8').read()
    if ENVIRONMENT in t or any(s in t for s in ALL_VERIFY_SECRETS): fail(f'{rel}: must not use the {ENVIRONMENT} environment or its secrets')
    for s in set(re.findall(r'secrets\.([A-Za-z0-9_]+)', t)):
        if s != 'GITHUB_TOKEN': fail(f'{rel}: references secret {s}; CI workflows may not use repository secrets')
    if re.search(r'pull_request_target', t): fail(f'{rel}: pull_request_target is not allowed')

# the runner script and the SQL it executes
sh = rd('scripts/validation/dev-live-verify.sh')
if 'BEGIN READ ONLY' not in sh or 'ROLLBACK' not in sh: fail('dev-live-verify.sh must wrap every script in BEGIN READ ONLY ... ROLLBACK')
if re.search(r'supabase/migrations|supabase\s+db|db push|\bcommit\b\s*;', sh, re.I) and 'supabase/migrations' in re.sub(r'#.*', '', sh): fail('dev-live-verify.sh must not reference migrations')
if "ci_verifier" not in sh or 'REFUSED' not in sh: fail('dev-live-verify.sh must refuse any login other than ci_verifier')
sql_files = set(re.findall(r'(supabase/(?:tests|dev-samples)/[A-Za-z0-9_.]+\.sql)', sh))
if sql_files != {'supabase/tests/live_gate.sql', 'supabase/dev-samples/live_attachment_check.sql', 'supabase/dev-samples/live_org_masters_inventory.sql', 'supabase/dev-samples/live_verifier_role_audit.sql'}:
    fail(f'dev-live-verify.sh runs an unexpected set of SQL files: {sorted(sql_files)}')
for f in sorted(sql_files):
    body = re.sub(r'--[^\n]*', '', rd(f))
    stripped = re.sub(r"'(?:[^']|'')*'", "''", body).strip().rstrip(';')     # string literals may contain ';'
    if not re.match(r'(?is)^(with|select)\b', stripped): fail(f'{f}: must be one statement starting with WITH or SELECT')
    if ';' in stripped: fail(f'{f}: must contain exactly one statement')
    if re.search(r'(?is)\(\s*(insert|update|delete|merge)\b', body) or re.search(r'(?is)\bselect\b[^;]*\binto\b\s+[a-z_.]+\s+from', body): fail(f'{f}: contains a data-modifying construct')
    if re.search(r'(?im)^\s*(\\|begin|commit|rollback|set\s)', body): fail(f'{f}: contains transaction control or a psql meta-command')

# the setup file must carry only the placeholder, never a real password
setup = rd('supabase/dev-samples/setup_ci_verifier.sql')
m = re.search(r"v_password\s+constant text := '([^']*)'", setup)
if not m or m.group(1) != 'PASTE-A-LONG-RANDOM-PASSWORD-HERE': fail('setup_ci_verifier.sql: v_password must be the unmodified placeholder')
if not re.search(r'(?i)nosuperuser nocreatedb nocreaterole noreplication', setup): fail('setup_ci_verifier.sql: role attributes must stay NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION')
if re.search(r'(?im)^\s*grant\s+(insert|update|delete|truncate|all|create|references|trigger)\b', setup) or re.search(r'(?im)^\s*grant\s+select\s+on\b', setup): fail('setup_ci_verifier.sql: only column-level SELECT grants are allowed (no table-level grants, no write/DDL grants)')
if re.search(r'(?im)^\s*grant\s+usage\s+on\s+schema\s+(app|auth|vault)\b', setup): fail('setup_ci_verifier.sql: no USAGE on schema app/auth/vault')
if re.search(r'(?im)^\s*grant\s+[a-z_]+\s+to\s+ci_verifier', setup) or re.search(r'(?im)^\s*grant\s+.*\bto\s+ci_verifier\s+with\s+admin', setup): fail('setup_ci_verifier.sql: no role grants to ci_verifier')

# no service-role / secret keys, no plaintext credentials, anywhere a workflow, script, doc or sample could carry them
SCAN = glob.glob(os.path.join(root, '.github/**/*'), recursive=True) + glob.glob(os.path.join(root, 'scripts/**/*'), recursive=True) + glob.glob(os.path.join(root, 'docs/**/*.md'), recursive=True) \
     + glob.glob(os.path.join(root, 'supabase/dev-samples/*')) + glob.glob(os.path.join(root, 'apps/web/src/**/*'), recursive=True) + glob.glob(os.path.join(root, 'apps/web/public/**/*'), recursive=True) + glob.glob(os.path.join(root, 'apps/web/*.*'))
GUARD_FILES = {'scripts/validation/dev-storage-smoke.mjs', 'scripts/validation/test-dev-storage-smoke.mjs', 'scripts/validation/check-verification-workflows.py', 'scripts/validation/test-verification-workflows.sh', 'scripts/migration'}
for p in SCAN:
    if not os.path.isfile(p): continue
    rel = os.path.relpath(p, root)
    try: t = open(p, encoding='utf-8').read()
    except Exception: continue
    guard = rel in GUARD_FILES or rel.endswith('.md')
    if not guard and re.search(r'(?i)SUPABASE_SERVICE_ROLE|SERVICE_ROLE_KEY|SUPABASE_ACCESS_TOKEN|SUPABASE_SECRET_KEY|sb_secret_[A-Za-z0-9]', t): fail(f'{rel}: references a service-role / secret key or an access token')
    if re.search(r'sb_secret_[A-Za-z0-9_-]{16,}', t): fail(f'{rel}: contains a Supabase secret key value')
    if re.search(r'eyJ[A-Za-z0-9_-]{15,}\.eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,}', t): fail(f'{rel}: contains a JWT-looking token')
    for mm in re.finditer(r'postgres(?:ql)?://([^:/@\s]+):([^@\s]+)@', t):
        pw = mm.group(2)
        if not re.fullmatch(r'(<[^>]*>|\$\{?[A-Za-z_]+\}?|\*+|\{\{[^}]*\}\}|PASSWORD|password|x+|\.\.\.|\[[^\]]*\])', pw): fail(f'{rel}: contains a connection string with an inline password')
    if rel.startswith('.github/') and re.search(r'(?i)\b(password|passwd|secret|token)\b\s*[:=]\s*["\']?[A-Za-z0-9/+_=-]{8,}', re.sub(r'\$\{\{[^}]*\}\}', '', t)) and 'secrets.' not in t.split('\n', 1)[0]:
        for line in t.splitlines():
            l = re.sub(r'\$\{\{[^}]*\}\}', '', line)
            if re.search(r'(?i)\b(password|passwd|secret|token)\b\s*[:=]\s*["\']?[A-Za-z0-9/+_=-]{8,}', l) and not l.strip().startswith('#'): fail(f'{rel}: possible plaintext credential: {line.strip()[:60]!r}')

if errors:
    print('VERIFICATION WORKFLOW CHECKS FAILED:'); [print('  - ' + e) for e in errors]; sys.exit(1)
print('ok   - verification workflows: workflow_dispatch only, environment dev-verification, approved branch only, exact secret allow-lists (live: DB password only; smoke: two synthetic passwords only)')
print('ok   - no artifacts/cache, no migration/supabase/psql/curl in steps, runner wraps every script in READ ONLY and refuses non-ci_verifier logins, only the 4 approved single-statement SELECT files run')
print('ok   - setup file: placeholder password only, NO* role attributes, column-level SELECT grants only, no USAGE on app/auth/vault')
print('ok   - no service-role/secret key, access token, JWT or inline-password connection string in workflows, scripts, docs, samples or the web app')
