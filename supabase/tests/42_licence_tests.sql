-- Licence master: ids, constraints, derived expiry state, scope, append-only events.
\set ON_ERROR_STOP on
-- ---------- pure functions ----------
select test.eq('bucket: expired', app.expiry_bucket(-1, array[90,60,30,15,7]), 'expired');
select test.eq('bucket: today is within_7', app.expiry_bucket(0, array[90,60,30,15,7]), 'within_7');
select test.eq('bucket: 7 -> within_7 (boundary)', app.expiry_bucket(7, array[90,60,30,15,7]), 'within_7');
select test.eq('bucket: 8 -> within_15', app.expiry_bucket(8, array[90,60,30,15,7]), 'within_15');
select test.eq('bucket: 30 -> within_30', app.expiry_bucket(30, array[90,60,30,15,7]), 'within_30');
select test.eq('bucket: 90 -> within_90', app.expiry_bucket(90, array[90,60,30,15,7]), 'within_90');
select test.eq('bucket: 91 -> valid', app.expiry_bucket(91, array[90,60,30,15,7]), 'valid');
select test.eq('bucket: no expiry', app.expiry_bucket(null, array[90,60,30,15,7]), 'no_expiry');
select test.eq('thresholds read from system_config (sorted desc)', app.licence_thresholds(), array[90,60,30,15,7]);

-- ---------- fixtures ----------
insert into public.authority (code, name) values ('AUTH-1', 'Test Authority'), ('AUTH-2', 'Other Authority');
insert into public.licence_type (code, name, authority_id, default_risk) select 'LT-FACT', 'Sample licence type', id, 'high' from public.authority where code='AUTH-1';
create temp table _lt as select id from public.licence_type where code='LT-FACT';
grant select on _lt to authenticated;
create or replace function test.mk_lic(p_loc text, p_expiry date, p_num text default null) returns uuid language sql as $$
  insert into public.licence (licence_type_id, entity_id, location_id, authority_id, licence_number, issue_date, expiry_date)
  select (select id from _lt), l.entity_id, l.id, (select id from public.authority where code='AUTH-1'), p_num, date '2020-01-01', p_expiry from public.location l where l.code = p_loc
  returning id $$;
grant execute on all functions in schema test to authenticated, anon;

select test.login('admin@bfcl.test');
-- ---------- ids + constraints ----------
select test.denied('licence type risk must be a LOV value', $$insert into public.licence_type(code,name,default_risk) values ('LT-BAD','x','extreme')$$);
select test.mk_lic('L-E1', current_date + 3, 'NO-1');
select test.eq('first licence gets LIC-000001', (select licence_no from public.licence where licence_number='NO-1'), 'LIC-000001');
select test.mk_lic('L-E1', current_date + 20, 'NO-2');
select test.eq('second licence gets LIC-000002', (select licence_no from public.licence where licence_number='NO-2'), 'LIC-000002');
select test.denied('same authority + licence number rejected', $$select test.mk_lic('L-E1B', current_date + 5, 'NO-1')$$);
select test.mk_lic('L-E1B', current_date + 100);
select test.mk_lic('L-E1B', current_date + 100);
select test.eq('licences without a number may repeat (no false duplicates)', (select count(*) from public.licence where licence_number is null), 2::bigint);
select test.denied('expiry before issue rejected', $$insert into public.licence(licence_type_id,entity_id,issue_date,expiry_date) select (select id from _lt), id, date '2026-02-01', date '2026-01-01' from public.entity where code='E1'$$);
select test.denied('renewal status must be a LOV value', $$update public.licence set renewal_status='maybe' where licence_number='NO-1'$$);
select test.denied('licence_no is immutable', $$update public.licence set licence_no='LIC-999999' where licence_number='NO-1'$$);
select test.denied('licence cannot change entity', $$update public.licence set entity_id=(select id from public.entity where code='E2') where licence_number='NO-1'$$);
select test.denied('risk must be a LOV value', $$update public.licence set risk_level='extreme' where licence_number='NO-1'$$);
update public.licence set risk_level='high', renewal_lead_days=30 where licence_number='NO-1';

-- ---------- derived state ----------
select test.mk_lic('L-E2', current_date - 5, 'NO-OLD');
select test.eq('expired category', (select expiry_category from public.v_licence_status where licence_number='NO-OLD'), 'expired');
select test.eq('days_to_expiry negative', (select days_to_expiry from public.v_licence_status where licence_number='NO-OLD'), -5);
select test.eq('within_7 category', (select expiry_category from public.v_licence_status where licence_number='NO-1'), 'within_7');
select test.eq('within_30 category', (select expiry_category from public.v_licence_status where licence_number='NO-2'), 'within_30');
select test.eq('renewal window open (3d left, lead 30d)', (select renewal_window_open from public.v_licence_status where licence_number='NO-1'), true);
select test.eq('renewal window closed (100d left, lead 60d)', (select renewal_window_open from public.v_licence_status where expiry_date = current_date + 100 limit 1), false);
update public.system_config set value='[45,10]' where key='licence.expiry_thresholds';
select test.eq('thresholds are configuration, not code', (select expiry_category from public.v_licence_status where licence_number='NO-2'), 'within_45');
select test.eq('configured threshold applies', (select expiry_category from public.v_licence_status where licence_number='NO-1'), 'within_10');
update public.system_config set value='[90,60,30,15,7]' where key='licence.expiry_thresholds';
update public.licence set lifecycle_status='cancelled' where licence_number='NO-OLD';
select test.eq('cancelled licence reports lifecycle, not expiry', (select expiry_category from public.v_licence_status where licence_number='NO-OLD'), 'cancelled');
insert into public.licence_type (code, name, has_expiry) values ('LT-PERP','Perpetual registration', false);
insert into public.licence (licence_type_id, entity_id, licence_number) select t.id, e.id, 'PERP-1' from public.licence_type t, public.entity e where t.code='LT-PERP' and e.code='E1';
select test.eq('no expiry date -> no_expiry', (select expiry_category from public.v_licence_status where licence_number='PERP-1'), 'no_expiry');

-- ---------- renewal chain + events ----------
insert into public.licence (licence_type_id, entity_id, location_id, authority_id, licence_number, expiry_date, supersedes_id, renewal_status)
  select (select id from _lt), l.entity_id, l.id, (select id from public.authority where code='AUTH-1'), 'NO-1-R', current_date + 365, o.id, 'renewed'
    from public.licence o join public.location l on l.id = o.location_id where o.licence_number='NO-1';
select test.eq('renewal links to predecessor', (select p.licence_number from public.licence n join public.licence p on p.id=n.supersedes_id where n.licence_number='NO-1-R'), 'NO-1');
insert into public.licence_event (licence_id, event_type, event_date, description) select id, 'renewal_applied', current_date, 'applied online' from public.licence where licence_number='NO-1';
select test.eq('event recorded', (select count(*) from public.licence_event), 1::bigint);
select test.denied('events are append-only (update)', $$update public.licence_event set description='x'$$);
select test.denied('events are append-only (delete)', $$delete from public.licence_event$$);
select test.denied('bad event type rejected', $$insert into public.licence_event(licence_id,event_type,event_date) select id,'hacked',current_date from public.licence limit 1$$);
select test.logout();

-- ---------- access + scope ----------
create temp table _lic1 as select id from public.licence order by licence_no limit 1;
grant select on _lic1 to authenticated;
select test.login('viewer@bfcl.test');
select test.eq('viewer has licence.read but NO scope -> sees nothing (fail closed)', test.count('select * from public.licence'), 0::bigint);
select test.eq('viewer without scope sees nothing in the derived view either', test.count('select * from public.v_licence_status'), 0::bigint);
select test.denied('viewer cannot create licence', $$insert into public.licence(licence_type_id,entity_id) select (select id from _lt), id from public.entity limit 1$$);
select test.denied('viewer cannot log events', $$insert into public.licence_event(licence_id,event_type,event_date) select id,'note',current_date from _lic1$$);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('unrestricted user reads all licences', test.count('select * from public.licence'), 7::bigint);
select test.eq('unrestricted user reads derived view', test.count('select * from public.v_licence_status'), 7::bigint);
select test.logout();
select test.login('stranger@gmail.com');
select test.eq('unprovisioned sees no licences', test.count('select * from public.licence'), 0::bigint);
select test.eq('unprovisioned sees no licence view rows', test.count('select * from public.v_licence_status'), 0::bigint);
select test.logout();
-- isolate from the previous suite's fixture: plant loses PLANT_MGR (compliance.manage)
delete from public.user_role where user_id=(select id from public.app_user where email='plant@bfcl.test') and role_id=(select id from public.role where code='PLANT_MGR');
-- plant@bfcl.test: Entity-One-scoped; give licence rights via PLANT_HR role (licence.read/write)
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_HR' on conflict do nothing;
select test.login('plant@bfcl.test');
select test.eq('scoped user sees only own-entity licences', test.count($$select 1 from public.licence l join public.entity e on e.id=l.entity_id where e.code='E2'$$), 0::bigint);
select test.eq('scoped user sees E1 licences', test.count($$select 1 from public.licence l join public.entity e on e.id=l.entity_id where e.code='E1'$$) > 0, true);
select test.eq('scoped user view also scoped', test.count($$select 1 from public.v_licence_status where licence_number='NO-OLD'$$), 0::bigint);
insert into public.licence (licence_type_id, entity_id, location_id, licence_number) select (select id from _lt), l.entity_id, l.id, 'SCOPED-OK' from public.location l where l.code='L-E1';
select test.eq('scoped user can create inside scope', test.count($$select 1 from public.licence where licence_number='SCOPED-OK'$$), 1::bigint);
select test.denied('scoped user cannot create for another entity', $$insert into public.licence(licence_type_id,entity_id,location_id) select (select id from _lt), l.entity_id, l.id from public.location l where l.code='L-E2'$$);
update public.licence set remarks='tamper' where licence_number='NO-OLD';
select test.denied('scoped user cannot create licence types', $$insert into public.licence_type(code,name) values ('LT-X','x')$$);
select test.logout();
select test.eq('scoped user cannot update other entity licence (row untouched, verified as owner)', (select remarks is null from public.licence where licence_number='NO-OLD'), true);
select test.eq('licence changes audited', (select count(*) from public.audit_log where table_name='licence') >= 7, true);
\echo ALL LICENCE TESTS PASSED
