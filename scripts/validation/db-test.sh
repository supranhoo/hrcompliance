#!/usr/bin/env bash
# Applies all migrations + seed to a throwaway Postgres database and runs SQL tests (RLS, audit, ids, rules).
# Usage: PGURL=postgresql://postgres@localhost:5432 scripts/validation/db-test.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
scripts/validation/check-frozen-migrations.sh
scripts/validation/test-frozen-lock.sh
scripts/validation/check-no-confidential-files.sh
scripts/validation/test-confidential-guard.sh
scripts/validation/check-sql-suites.sh
scripts/validation/test-sql-suite-guard.sh
scripts/validation/build-live-gate.sh --check
BASE="${PGURL:-postgresql://postgres@localhost:5432}"
DB="bfcl_test_$$"
PSQL=$(command -v psql)
psql() { "$PSQL" -v ON_ERROR_STOP=1 -q "$@"; }
export -f psql PSQL 2>/dev/null || true
psql "$BASE/postgres" -c "create database $DB"
trap 'psql "$BASE/postgres" -c "drop database if exists $DB" >/dev/null' EXIT
URL="$BASE/$DB"
psql "$URL" -f supabase/tests/00_supabase_shim.sql >/dev/null
for f in supabase/migrations/*.sql; do echo "migrate: $f"; psql "$URL" -f "$f" >/dev/null; v=$(basename "$f" | cut -d_ -f1); psql "$URL" -c "insert into supabase_migrations.schema_migrations(version) values ('$v')" >/dev/null; done
echo "seed migration: re-run for idempotency"; psql "$URL" -f "$(ls supabase/migrations/*_system_seed.sql)" >/dev/null
EXECUTED="${TMPDIR:-/tmp}/executed_suites_$$.txt"; : > "$EXECUTED"
run_tests() { # file marker
  echo "$1" >> "$EXECUTED"
  OUT=$(command psql -v ON_ERROR_STOP=1 -q "$URL" -f "$1" 2>&1 || true)
  echo "$OUT" | grep -E "ERROR|FAIL|ALL .* PASSED|NOTICE:  ok" | sed -E 's/^psql:[^ ]+ //; s/^(NOTICE|ERROR):  //'
  echo "$OUT" | grep -q "$2" || { echo "SQL TESTS FAILED: $1"; exit 1; }
}
# Every numbered suite (NN_name.sql, except the 00_ shim) is discovered by one pattern and must announce its own pass marker; check-sql-suites.sh then proves none was skipped.
for t in $(ls supabase/tests/[0-9][0-9]_*.sql | grep -v '/00_'); do n=$(grep -o "ALL [A-Z ]* TESTS PASSED" "$t" | tail -1); [ -n "$n" ] || { echo "SUITE WITHOUT PASS MARKER: $t"; exit 1; }; run_tests "$t" "$n"; done
scripts/validation/check-sql-suites.sh --executed "$EXECUTED"
rm -f "$EXECUTED"
VIOL=$("$PSQL" -qtA -F ' | ' "$URL" -f supabase/tests/security_audit.sql)
[ -z "$VIOL" ] && echo "ok   - security audit: 0 violations across all public tables/functions" || { echo "FAIL security audit:"; echo "$VIOL"; exit 1; }
# Concurrency: 40 parallel allocations must yield 40 distinct, gapless ids.
seq 1 40 | xargs -P 20 -I{} "$PSQL" -qtA "$URL" -c "select app.next_business_id('GRC', date '2026-01-01')" > "${TMPDIR:-/tmp}/ids_$$.txt"
U=$(sort -u "${TMPDIR:-/tmp}/ids_$$.txt" | wc -l); M=$(sort "${TMPDIR:-/tmp}/ids_$$.txt" | tail -1)
rm -f "${TMPDIR:-/tmp}/ids_$$.txt"
# Concurrency: 8 parallel generator runs over the same window must insert each obligation exactly once (idempotency key).
# Expected count is measured, not assumed: a rolled-back dry run inside a transaction tells us how many obligations the window holds.
EXP=$("$PSQL" -qtA "$URL" <<'SQL' | grep -E '^[0-9]+$' | tail -1
begin;
select (app.generate_compliance_instances(date '2028-01-01', date '2028-03-31') ->> 'inserted')::int;
rollback;
SQL
)
GEN=$(seq 1 8 | xargs -P 8 -I{} "$PSQL" -qtA "$URL" -c "select (app.generate_compliance_instances(date '2028-01-01', date '2028-03-31') ->> 'inserted')::int")
SUM=$(echo "$GEN" | awk '{s+=$1} END {print s}')
ROWS=$("$PSQL" -qtA "$URL" -c "select count(*) from public.compliance_instance where period_start between date '2028-01-01' and date '2028-03-31'")
DUPS=$("$PSQL" -qtA "$URL" -c "select count(*) from (select 1 from public.compliance_instance where status <> 'superseded' group by compliance_id, location_id, period_start having count(*) > 1) d")
[ "${EXP:-0}" -gt 0 ] && [ "$SUM" = "$EXP" ] && [ "$ROWS" = "$EXP" ] && [ "$DUPS" = "0" ] && echo "ok   - 8 concurrent generator runs: $EXP obligations inserted exactly once, 0 duplicates" || { echo "FAIL generator concurrency: expected=$EXP inserted_sum=$SUM rows=$ROWS duplicates=$DUPS"; exit 1; }
# Concurrency: 20 parallel claims of the same job key -> exactly one runner.
seq 1 20 | xargs -P 20 -I{} "$PSQL" -qtA "$URL" -c "select should_run from app.job_start('compliance_generation','2026-10')" > "${TMPDIR:-/tmp}/jobs_$$.txt"
T=$(grep -c '^t$' "${TMPDIR:-/tmp}/jobs_$$.txt"); rm -f "${TMPDIR:-/tmp}/jobs_$$.txt"
[ "$T" = "1" ] && echo "ok   - 20 concurrent job claims: exactly 1 runner" || { echo "FAIL job concurrency: runners=$T"; exit 1; }
[ "$U" = "40" ] && [ "$M" = "GRC-2026-000040" ] && echo "ok   - 40 concurrent allocations: 40 unique, max $M" || { echo "FAIL concurrency: unique=$U max=$M"; exit 1; }

# DEV live-verification automation: real setup file -> real ci_verifier login -> real runner, with least-privilege and failure-path proofs (own throwaway database).
PGURL="$BASE" scripts/validation/test-live-verifier.sh

# Synthetic dev samples: load -> engines produce real output -> idempotent re-load -> complete removal (separate throwaway DB).
DB2="bfcl_sample_$$"; psql "$BASE/postgres" -c "create database $DB2"; trap 'psql "$BASE/postgres" -c "drop database if exists $DB2" >/dev/null; psql "$BASE/postgres" -c "drop database if exists $DB" >/dev/null' EXIT
URL2="$BASE/$DB2"; Q0() { "$PSQL" -qtA "$URL2" -c "$1"; }; psql "$URL2" -f supabase/tests/00_supabase_shim.sql >/dev/null 2>&1
for f in supabase/migrations/*.sql; do psql "$URL2" -f "$f" >/dev/null 2>&1; psql "$URL2" -c "insert into supabase_migrations.schema_migrations(version) values ('$(basename "$f" | cut -d_ -f1)')" >/dev/null; done
# Live gate on a PRISTINE database (migrations only): every check must PASS exactly as it must on bfcl-hrc-dev.
GATE=$("$PSQL" -qtA -F '|' "$URL2" -f supabase/tests/live_gate.sql)
echo "$GATE" | grep -E '\|(FAIL|PASS|N/A)$' | sed 's/^/     gate: /' | tail -3
echo "$GATE" | grep -q '|FAIL$' && { echo "FAIL live gate on pristine DB:"; echo "$GATE" | grep '|FAIL$'; exit 1; }
echo "$GATE" | grep -q '^99|OVERALL|no FAIL|0 FAIL, 19 PASS, 0 N/A|PASS$' && echo "ok   - live gate passes on a pristine database (all migrations, 45 tables, 20 permissions, audit 0)" || { echo "FAIL live gate overall:"; echo "$GATE" | tail -3; exit 1; }
# environment guard: samples must be REFUSED when the database is unlabelled or labelled production
GUARD1=$("$PSQL" -q "$URL2" -f supabase/dev-samples/sample_compliance.sql 2>&1 | grep -c "REFUSED" || true)
psql "$URL2" -c "insert into public.system_config(key,value) values ('environment.name','\"production\"')" >/dev/null
GUARD2=$("$PSQL" -q "$URL2" -f supabase/dev-samples/sample_compliance.sql 2>&1 | grep -c "REFUSED" || true)
GUARD3=$("$PSQL" -q "$URL2" -f supabase/dev-samples/uat_engine_demo.sql 2>&1 | grep -c "REFUSED" || true)
[ "$GUARD1" -ge 1 ] && [ "$GUARD2" -ge 1 ] && [ "$GUARD3" -ge 1 ] && [ "$(Q0 "select count(*) from public.compliance_master")" = "0" ] && echo "ok   - sample/demo scripts REFUSE to run when unlabelled or labelled production (nothing was written)" || { echo "FAIL environment guard ($GUARD1/$GUARD2/$GUARD3)"; exit 1; }
psql "$URL2" -c "update public.system_config set value='\"development\"' where key='environment.name'" >/dev/null
# emulate the live dev project: the bootstrap admin exists and has signed in (active)
psql "$URL2" -f supabase/seed/dev_bootstrap_admin.sql >/dev/null; psql "$URL2" -c "update public.app_user set status='active'" >/dev/null
psql "$URL2" -f supabase/dev-samples/sample_compliance.sql >/dev/null
Q() { "$PSQL" -qtA "$URL2" -c "$1"; }
[ "$(Q "select count(*) from public.compliance_instance")" = "0" ] && echo "ok   - sample load is data-only: no obligations until the engines run" || { echo "FAIL sample load ran engines"; exit 1; }
M1=$(Q "select count(*) from public.compliance_master"); L1=$(Q "select count(*) from public.licence"); R1=$(Q "select count(*) from public.compliance_rule_version")
psql "$URL2" -f supabase/dev-samples/sample_compliance.sql >/dev/null
M2=$(Q "select count(*) from public.compliance_master"); L2=$(Q "select count(*) from public.licence"); R2=$(Q "select count(*) from public.compliance_rule_version")
[ "$M1" = "$M2" ] && [ "$L1" = "$L2" ] && [ "$R1" = "$R2" ] && [ "$L1" = "3" ] && echo "ok   - sample load is idempotent ($M1 masters, $R1 rule versions, $L1 licences; second load changed nothing)" || { echo "FAIL sample idempotency $M1/$M2 $L1/$L2 $R1/$R2"; exit 1; }
DEMO=$("$PSQL" -qtA -F '|' "$URL2" -f supabase/dev-samples/uat_engine_demo.sql 2>&1)
echo "$DEMO" | grep -E '^[0-9]+\|' | awk -F'|' '{printf "     demo: %-92s %s  %s ms\n", substr($2,1,92), $3, $4}'
echo "$DEMO" | grep -q 'ERROR' && { echo "FAIL demo script error:"; echo "$DEMO" | grep ERROR; exit 1; }
echo "$DEMO" | grep -qE '^[0-9]+\|[^|]*\|FAIL\|' && { echo "FAIL engine demo has FAIL rows"; exit 1; }
echo "$DEMO" | grep -qE '^[0-9]+\|7\. OVERALL\|PASS\|' && echo "ok   - live engine demo script: all steps PASS on synthetic data" || { echo "FAIL engine demo overall"; exit 1; }
SC=$("$PSQL" -qtA -F '|' "$URL2" -f supabase/dev-samples/uat_scope_check.sql 2>&1)
echo "$SC" | grep -E '^[0-9]+\|' | awk -F'|' '{printf "     scope: %-78s %s\n", substr($2,1,78), $5}'
echo "$SC" | grep -q 'ERROR' && { echo "FAIL scope script error:"; echo "$SC" | grep ERROR; exit 1; }
echo "$SC" | grep -qE '\|FAIL$' && { echo "FAIL scope check has FAIL rows"; exit 1; }
echo "$SC" | grep -qE '^[0-9]+\|OVERALL\|.*\|PASS$' && echo "ok   - scope check as a synthetic single-location user: nothing leaks across locations" || { echo "FAIL scope overall"; exit 1; }
psql "$URL2" -f supabase/dev-samples/uat_evidence_fixture.sql >/dev/null 2>&1
ST=$(Q "select string_agg(evidence_state, ',' order by evidence_state) from (select distinct evidence_state from public.v_evidence_requirement) x")
[ "$ST" = "expired,missing,pending_review,rejected,verified" ] && echo "ok   - evidence fixture makes all five evidence states visible ($ST)" || { echo "FAIL evidence states: $ST"; exit 1; }
EV1=$(Q "select count(*) from public.evidence"); psql "$URL2" -f supabase/dev-samples/uat_evidence_fixture.sql >/dev/null 2>&1; [ "$EV1" = "$(Q "select count(*) from public.evidence")" ] && echo "ok   - evidence fixture is idempotent" || { echo "FAIL evidence fixture not idempotent"; exit 1; }
psql "$URL2" -f supabase/dev-samples/uat_backdate_exception.sql >/dev/null 2>&1
AG=$(Q "select string_agg(age_bucket, ',' order by age_bucket) from (select distinct age_bucket from public.v_exception where status in ('open','acknowledged')) x")
echo "$AG" | grep -q "31-90" && echo "$AG" | grep -q "90+" && echo "$AG" | grep -q "8-30" && echo "ok   - ageing fixture produces the older buckets ($AG)" || { echo "FAIL ageing buckets: $AG"; exit 1; }
[ "$(Q "select count(*) from pg_trigger where tgrelid='public.exception'::regclass and tgname='exception_guard' and tgenabled='O'")" = "1" ] && echo "ok   - exception identity guard is enabled again after the ageing fixture" || { echo "FAIL guard left disabled"; exit 1; }
# rule-change demo needs a signed-in (linked) dev admin, as on the live project
psql "$URL2" -c "update public.app_user set auth_user_id='7b7b7b7b-0000-4000-8000-000000000002' where email='vivek.dansena08@gmail.com'" >/dev/null
RC=$("$PSQL" -qtA -F '|' "$URL2" -f supabase/dev-samples/uat_rule_change.sql 2>&1)
echo "$RC" | grep -E '^[0-9]+\|' | awk -F'|' '{printf "     rule: %-70s %s\n", substr($2,1,70), $3}'
echo "$RC" | grep -q 'ERROR' && { echo "FAIL rule-change script error:"; echo "$RC" | grep ERROR; exit 1; }
echo "$RC" | grep -qE '\|FAIL\|' && { echo "FAIL rule-change has FAIL rows"; exit 1; }
echo "$RC" | grep -qE '\|PASS\|' && echo "ok   - rule change via the permission-checked function: v1 retired, old obligations untouched, new period uses v2" || { echo "FAIL rule change"; exit 1; }
scripts/validation/uat-modular-test.sh "$URL2" || exit 1
N1=$(Q "select count(*) from public.compliance_instance"); E1=$(Q "select count(*) from public.exception"); NT1=$(Q "select count(*) from public.notification")
psql "$URL2" -f supabase/dev-samples/uat_engine_demo.sql >/dev/null 2>&1
[ "$N1" = "$(Q "select count(*) from public.compliance_instance")" ] && [ "$E1" -le "$(Q "select count(*) from public.exception")" ] && echo "ok   - re-running the demo creates no duplicate obligations" || { echo "FAIL demo rerun changed obligations"; exit 1; }
Q "select count(*) from public.compliance_instance i join public.location l on l.id=i.location_id where l.code='SAMPLE-LOC-B' and i.compliance_id=(select id from public.compliance_master where code='SAMPLE-QUARTERLY')" | grep -qx 0 && echo "ok   - samples: conditional applicability excluded the small office from the quarterly obligation" || { echo "FAIL sample applicability"; exit 1; }
psql "$URL2" -f supabase/dev-samples/remove_samples.sql >/dev/null
LEFT=$(Q "select (select count(*) from public.entity where code like 'SAMPLE%') + (select count(*) from public.compliance_master where code like 'SAMPLE%') + (select count(*) from public.compliance_instance) + (select count(*) from public.exception) + (select count(*) from public.licence) + (select count(*) from public.notification) + (select count(*) from public.location where code like 'SAMPLE%') + (select count(*) from public.evidence) + (select count(*) from public.app_user where email like 'sample.%@example.invalid') + (select count(*) from public.user_scope s join public.app_user u on u.id=s.user_id where u.email like 'sample.%')")
[ "$LEFT" = "0" ] && echo "ok   - sample removal leaves nothing behind" || { echo "FAIL sample removal left $LEFT rows"; exit 1; }
