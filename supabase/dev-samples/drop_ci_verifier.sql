-- REVOKE / REMOVE the DEV verification login "ci_verifier" completely. NOT a migration; run by hand in the Supabase SQL Editor of bfcl-hrc-dev (as postgres). Safe to re-run.
-- Quick, reversible lock-out instead of removal:   alter role ci_verifier nologin;     (undo: re-run supabase/dev-samples/setup_ci_verifier.sql, which also rotates the password)
-- After removal also delete the GitHub environment secret DEV_DB_PASSWORD (and the variables DEV_DB_HOST / DEV_DB_USER) in Settings -> Environments -> dev-verification.
do $drop$
begin
  if exists (select 1 from pg_roles where rolname = 'ci_verifier') then
    begin perform pg_terminate_backend(pid) from pg_stat_activity where usename = 'ci_verifier'; exception when others then raise notice 'could not end open sessions (%); they end by themselves at the 60 s idle limit', sqlerrm; end;
    execute 'drop owned by ci_verifier';     -- removes every privilege granted to it (it owns nothing)
    execute 'drop role ci_verifier';
    raise notice 'ci_verifier removed';
  else
    raise notice 'ci_verifier does not exist - nothing to do';
  end if;
end
$drop$;
-- END OF FILE
