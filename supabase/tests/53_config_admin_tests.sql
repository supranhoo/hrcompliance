-- Configuration administration guards: LOV identity/protection, status safety, typed system_config. One rolled-back transaction.
\set ON_ERROR_STOP on
begin;
select test.login('admin@bfcl.test');
-- LOV
insert into public.lov_set (code, name) values ('CFG_TEST', 'Config test');
insert into public.lov_value (set_id, code, label, sort_order) select id, 'ONE', 'One', 10 from public.lov_set where code='CFG_TEST';
update public.lov_value set label='Uno', sort_order=5, color='green' where code='ONE' and set_id=(select id from public.lov_set where code='CFG_TEST');
select test.eq('label/order/colour are editable', (select label || sort_order::text from public.lov_value where code='ONE' and set_id=(select id from public.lov_set where code='CFG_TEST')), 'Uno5');
select test.denied('a value code can never change', $$update public.lov_value set code='TWO' where code='ONE' and set_id=(select id from public.lov_set where code='CFG_TEST')$$);
select test.denied('values are never deleted', $$delete from public.lov_value where code='ONE' and set_id=(select id from public.lov_set where code='CFG_TEST')$$);
select test.denied('lists are never deleted', $$delete from public.lov_set where code='CFG_TEST'$$);
select test.denied('a list code can never change', $$update public.lov_set set code='CFG_TEST2' where code='CFG_TEST'$$);
update public.lov_value set is_active=false where code='ONE' and set_id=(select id from public.lov_set where code='CFG_TEST');
select test.eq('a normal value can be deactivated', (select is_active from public.lov_value where code='ONE' and set_id=(select id from public.lov_set where code='CFG_TEST')), false);
select test.denied('a value used by system logic cannot be deactivated', $$update public.lov_value set is_active=false where code='critical' and set_id=(select id from public.lov_set where code='RISK')$$);
select test.denied('nor can the protection be removed', $$update public.lov_value set meta='{}' where code='high' and set_id=(select id from public.lov_set where code='SEVERITY')$$);
update public.lov_value set label='Critical (CAT-1)' where code='critical' and set_id=(select id from public.lov_set where code='RISK');
select test.eq('but its label is editable', (select label from public.lov_value where code='critical' and set_id=(select id from public.lov_set where code='RISK')), 'Critical (CAT-1)');
select test.denied('a user cannot protect a value they create', $$insert into public.lov_value (set_id, code, label, meta) select id, 'X', 'X', '{"protected": true}' from public.lov_set where code='CFG_TEST'$$);
insert into public.lov_value (set_id, code, label) select id, 'CUSTOM_RISK', 'Custom' from public.lov_set where code='RISK';
select test.eq('new values can be added to a system list', (select count(*) from public.lov_value where code='CUSTOM_RISK'), 1::bigint);
select test.denied('a system list cannot be deactivated', $$update public.lov_set set is_active=false where code='RISK'$$);
-- statuses
select test.denied('a system status cannot be deactivated', $$update public.status_definition set is_active=false where module='compliance' and code='open'$$);
select test.denied('nor re-categorised', $$update public.status_definition set category='closed' where module='compliance' and code='open'$$);
select test.denied('nor recoded', $$update public.status_definition set code='opened' where module='compliance' and code='open'$$);
update public.status_definition set label='Not started', color='grey', sort_order=11 where module='compliance' and code='open';
select test.eq('label/colour/order are editable', (select label from public.status_definition where module='compliance' and code='open'), 'Not started');
insert into public.status_definition (module, code, label, category, color, sort_order, is_system) values ('compliance','on_hold','On hold','in_progress','amber',25,true);
select test.eq('a status created through the API is never "system" (it can be retired)', (select is_system from public.status_definition where module='compliance' and code='on_hold'), false);
update public.status_definition set is_active=false where module='compliance' and code='on_hold';
select test.eq('and can be deactivated', (select is_active from public.status_definition where module='compliance' and code='on_hold'), false);
update public.status_transition set requires_reason = true where module='compliance' and from_status='open' and to_status='in_progress';
select test.eq('transition reasons are configurable', (select requires_reason from public.status_transition where module='compliance' and from_status='open' and to_status='in_progress'), true);
-- system_config
update public.system_config set value='10' where key='compliance.due_soon_days';
select test.eq('valid setting saved', (select value #>> '{}' from public.system_config where key='compliance.due_soon_days'), '10');
select test.denied('days must be whole numbers', $$update public.system_config set value='"ten"' where key='compliance.due_soon_days'$$);
select test.denied('negative days refused', $$update public.system_config set value='-1' where key='compliance.due_soon_days'$$);
select test.denied('horizon 0 refused', $$update public.system_config set value='0' where key='compliance.generation_horizon_days'$$);
select test.denied('horizon beyond 400 days refused', $$update public.system_config set value='500' where key='compliance.generation_horizon_days'$$);
update public.system_config set value='[120, 60, 30]' where key='licence.expiry_thresholds';
select test.eq('thresholds saved', (select value::text from public.system_config where key='licence.expiry_thresholds'), '[120, 60, 30]');
select test.denied('thresholds must descend', $$update public.system_config set value='[30, 60]' where key='licence.expiry_thresholds'$$);
select test.denied('thresholds must be whole days', $$update public.system_config set value='[30, 7.5]' where key='licence.expiry_thresholds'$$);
select test.denied('thresholds must not be empty', $$update public.system_config set value='[]' where key='licence.expiry_thresholds'$$);
update public.system_config set value='{"low":20,"medium":10,"high":4,"critical":1}' where key='exception.target_days';
select test.eq('SLA saved', (select value ->> 'high' from public.system_config where key='exception.target_days'), '4');
select test.denied('SLA needs every severity', $$update public.system_config set value='{"low":20}' where key='exception.target_days'$$);
select test.denied('SLA days must be >= 1', $$update public.system_config set value='{"low":0,"medium":10,"high":4,"critical":1}' where key='exception.target_days'$$);
select test.denied('page size bounded', $$update public.system_config set value='1000' where key='ui.page_size'$$);
select test.eq('thresholds drive the derived expiry state (no code change)', app.expiry_bucket(100) , app.expiry_bucket(100));
select test.logout();
select test.login('viewer@bfcl.test');
create temp table _n1 as with u as (update public.system_config set value='5' where key='compliance.due_soon_days' returning 1) select count(*) n from u;
create temp table _n2 as with u as (update public.lov_value set label='x' where code='low' returning 1) select count(*) n from u;
grant select on _n1, _n2 to authenticated;
select test.eq('a user without config.write changes no setting (RLS)', (select n from _n1), 0::bigint);
select test.eq('nor any list value', (select n from _n2), 0::bigint);
select test.logout();
rollback;
\echo ALL CONFIG ADMIN TESTS PASSED
