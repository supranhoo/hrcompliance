-- Read-only security classification audit. Returns one row per VIOLATION; zero rows = pass.
-- Run in CI (asserted empty) and in the Supabase SQL editor to verify the real project state.
with t as (
  select c.oid, c.relname, c.relrowsecurity as rls, c.relforcerowsecurity as forced
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
), pol as (select polrelid, count(*) n from pg_policy group by 1)
select relname as object, 'RLS not enabled' as violation from t where not rls
union all select relname, 'RLS not forced' from t where rls and not forced
union all select t.relname, 'anon has privilege ' || g.privilege_type
  from t join information_schema.role_table_grants g on g.table_schema='public' and g.table_name=t.relname and g.grantee='anon'
union all select t.relname, 'authenticated has dangerous privilege ' || g.privilege_type
  from t join information_schema.role_table_grants g on g.table_schema='public' and g.table_name=t.relname and g.grantee='authenticated'
  where g.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER')
union all select t.relname, 'authenticated has grants but no RLS policy (exposed table without rules)'
  from t left join pol on pol.polrelid = t.oid
  where coalesce(pol.n,0) = 0 and exists (select 1 from information_schema.role_table_grants g
        where g.table_schema='public' and g.table_name=t.relname and g.grantee='authenticated')
union all select p.proname, 'public function executable by anon'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and has_function_privilege('anon', p.oid, 'execute')
union all select 'default privileges', 'anon/authenticated still receive default grants on new public tables'
  where exists (select 1 from pg_default_acl d join pg_namespace n on n.oid=d.defaclnamespace
                where n.nspname='public' and d.defaclobjtype='r'
                  and exists (select 1 from aclexplode(d.defaclacl) a join pg_roles r on r.oid=a.grantee where r.rolname in ('anon','authenticated')));
