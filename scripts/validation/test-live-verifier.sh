#!/usr/bin/env bash
# Proves the DEV live-verification automation end to end on a throwaway database, as the REAL ci_verifier login created by the REAL setup file:
#   setup is safe (placeholder / non-DEV refused) -> verifier role passes its own audit -> the real runner passes with results identical to a superuser run
#   -> the verifier cannot read confidential tables, write, create, or call internals -> the runner FAILS when the gate fails, when the target is not DEV,
#   when the role is over-privileged, and when it is not ci_verifier -> no organisation names/codes or password ever reach the output.
# Usage: PGURL=postgresql://postgres@localhost:5432 scripts/validation/test-live-verifier.sh     (needs a superuser connection; PG16+)
set -euo pipefail
cd "$(dirname "$0")/../.."
BASE="${PGURL:-postgresql://postgres@localhost:5432}"; DB="bfcl_verifier_$$"
HOST="${TEST_PGHOST:-localhost}"; PORT="${TEST_PGPORT:-5432}"; PW="test-only-password-0123456789abcdef"
PSQL=$(type -P psql); T="$(mktemp -d)"
S() { "$PSQL" -v ON_ERROR_STOP=1 -q "$@"; }
cleanup() { S "$BASE/postgres" -c "drop database if exists $DB" >/dev/null 2>&1 || true; S "$BASE/postgres" -c "drop role if exists ci_verifier" >/dev/null 2>&1 || true; rm -rf "$T"; }
trap cleanup EXIT
[ "$(S "$BASE/postgres" -qtA -c "select count(*) from pg_roles where rolname = 'ci_verifier'")" = "0" ] || { echo "STOP: a ci_verifier role already exists in this PostgreSQL cluster; run this test on a clean/throwaway server (it creates and drops that role)."; exit 1; }
S "$BASE/postgres" -c "create database $DB"; URL="$BASE/$DB"
S "$URL" -f supabase/tests/00_supabase_shim.sql >/dev/null
for f in supabase/migrations/*.sql; do S "$URL" -f "$f" >/dev/null 2>&1 || { echo "FAIL migration $f"; exit 1; }; S "$URL" -c "insert into supabase_migrations.schema_migrations(version) values ('$(basename "$f" | cut -d_ -f1)')" >/dev/null; done
ok() { echo "ok   - $1"; }; bad() { echo "FAIL - $1"; exit 1; }
A() { S "$URL" -qtA "$@"; }                       # as the superuser
V() { PGPASSWORD="$PW" "$PSQL" -X -q -tA -v ON_ERROR_STOP=1 "host=$HOST port=$PORT user=ci_verifier dbname=$DB sslmode=disable" "$@"; }   # as ci_verifier
RUN() { PGHOST=$HOST PGPORT=$PORT PGUSER="${1:-ci_verifier}" PGDATABASE=$DB PGPASSWORD="$PW" PGSSLMODE=disable GITHUB_STEP_SUMMARY="$T/summary.md" scripts/validation/dev-live-verify.sh; }

# Synthetic, clearly fake organisation data (the distinctive tokens must never appear in any output) + a confidential-looking row in a table the verifier must not read.
A -c "insert into public.system_config(key,value) values ('environment.name','\"development\"') on conflict (key) do update set value = excluded.value"
A <<'SQL'
insert into public.entity(code,name,legal_name,pan) values ('ZZENT1','Zz Secret Entity Name','Zz Legal Name','AAAAA0000A');
insert into public.location(entity_id,code,name) select id,'ZZLOC1','Zz Secret GFA Plant' from public.entity where code='ZZENT1';
insert into public.business_unit(entity_id,code,name) select id,'ZZBU1','Zz Secret BU' from public.entity where code='ZZENT1';
insert into public.unit(business_unit_id,location_id,code,name) select b.id,l.id,'ZZU1','Zz HASP Unit' from public.business_unit b, public.location l where b.code='ZZBU1' and l.code='ZZLOC1';
insert into public.department(code,name) values ('ZZD1','Common'),('ZZD2','Zz Secret Dept');
insert into public.authority(code,name,authority_type,email) values ('ZZA1','Zz Secret Authority','statutory','zz@example.test');
SQL

# 1. Setup refuses the untouched placeholder and refuses a non-DEV database.
OUT=$(S "$URL" -f supabase/dev-samples/setup_ci_verifier.sql 2>&1 || true); echo "$OUT" | grep -q "SETUP STOPPED: replace the password placeholder" && ok "setup REFUSES the untouched password placeholder" || bad "setup ran with the placeholder"
sed "/v_password    constant/ s/PASTE-A-LONG-RANDOM-PASSWORD-HERE/$PW/" supabase/dev-samples/setup_ci_verifier.sql > "$T/setup.sql"
A -c "update public.system_config set value='\"production\"' where key='environment.name'"
OUT=$(S "$URL" -f "$T/setup.sql" 2>&1 || true); echo "$OUT" | grep -q "SETUP STOPPED: system_config environment.name" && [ "$(A -c "select count(*) from pg_roles where rolname='ci_verifier'")" = "0" ] && ok "setup REFUSES a database not labelled development (no role was created)" || bad "setup ran on a non-DEV label"
A -c "update public.system_config set value='\"development\"' where key='environment.name'"
S "$URL" -f "$T/setup.sql" >/dev/null && ok "setup runs on DEV" || bad "setup failed"
S "$URL" -f "$T/setup.sql" >/dev/null && ok "setup is re-runnable (idempotent)" || bad "setup re-run failed"

# 2. BYPASSRLS is technically required: the same grants WITHOUT it return zero rows from FORCE RLS tables (this is the measurement behind the design decision).
A -c "alter role ci_verifier nobypassrls"; N=$(V -c "select count(*) from public.permission"); A -c "alter role ci_verifier bypassrls"
[ "$N" = "0" ] && ok "measured: without BYPASSRLS the verifier sees 0 permission rows (FORCE RLS) - so BYPASSRLS + a column whitelist is required, not optional" || bad "expected 0 rows without BYPASSRLS, got $N"

# 3. Least privilege, proven by attempting things.
DENY() { local why="$1"; shift; if V -c "$*" >"$T/o" 2>&1; then bad "verifier was ALLOWED: $why"; else grep -qi "permission denied\|read-only transaction\|cannot execute\|must be owner" "$T/o" && ok "denied: $why" || { cat "$T/o"; bad "unexpected error for: $why"; }; fi; }
DENY "INSERT into system_config" "insert into public.system_config(key,value) values ('x','1')"
DENY "UPDATE system_config" "update public.system_config set value='\"production\"' where key='environment.name'"
DENY "DELETE from permission" "delete from public.permission"
DENY "TRUNCATE role" "truncate public.role"
DENY "CREATE TABLE in public" "create table public.zz_x(id int)"
DENY "CREATE SCHEMA" "create schema zz_x"
DENY "CREATE ROLE" "create role zz_r"
DENY "DROP a table" "drop table public.permission"
DENY "ALTER a table" "alter table public.permission add column zz int"
DENY "call app.has_permission (no USAGE on schema app)" "select app.has_permission('master.read')"
DENY "reading app_user.email" "select email from public.app_user"
DENY "reading app_user.full_name" "select full_name from public.app_user"
DENY "reading entity.pan (not whitelisted)" "select pan from public.entity"
DENY "reading authority.email (not whitelisted)" "select email from public.authority"
DENY "reading location.address (not whitelisted)" "select address from public.location"
DENY "SELECT * on a whitelisted table (unlisted columns inside it)" "select * from public.entity"
DENY "reading storage.objects (no object listing)" "select count(*) from storage.objects"
DENY "turning read-only off and writing anyway" "set default_transaction_read_only = off; insert into public.system_config(key,value) values ('x','1')"
# every public table that is not on the whitelist is completely unreadable
NONWL=$(A -c "select string_agg(c.relname, ' ') from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p','v') and not exists (select 1 from pg_attribute a, aclexplode(a.attacl) x where a.attrelid=c.oid and x.grantee=(select oid from pg_roles where rolname='ci_verifier'))")
CNT=0; for t in $NONWL; do if V -c "select 1 from public.$t limit 1" >"$T/o" 2>&1; then bad "verifier can read non-whitelisted public.$t"; fi; CNT=$((CNT+1)); done
[ "$CNT" -ge 25 ] && ok "all $CNT non-whitelisted tables/views in public are unreadable by the verifier" || bad "unexpectedly few non-whitelisted objects ($CNT)"

# 4. The verifier passes its own audit and the real runner passes; results equal a superuser run; nothing sensitive in the output.
RUN > "$T/run.out" 2>&1 && grep -q "RESULT: PASS" "$T/run.out" && ok "runner: all live checks PASS as ci_verifier (read-only, whitelisted)" || { cat "$T/run.out"; bad "runner did not pass"; }
grep -q "target labelled development" "$T/run.out" && grep -q "PASS - verifier role audit" "$T/run.out" && grep -q "PASS - live_gate.sql" "$T/run.out" && grep -q "PASS - live_attachment_check.sql" "$T/run.out" && grep -q "PASS - organisation master summary" "$T/run.out" && ok "runner reports DEV guard, role audit, gate, attachment check and org summary" || bad "runner output incomplete"
for f in supabase/tests/live_gate.sql supabase/dev-samples/live_attachment_check.sql; do
  A -F'|' -f "$f" > "$T/su.out"; { printf "BEGIN READ ONLY;\n"; cat "$f"; printf "\nROLLBACK;\n"; } | V -F'|' -f - > "$T/ver.out"; diff -q "$T/su.out" "$T/ver.out" >/dev/null && ok "$(basename "$f"): rows identical for ci_verifier and for the superuser" || bad "$(basename "$f") differs for the verifier"; done
if grep -Eqi "Zz Secret|ZZENT|ZZLOC|ZZBU|ZZD[12]|ZZA1|ZZU1|AAAAA0000A|$PW" "$T/run.out" "$T/summary.md"; then bad "organisation names/codes or the password leaked into the output / job summary"; else ok "no organisation name, code, PAN or password appears in the log or the job summary"; fi
grep -q "GFA exists: yes (in: location)" "$T/run.out" && grep -q "HASP exists: yes (in: unit)" "$T/run.out" && grep -q "Common exists: yes (in: department)" "$T/run.out" && grep -q "  location: 1" "$T/run.out" && grep -q "  department: 2" "$T/run.out" && ok "sanitized org summary: counts and GFA/HASP/Common flags with master types" || { cat "$T/run.out"; bad "org summary wrong"; }

# 5. Negative paths of the runner.
set +e
RUN postgres >"$T/n1.out" 2>&1; R1=$?
grep -q "REFUSED: the live verifier connects only as" "$T/n1.out" && [ $R1 -eq 2 ] && ok "runner REFUSES any login other than ci_verifier (exit 2)" || { cat "$T/n1.out"; bad "runner accepted a non-verifier login"; }
A -c "update public.system_config set value='\"production\"' where key='environment.name'"; RUN >"$T/n2.out" 2>&1; R2=$?
grep -q "ABORT: system_config environment.name is 'production'" "$T/n2.out" && [ $R2 -eq 3 ] && ! grep -q "live_gate" "$T/n2.out" && ok "runner ABORTS before running anything when the target is not 'development' (exit 3)" || { cat "$T/n2.out"; bad "runner did not abort on production label"; }
A -c "update public.system_config set value='\"development\"' where key='environment.name'"
A -c "insert into public.role(code,name) values ('ZZ_TEST_ROLE','zz test')"; RUN >"$T/n3.out" 2>&1; R3=$?
grep -q "FAIL #7: roles" "$T/n3.out" && grep -q "RESULT: FAIL" "$T/n3.out" && [ $R3 -eq 1 ] && ok "a live-gate FAIL fails the run (exit 1) and names the failing check" || { cat "$T/n3.out"; bad "gate failure not reported"; }
A -c "delete from public.role where code = 'ZZ_TEST_ROLE'"
A -c "update storage.buckets set public = true where id = 'attachments'"; RUN >"$T/n4.out" 2>&1; R4=$?
grep -q "FAIL #12" "$T/n4.out" && [ $R4 -eq 1 ] && ok "a PUBLIC attachments bucket fails the attachment check and the run" || { cat "$T/n4.out"; bad "public bucket not detected"; }
A -c "update storage.buckets set public = false where id = 'attachments'"
A -c "grant select on public.app_user to ci_verifier"; RUN >"$T/n5.out" 2>&1; R5=$?
grep -q "ABORT: the verifier role audit failed" "$T/n5.out" && [ $R5 -eq 4 ] && ! grep -q "PASS - live_gate" "$T/n5.out" && ok "an over-privileged verifier (extra table grant) stops the run before any script (exit 4)" || { cat "$T/n5.out"; bad "role drift not detected"; }
S "$URL" -f "$T/setup.sql" >/dev/null; A -c "alter role ci_verifier createrole"; RUN >"$T/n6.out" 2>&1; R6=$?
[ $R6 -eq 4 ] && grep -q "FAIL #2" "$T/n6.out" && ok "a verifier with CREATEROLE is detected and stops the run" || { cat "$T/n6.out"; bad "createrole drift not detected"; }
A -c "alter role ci_verifier nocreaterole"
printf 'select 1;\ncommit;\n' > "$T/evil.sql"; ( source <(sed -n '/^guard_sql()/,/^}/p' scripts/validation/dev-live-verify.sh); guard_sql "$T/evil.sql" ) >"$T/n7.out" 2>&1; grep -q REFUSED "$T/n7.out" && ok "the SQL guard refuses a script containing COMMIT" || bad "SQL guard did not bite"
set -e
RUN >"$T/final.out" 2>&1 && ok "after restoring the state the runner passes again (exit 0)" || { cat "$T/final.out"; bad "runner does not pass after restore"; }
env -u GITHUB_STEP_SUMMARY PGHOST=$HOST PGPORT=$PORT PGUSER=ci_verifier PGDATABASE=$DB PGPASSWORD="$PW" PGSSLMODE=disable scripts/validation/dev-live-verify.sh >"$T/nosum.out" 2>&1 && ok "runner exits 0 on PASS also when run by hand (no job-summary file)" || { cat "$T/nosum.out"; bad "runner exit status depends on the job summary"; }
# 6. Revocation: the drop script removes the login completely; the setup can recreate it afterwards.
S "$URL" -f supabase/dev-samples/drop_ci_verifier.sql >/dev/null 2>&1 && [ "$(A -c "select count(*) from pg_roles where rolname='ci_verifier'")" = "0" ] && ok "drop_ci_verifier.sql removes the login completely" || bad "drop script failed"
S "$URL" -f supabase/dev-samples/drop_ci_verifier.sql >/dev/null 2>&1 && ok "drop_ci_verifier.sql is re-runnable when the role is already gone" || bad "drop script re-run failed"
S "$URL" -f "$T/setup.sql" >/dev/null && RUN >"$T/re.out" 2>&1 && ok "setup after a drop recreates a working verifier (rotation / re-provisioning path)" || { cat "$T/re.out"; bad "re-provisioning failed"; }
echo "ALL LIVE VERIFIER TESTS PASSED"
