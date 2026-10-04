-- Register export: separate permission, append-only log, own-or-audit visibility, fail-closed. Rolled back.
\set ON_ERROR_STOP on
begin;
select test.eq('report.export exists', (select count(*) from public.permission where code = 'report.export'), 1::bigint);
select test.eq('granted by default to SUPER_ADMIN and HEAD_HR only', (select string_agg(r.code, ',' order by r.code) from public.role_permission rp join public.role r on r.id = rp.role_id where rp.permission_code = 'report.export'), 'HEAD_HR,SUPER_ADMIN');

select test.login('viewer@bfcl.test');
select test.denied('a user without report.export cannot record (so cannot export)', $$select public.export_record('compliance', '{}', 3, false)$$);
select test.denied('nor insert into the log directly', $$insert into public.export_log(user_id, register, row_count) values (app.current_user_id(), 'compliance', 1)$$);
select test.logout();

select test.login('headhr@bfcl.test');
select public.export_record('compliance', '{"status":"open"}', 12, false);
select public.export_record('licences', '{}', 10000, true);
select test.eq('log keeps who, what, filters, count and truncation', (select count(*) from public.v_export_log where register = 'compliance' and row_count = 12 and not limit_reached and filters = '{"status":"open"}'::jsonb and user_email = 'headhr@bfcl.test'), 1::bigint);
select test.eq('truncation is recorded', (select count(*) from public.v_export_log where register = 'licences' and limit_reached), 1::bigint);
select test.denied('register names are validated', $$select public.export_record('Bad Name!', '{}', 1, false)$$);
select test.denied('negative counts are refused', $$select public.export_record('compliance', '{}', -1, false)$$);
select test.denied('cannot log on behalf of another user', $$insert into public.export_log(user_id, register, row_count) select id, 'compliance', 1 from public.app_user where email = 'admin@bfcl.test'$$);
select test.denied('log rows cannot be edited', $$update public.export_log set row_count = 0$$);
select test.denied('log rows cannot be deleted', $$delete from public.export_log$$);
select test.logout();

select test.login('admin@bfcl.test');
select public.export_record('exceptions', '{}', 4, false);
select test.eq('audit.read holders see everyone''s exports (HEAD_HR + admin)', (select count(distinct user_email) from public.v_export_log), 2::bigint);
select test.logout();
select test.login('plant@bfcl.test');
select test.eq('others see only their own (none)', (select count(*) from public.v_export_log), 0::bigint);
select test.logout();
rollback;
\echo ALL REGISTER EXPORT TESTS PASSED
