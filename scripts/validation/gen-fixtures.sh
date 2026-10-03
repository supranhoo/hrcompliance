#!/usr/bin/env bash
# Regenerates frontend CONTRACT fixtures from a real database built by the migrations + SQL test suites:
#   dashboard payload, calendar rows, and one real row (all columns) of every view the UI reads.
# The web tests then prove schemas / select-lists match what PostgreSQL actually returns.
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE="${PGURL:-postgresql://postgres@localhost:5432}"; DB="bfcl_fx_$$"; PSQL=$(command -v psql)
"$PSQL" -q "$BASE/postgres" -c "create database $DB"; trap '"$PSQL" -q "$BASE/postgres" -c "drop database if exists $DB" >/dev/null' EXIT
URL="$BASE/$DB"; OUT=apps/web/src/lib/fixtures; mkdir -p "$OUT"
"$PSQL" -q -f supabase/tests/00_supabase_shim.sql "$URL" >/dev/null 2>&1
for f in supabase/migrations/*.sql; do "$PSQL" -q -v ON_ERROR_STOP=1 -f "$f" "$URL" >/dev/null; done
for t in supabase/tests/10_*.sql supabase/tests/20_*.sql supabase/tests/4*.sql; do "$PSQL" -q -v ON_ERROR_STOP=1 -f "$t" "$URL" >/dev/null 2>&1; done
as_user() { # email, sql -> json text (executed as an authenticated user, so RLS applies exactly like the API)
  "$PSQL" -qtA "$URL" <<SQL | tail -1
begin;
select set_config('request.jwt.claim.sub', (select id::text from auth.users where email='$1'), true);
set local role authenticated;
$2
rollback;
SQL
}
"$PSQL" -qtA "$URL" -c "
begin; select set_config('request.jwt.claim.sub', (select id::text from auth.users where email='headhr@bfcl.test'), true); set local role authenticated;
select jsonb_pretty(public.compliance_dashboard()); rollback;" | sed -n '/^{/,$p' | sed '/^ROLLBACK$/d;/^BEGIN$/d' > "$OUT/dashboard.json"
"$PSQL" -qtA "$URL" -c "
begin; select set_config('request.jwt.claim.sub', (select id::text from auth.users where email='admin@bfcl.test'), true); set local role authenticated;
select jsonb_pretty(public.my_access()); rollback;" | sed -n '/^{/,$p' | sed '/^ROLLBACK$/d;/^BEGIN$/d' > "$OUT/my_access.json"
for v in v_compliance_instance v_exception v_licence_status v_evidence_requirement; do
  "$PSQL" -qtA "$URL" -c "
begin; select set_config('request.jwt.claim.sub', (select id::text from auth.users where email='headhr@bfcl.test'), true); set local role authenticated;
select jsonb_pretty(to_jsonb(x)) from (select * from public.$v limit 1) x; rollback;" | sed -n '/^{/,$p' | sed '/^ROLLBACK$/d;/^BEGIN$/d' > "$OUT/$v.json"
done
"$PSQL" -qtA "$URL" -c "
begin; select set_config('request.jwt.claim.sub', (select id::text from auth.users where email='headhr@bfcl.test'), true); set local role authenticated;
select jsonb_pretty(coalesce(jsonb_agg(c), '[]'::jsonb)) from (select * from public.compliance_calendar(current_date - 400, current_date + 400) limit 3) c; rollback;" | sed -n '/^\[/,$p' | sed '/^ROLLBACK$/d;/^BEGIN$/d' > "$OUT/calendar.json"
wc -c "$OUT"/*.json
