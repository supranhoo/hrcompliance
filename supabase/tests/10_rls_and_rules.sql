-- Negative + positive security/integrity tests. Run by scripts/validation/db-test.sh against a throwaway DB.
\set ON_ERROR_STOP on
create schema test;
create or replace function test.login(p_email text) returns void language plpgsql as $$
declare v uuid;
begin
  select id into v from auth.users where email = p_email;
  perform set_config('request.jwt.claim.sub', coalesce(v::text, ''), false);
  execute 'set role authenticated';
end $$;
create or replace function test.logout() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false); end $$;
create or replace function test.eq(label text, actual anyelement, expected anyelement) returns void language plpgsql as $$
begin
  if actual is distinct from expected then raise exception 'FAIL [%]: expected %, got %', label, expected, actual; end if;
  raise notice 'ok   - %', label;
end $$;
-- Passes only if the statement raises (RLS violation / permission denied / constraint).
create or replace function test.denied(label text, stmt text) returns void language plpgsql as $$
begin
  begin execute stmt; exception when others then raise notice 'ok   - % (%)', label, sqlerrm; return; end;
  raise exception 'FAIL [%]: statement was allowed: %', label, stmt;
end $$;
create or replace function test.count(stmt text) returns bigint language plpgsql as $$
declare n bigint; begin execute 'select count(*) from (' || stmt || ') q' into n; return n; end $$;
grant usage on schema test to authenticated, anon;
grant execute on all functions in schema test to authenticated, anon;

-- ---------- fixtures (as superuser) ----------
insert into public.entity (code, name) values ('E1','Entity One'), ('E2','Entity Two');
insert into public.location (entity_id, code, name) select id, 'L-E1', 'Loc E1' from public.entity where code='E1';
insert into public.location (entity_id, code, name) select id, 'L-E2', 'Loc E2' from public.entity where code='E2';

insert into public.app_user (email, full_name, scope_all) values
  ('admin@bfcl.test','Admin',true), ('headhr@bfcl.test','Head HR',true),
  ('plant@bfcl.test','Plant HR',false), ('viewer@bfcl.test','Viewer',false), ('off@bfcl.test','Disabled',false);
update public.app_user set status='disabled' where email='off@bfcl.test';
insert into public.user_role select u.id, r.id from public.app_user u join public.role r on
  (u.email='admin@bfcl.test' and r.code='SUPER_ADMIN') or (u.email='headhr@bfcl.test' and r.code='HEAD_HR')
  or (u.email='plant@bfcl.test' and r.code='PLANT_HR') or (u.email='viewer@bfcl.test' and r.code='VIEWER')
  or (u.email='off@bfcl.test' and r.code='SUPER_ADMIN');
-- plant HR is scoped to Entity One only, with write rights granted via a custom role
insert into public.role (code, name) values ('PLANT_WRITER','Plant writer');
insert into public.role_permission select r.id, 'master.write' from public.role r where r.code='PLANT_WRITER';
insert into public.role_permission select r.id, 'master.read' from public.role r where r.code='PLANT_WRITER';
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_WRITER';
insert into public.user_scope (user_id, scope_type, scope_id)
  select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email='plant@bfcl.test' and e.code='E1';

-- Simulate first Google login (mixed-case email must still link). 'stranger' has no app_user row.
insert into auth.users (email) values ('Admin@BFCL.test'), ('headhr@bfcl.test'), ('plant@bfcl.test'), ('viewer@bfcl.test'), ('off@bfcl.test'), ('stranger@gmail.com');
-- normalise the test lookup used by test.login
update auth.users set email = lower(email);

select test.eq('login links all 5 pre-provisioned users (incl. disabled)', (select count(*) from public.app_user where auth_user_id is not null), 5::bigint);
select test.eq('invited -> active on first login', (select status from public.app_user where email='admin@bfcl.test'), 'active');
select test.eq('disabled user stays disabled', (select status from public.app_user where email='off@bfcl.test'), 'disabled');
select test.eq('unprovisioned Google account gets no app_user', (select count(*) from public.app_user where email='stranger@gmail.com'), 0::bigint);

-- ---------- anon ----------
set role anon;
select test.denied('anon cannot read entity', 'select * from public.entity');
select test.denied('anon cannot read audit_log', 'select * from public.audit_log');
select test.denied('anon cannot call my_access', 'select public.my_access()');
reset role;

-- ---------- unprovisioned authenticated user fails closed ----------
select test.login('stranger@gmail.com');
select test.eq('stranger sees 0 entities', test.count('select * from public.entity'), 0::bigint);
select test.eq('stranger sees 0 lov sets', test.count('select * from public.lov_set'), 0::bigint);
select test.eq('stranger my_access empty', public.my_access(), '{}'::jsonb);
select test.denied('stranger cannot insert entity', $$insert into public.entity(code,name) values ('X','x')$$);
select test.logout();

-- ---------- disabled user ----------
select test.login('off@bfcl.test');
select test.eq('disabled super admin sees 0 entities', test.count('select * from public.entity'), 0::bigint);
select test.logout();

-- ---------- viewer: read only ----------
select test.login('viewer@bfcl.test');
select test.eq('viewer reads entities', test.count('select * from public.entity'), 2::bigint);
select test.denied('viewer cannot insert entity', $$insert into public.entity(code,name) values ('X','x')$$);
update public.entity set name='hacked' where code='E1';
select test.eq('viewer update affects 0 rows', (select name from public.entity where code='E1'), 'Entity One');
select test.denied('viewer has no DELETE privilege on entity', 'delete from public.entity');
select test.denied('viewer has no TRUNCATE privilege on entity', 'truncate public.entity');
select test.denied('viewer cannot write config', $$insert into public.lov_set(code,name) values ('ZZZ','z')$$);
select test.eq('viewer cannot see audit', test.count('select * from public.audit_log'), 0::bigint);
select test.eq('viewer cannot see other users', test.count('select * from public.app_user'), 1::bigint);
select test.denied('viewer cannot self-grant role', $$insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='viewer@bfcl.test' and r.code='SUPER_ADMIN'$$);
select test.denied('viewer cannot touch number_counter', 'select * from public.number_counter');
select test.denied('viewer cannot call app.next_business_id', $$select app.next_business_id('CMP')$$);
select test.logout();

-- ---------- scoped writer: location writes limited to scope ----------
select test.login('plant@bfcl.test');
select test.eq('plant sees locations (master.read)', test.count('select * from public.location'), 2::bigint);
insert into public.location (entity_id, code, name) select id, 'L-E1B', 'Second E1' from public.entity where code='E1';
select test.eq('plant inserted location inside scope', test.count($$select 1 from public.location where code='L-E1B'$$), 1::bigint);
select test.denied('plant cannot insert location outside scope', $$insert into public.location (entity_id, code, name) select id, 'L-E2B', 'x' from public.entity where code='E2'$$);
update public.location set name='tamper' where code='L-E2';
select test.eq('plant cannot update out-of-scope location', (select name from public.location where code='L-E2'), 'Loc E2');
select test.denied('plant cannot move location into other entity', $$update public.location set entity_id=(select id from public.entity where code='E2') where code='L-E1B'$$);
select test.denied('plant lacks config.write', $$insert into public.lov_set(code,name) values ('ZZZ','z')$$);
select test.logout();

-- ---------- super admin ----------
select test.login('admin@bfcl.test');
insert into public.lov_set (code, name) values ('TEST_SET','Test');
select test.eq('admin can write config', test.count($$select 1 from public.lov_set where code='TEST_SET'$$), 1::bigint);
delete from public.lov_set where code='RISK';  -- RLS filters the row: 0 rows deleted, no error
select test.eq('system LOV set still present', test.count($$select 1 from public.lov_set where code='RISK'$$), 1::bigint);
select test.eq('admin my_access has user.admin', public.my_access() -> 'permissions' ? 'user.admin', true);
update public.role set name='x' where code='SUPER_ADMIN';
select test.eq('system role cannot be edited', (select name from public.role where code='SUPER_ADMIN'), 'Super Admin');
select test.denied('audit_log not writable by admin', $$insert into public.audit_log(table_name,record_id,action) values ('x','y','INSERT')$$);
select test.denied('audit_log not updatable by admin', $$update public.audit_log set reason='x'$$);
select test.denied('audit_log not deletable by admin', $$delete from public.audit_log$$);
select test.logout();

-- ---------- audit content ----------
select test.eq('audit captured entity insert', (select count(*) from public.audit_log where table_name='entity' and action='INSERT'), 2::bigint);
begin;
  select set_config('app.audit_reason', 'rename after registry update', true);
  update public.entity set name = 'Entity One Ltd' where code = 'E1';
  update public.entity set name = name where code = 'E2';  -- no-op: must not create audit noise
commit;
select test.eq('audit UPDATE records changed field', (select changed_fields from public.audit_log where table_name='entity' and action='UPDATE' order by id desc limit 1), array['name']);
select test.eq('audit UPDATE records reason', (select reason from public.audit_log where table_name='entity' and action='UPDATE' order by id desc limit 1), 'rename after registry update');
select test.eq('no-op update creates no audit row', (select count(*) from public.audit_log where table_name='entity' and action='UPDATE'), 1::bigint);
select test.eq('row_version incremented', (select row_version from public.entity where code='E1'), 2);
select test.denied('owner cannot UPDATE audit_log', $$update public.audit_log set reason='x'$$);
select test.denied('owner cannot DELETE audit_log', $$delete from public.audit_log$$);
select test.denied('owner cannot TRUNCATE audit_log', $$truncate public.audit_log$$);
select test.login('headhr@bfcl.test');
select test.eq('Head HR (audit.read) can read audit', test.count('select * from public.audit_log') > 0, true);
select test.logout();

-- ---------- business ids ----------
select test.eq('yearly id format', app.next_business_id('CMP', date '2026-05-01'), 'CMP-2026-000001');
select test.eq('yearly id increments', app.next_business_id('CMP', date '2026-12-31'), 'CMP-2026-000002');
select test.eq('yearly id resets in new year', app.next_business_id('CMP', date '2027-01-01'), 'CMP-2027-000001');
select test.eq('non-resetting id format', app.next_business_id('CTR'), 'CTR-000001');
select test.denied('unknown rule rejected', $$select app.next_business_id('NOPE')$$);

-- ---------- rule validator (no arbitrary code) ----------
select test.eq('valid nested rule', app.rule_is_valid('{"op":"and","args":[{"op":"eq","field":"location.state","value":"X"},{"op":"within_days","field":"due_date","value":30}]}'), true);
select test.eq('unknown operator rejected', app.rule_is_valid('{"op":"exec","field":"a","value":"1"}'), false);
select test.eq('sql-ish field name rejected', app.rule_is_valid('{"op":"eq","field":"a; drop table x","value":"1"}'), false);
select test.eq('object value rejected', app.rule_is_valid('{"op":"eq","field":"a","value":{"$fn":"x"}}'), false);
select test.eq('empty and rejected', app.rule_is_valid('{"op":"and","args":[]}'), false);
select test.eq('is_blank with value rejected', app.rule_is_valid('{"op":"is_blank","field":"a","value":1}'), false);
select test.eq('in needs array', app.rule_is_valid('{"op":"in","field":"a","value":"x"}'), false);
select test.eq('excess nesting rejected', app.rule_is_valid((repeat('{"op":"and","args":[', 9) || '{"op":"eq","field":"a","value":1}' || repeat(']}', 9))::jsonb), false);
select test.eq('moderate nesting accepted', app.rule_is_valid((repeat('{"op":"and","args":[', 3) || '{"op":"eq","field":"a","value":1}' || repeat(']}', 3))::jsonb), true);
select test.denied('rule_definition CHECK enforces validator', $$insert into public.rule_definition(scope,code,name,definition) values ('applicability','R1','r','{"op":"js","field":"a","value":"1"}')$$);
insert into public.rule_definition(scope,code,name,definition) values ('applicability','R1','r','{"op":"eq","field":"state","value":"X"}');

-- ---------- field designer constraints ----------
select test.denied('select field requires LOV set', $$insert into public.field_definition(module,key,label,field_type) values ('grc','religion','Religion','single_select')$$);
insert into public.field_definition(module,key,label,field_type,lov_set_id) select 'grc','religion','Religion','single_select', id from public.lov_set where code='RISK';
select test.denied('only one live version per field key', $$insert into public.field_definition(module,key,label,field_type,version) values ('grc','religion','Religion v2','short_text',2)$$);
select test.denied('bad field key rejected', $$insert into public.field_definition(module,key,label,field_type) values ('grc','Bad Key','x','short_text')$$);
select test.denied('unknown field type rejected', $$insert into public.field_definition(module,key,label,field_type) values ('grc','k','x','javascript')$$);

-- ---------- constraints ----------
select test.denied('duplicate entity code rejected', $$insert into public.entity(code,name) values ('E1','dup')$$);
select test.denied('effective_to < effective_from rejected', $$insert into public.entity(code,name,effective_from,effective_to) values ('E9','x','2026-02-01','2026-01-01')$$);
insert into public.department(code,name) values ('D1','d');
select test.denied('department cannot be its own parent', $$update public.department set parent_id = id where code='D1'$$);
\echo ALL DB TESTS PASSED
