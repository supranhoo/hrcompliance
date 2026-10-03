-- UI status RPCs: reason capture, configured transitions, scope, permission.
\set ON_ERROR_STOP on
create temp table _s as select test.mk_d('L-E1', current_date + 5, 'open') id;
create temp table _s2 as select test.mk_d('L-E2', current_date + 5, 'open') id;
grant select on _s, _s2 to authenticated;
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_HR' on conflict do nothing;

select test.login('plant@bfcl.test');
select public.compliance_set_status((select id from _s), 'in_progress');
select test.eq('simple transition works', (select status from public.compliance_instance where id=(select id from _s)), 'in_progress');
select public.compliance_set_status((select id from _s), 'completed');
select test.eq('completion stamps date', (select completed_on from public.compliance_instance where id=(select id from _s)), current_date);
select test.denied('reopen without reason is refused', $$select public.compliance_set_status((select id from _s), 'open')$$);
select public.compliance_set_status((select id from _s), 'open', 'filed under the wrong period');
select test.eq('reopen with reason works', (select status from public.compliance_instance where id=(select id from _s)), 'open');
select test.denied('transition not configured (open -> open style / unknown status)', $$select public.compliance_set_status((select id from _s), 'archived')$$);
select test.denied('out-of-scope obligation is "not found" for a scoped user', $$select public.compliance_set_status((select id from _s2), 'in_progress')$$);
select test.denied('not_applicable needs a reason', $$select public.compliance_set_status((select id from _s), 'not_applicable')$$);
select public.compliance_set_status((select id from _s), 'not_applicable', 'site closed for the period');
select test.logout();
select test.eq('reason captured in the audit log', (select reason from public.audit_log where table_name='compliance_instance' and action='UPDATE' and new_data ->> 'status' = 'not_applicable' order by id desc limit 1), 'site closed for the period');
select test.eq('reason does not leak to later statements', coalesce(current_setting('app.audit_reason', true), ''), '');

select test.login('viewer@bfcl.test');
select test.denied('viewer cannot change status (no permission/scope)', $$select public.compliance_set_status((select id from _s), 'in_progress')$$);
select test.logout();
select test.login('stranger@gmail.com');
select test.denied('unprovisioned cannot change status', $$select public.compliance_set_status((select id from _s), 'in_progress')$$);
select test.logout();

-- exceptions
select app.detect_exceptions();
create temp table _x as select id from public.exception where status='open' and source='auto' order by detected_at limit 1;
grant select on _x to authenticated;
select test.login('headhr@bfcl.test');
select public.exception_set_status((select id from _x), 'acknowledged', 'looking into it');
select test.eq('acknowledge', (select status from public.exception where id=(select id from _x)), 'acknowledged');
select test.denied('resolving needs a note', $$select public.exception_set_status((select id from _x), 'resolved')$$);
select test.denied('resolving with a blank note is refused', $$select public.exception_set_status((select id from _x), 'resolved', '   ')$$);
select public.exception_set_status((select id from _x), 'resolved', 'regularised with the authority');
select test.eq('resolution stored', (select resolution from public.exception where id=(select id from _x)), 'regularised with the authority');
select test.eq('timeline records the transition and note', (select count(*) from public.exception_action where exception_id=(select id from _x) and action_type='status_change' and note like '%regularised with the authority%'), 1::bigint);
select test.denied('reopen needs a reason', $$select public.exception_set_status((select id from _x), 'open')$$);
select public.exception_set_status((select id from _x), 'open', 'issue recurred');
select test.eq('reopened clears the resolution', (select resolution is null from public.exception where id=(select id from _x)), true);
select test.logout();
select test.login('viewer@bfcl.test');
select test.denied('viewer cannot change exceptions', $$select public.exception_set_status((select id from _x), 'acknowledged')$$);
select test.logout();
\echo ALL STATUS RPC TESTS PASSED
