-- FU-001: owner-fallback routing is configuration (alert rule OWNER_FALLBACK), not a hardcoded role. Rolled back.
\set ON_ERROR_STOP on
begin;
select test.eq('no role literal remains in the recipient resolvers', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname in ('resolve_recipients','unroutable_recipients') and p.prosrc like '%HEAD_HR%'), 0::bigint);
select test.eq('seeded OWNER_FALLBACK preserves the previous behaviour (role HEAD_HR)', (select definition -> 'recipients' from app.active_alert_rules() where code = 'OWNER_FALLBACK'), '["role:HEAD_HR"]'::jsonb);

insert into public.department (code, name) values ('FB-D', 'fallback dept');
create or replace function test.mkuser2(p_email text, p_role text) returns void language plpgsql as $$
begin
  insert into public.app_user (email, status) values (p_email, 'active');
  insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email = p_email and r.code = p_role;
  insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email = p_email and e.code = 'E1';
end $$;
select test.mkuser2('fb_hr@bfcl.test', 'HEAD_HR');
select test.mkuser2('fb_viewer@bfcl.test', 'VIEWER');
create or replace function test.who(p_recipients jsonb, p_dept text default null) returns text language sql stable as $$
  select coalesce(string_agg(a.email, ',' order by a.email), '-') from app.resolve_recipients(p_recipients, null, (select id from public.entity where code = 'E1'), (select id from public.location where code = 'L-E1'),
         (select id from public.department where code = p_dept)) r(u) join public.app_user a on a.id = r.u where a.email like 'fb\_%' $$;
grant execute on all functions in schema test to authenticated, anon;

select test.eq('owner missing -> seeded fallback reaches Head HR in scope (as before)', test.who('["owner"]'), 'fb_hr@bfcl.test');
select test.eq('fallback respects department scope (user without the department is skipped)', test.who('["owner"]', 'FB-D'), '-');
select test.eq('explicit role recipients are unaffected', test.who('["role:VIEWER"]'), 'fb_viewer@bfcl.test');
select test.eq('4-argument resolver equals the 5-argument one without a department', (select count(*) from app.resolve_recipients('["owner"]', null, (select id from public.entity where code='E1'), (select id from public.location where code='L-E1'))), (select count(*) from app.resolve_recipients('["owner"]', null, (select id from public.entity where code='E1'), (select id from public.location where code='L-E1'), null)));

-- reconfigure through the audited config API
select test.login('admin@bfcl.test');
select test.denied('owner is not allowed inside the fallback', $$select public.config_new_version('alert_rule','OWNER_FALLBACK','Owner fallback recipients','{"applies":"compliance","offsets":[0],"channels":["in_app"],"recipients":["owner"]}','r',null)$$);
select public.config_new_version('alert_rule','OWNER_FALLBACK','Owner fallback recipients','{"applies":"compliance","offsets":[0],"channels":["in_app"],"recipients":["role:VIEWER"]}','route to viewers',null);
select test.logout();
select test.eq('after reconfiguration the fallback follows the configuration, not Head HR', test.who('["owner"]'), 'fb_viewer@bfcl.test');
select test.eq('the new version is stored with its reason and is audited', (select count(*) from public.config_definition c where c.code = 'OWNER_FALLBACK' and c.change_reason = 'route to viewers' and exists (select 1 from public.audit_log a where a.table_name = 'config_definition' and a.record_id = c.id::text and a.action = 'INSERT')), 1::bigint);

-- no fallback configured -> nobody (the alert then falls to D-001 handling) and validation says so
select test.login('admin@bfcl.test');
select public.config_new_version('alert_rule','OWNER_FALLBACK','Owner fallback recipients','{"applies":"compliance","offsets":[0],"channels":["in_app"],"recipients":["user:00000000-0000-0000-0000-000000000000"]}','nobody valid',null);
select test.logout();
select test.eq('a fallback naming nobody valid resolves to nobody', test.who('["owner"]'), '-');
select test.login('admin@bfcl.test');
select test.eq('validation flags the unusable fallback', (select count(*) from public.alert_routing_validation() where rule_code = 'OWNER_FALLBACK' and problem like '%no valid routing%'), 1::bigint);
select test.logout();
update public.config_definition set status = 'retired' where kind = 'alert_rule' and code = 'OWNER_FALLBACK';
select test.login('admin@bfcl.test');
select test.eq('validation warns when the fallback is not configured at all', (select count(*) from public.alert_routing_validation() where rule_code = 'OWNER_FALLBACK' and problem like 'not configured%'), 1::bigint);
select test.logout();
select test.eq('and with no fallback an ownerless alert reaches nobody', test.who('["owner"]'), '-');
rollback;
\echo ALL OWNER FALLBACK TESTS PASSED
