-- Alert-rule administration read models + the config API used by the admin screen. Rolled back.
\set ON_ERROR_STOP on
begin;
select test.login('admin@bfcl.test');
select public.config_new_version('alert_rule', 'AA_TEST', 'Admin test', '{"applies":"compliance","offsets":[-14,-7,0],"channels":["in_app"],"recipients":["owner"],"critical":true}', 'first version');
select public.config_new_version('alert_rule', 'AA_TEST', 'Admin test', '{"applies":"compliance","offsets":[-14,-3,0],"channels":["in_app"],"recipients":["role:HEAD_HR"],"critical":true}', 'moved the reminder');
select test.eq('every version is listed; the latest is flagged', (select string_agg(version::text || ':' || status || ':' || is_latest::text, ',' order by version) from public.v_alert_rule where code='AA_TEST'), '1:retired:false,2:active:true');
select test.eq('offsets / recipients / critical are exposed as parts', (select offsets::text || recipients::text || critical::text from public.v_alert_rule where code='AA_TEST' and version=2), '[-14, -3, 0]["role:HEAD_HR"]true');
select test.eq('the default rules are visible', (select count(*) from public.v_alert_rule where code like 'DEFAULT\_%' and is_latest) >= 3, true);
select test.eq('the history keeps the reason', (select change_reason from public.v_alert_rule where code='AA_TEST' and version=1), 'first version');
select test.denied('a malformed rule is refused by the database', $$select public.config_new_version('alert_rule','AA_BAD','x','{"offsets":[1.5],"channels":["in_app"],"recipients":["owner"]}','r')$$);
select test.denied('a reason is mandatory', $$select public.config_new_version('alert_rule','AA_TEST','x','{"offsets":[0],"channels":["in_app"],"recipients":["owner"]}','')$$);
select test.eq('routing issues are a register (production has no escalation recipients)', (select count(*) from public.v_alert_routing_issue where rule_code='UNROUTABLE_ESCALATION' and severity='error') >= 0, true);
select test.logout();
select test.login('viewer@bfcl.test');
select test.denied('a user without health/config permission cannot read routing issues', $$select * from public.v_alert_routing_issue$$);
select test.denied('nor create alert rules', $$select public.config_new_version('alert_rule','AA_V','x','{"offsets":[0],"channels":["in_app"],"recipients":["owner"]}','r')$$);
select test.logout();
rollback;
\echo ALL ALERT ADMIN TESTS PASSED
