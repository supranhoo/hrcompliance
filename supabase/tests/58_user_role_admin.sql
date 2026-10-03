-- Users / roles / permissions / scope administration. Rolled back.
\set ON_ERROR_STOP on
begin;
-- make the starting state self-contained: admin@bfcl.test is the only role administrator, whatever earlier suites left behind
delete from public.user_role ur using public.role r, public.app_user u where r.id = ur.role_id and r.code = 'SUPER_ADMIN' and u.id = ur.user_id and u.email <> 'admin@bfcl.test';
select test.eq('SUPER_ADMIN holds role.admin', (select count(*) from public.role_permission rp join public.role r on r.id = rp.role_id where r.code = 'SUPER_ADMIN' and rp.permission_code = 'role.admin'), 1::bigint);
select test.eq('no other role holds role.admin by default', (select count(*) from public.role_permission where permission_code = 'role.admin'), 1::bigint);

-- ===== non-admins =====
select test.login('headhr@bfcl.test');
select test.denied('HEAD_HR (no admin permissions) cannot create a role', $$select public.role_save('X_ROLE','X',null,'{}','r')$$);
select test.denied('HEAD_HR cannot invite users', $$select public.user_invite('n@bfcl.test','N','{}','r')$$);
select test.denied('direct role_permission insert is blocked by RLS', $$insert into public.role_permission(role_id, permission_code) select id, 'user.admin' from public.role where code = 'HEAD_HR'$$);
select test.logout();

-- ===== SUPER_ADMIN: roles and the permission editor =====
select test.login('admin@bfcl.test');
select test.denied('reason is mandatory', $$select public.role_save('AUDITOR','Auditor','read only','{audit.read}','')$$);
select test.denied('role code format', $$select public.role_save('bad code','x',null,'{}','r')$$);
select test.denied('unknown permission refused', $$select public.role_save('AUDITOR','Auditor',null,'{no.such}','r')$$);
select public.role_save('AUDITOR','Auditor','read only','{audit.read,compliance.read}','new auditor role');
select test.eq('role created with permissions', (select permissions from public.v_role_admin where code='AUDITOR'), array['audit.read','compliance.read']);
select public.role_save('AUDITOR','Auditor','read only','{audit.read}','narrow it');
select test.eq('permission removed by the editor', (select permissions from public.v_role_admin where code='AUDITOR'), array['audit.read']);
select test.eq('role change is audited with the reason', (select count(*) from public.audit_log where table_name='role_permission' and reason='narrow it'), 1::bigint);
select test.denied('role code is immutable', $$update public.role set code='AUDITOR2' where code='AUDITOR'$$);

-- HEAD_HR's access follows permissions, not its name: grant it user.admin and it can administer users but still not roles
select public.role_save('HEAD_HR','Head HR',null, (select permissions from public.v_role_admin where code='HEAD_HR') || array['user.admin'], 'let Head HR manage users');
select test.eq('HEAD_HR now holds user.admin', (select 'user.admin' = any(permissions) from public.v_role_admin where code='HEAD_HR'), true);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('permission change takes effect (same source for RLS and my_access)', (public.my_access() -> 'permissions') ? 'user.admin', true);
select public.user_invite('New.Person@BFCL.test','New Person','{}','onboarding');
select test.eq('invited, email lower-cased', (select status || ':' || email from public.v_user_admin where email like 'new.person%'), 'invited:new.person@bfcl.test');
select test.denied('user.admin alone cannot assign roles', $$select public.user_set_roles((select id from public.app_user where email='new.person@bfcl.test'), '{VIEWER}', 'r')$$);
select test.denied('nor edit role permissions', $$select public.role_save('HEAD_HR','Head HR',null,'{role.admin}','escalate')$$);
select test.denied('nor assign itself via the table', $$insert into public.user_role(user_id, role_id) select u.id, r.id from public.app_user u, public.role r where u.email='headhr@bfcl.test' and r.code='SUPER_ADMIN'$$);
select test.denied('invalid email', $$select public.user_invite('nope','x','{}','r')$$);
select test.denied('duplicate email', $$select public.user_invite('admin@bfcl.test','x','{}','r')$$);
select test.logout();

-- ===== roles on users, scope =====
select test.login('admin@bfcl.test');
select public.user_set_roles((select id from public.app_user where email='new.person@bfcl.test'), '{VIEWER,AUDITOR}', 'initial roles');
select test.eq('roles assigned', (select roles from public.v_user_admin where email='new.person@bfcl.test'), array['AUDITOR','VIEWER']);
select test.denied('unknown role', $$select public.user_set_roles((select id from public.app_user where email='new.person@bfcl.test'), '{NOPE}', 'r')$$);
select public.user_set_roles((select id from public.app_user where email='new.person@bfcl.test'), '{VIEWER}', 'drop auditor');
select test.eq('role removed', (select roles from public.v_user_admin where email='new.person@bfcl.test'), array['VIEWER']);

select test.denied('restricted scope needs at least one entity or location', $$select public.user_set_scope((select id from public.app_user where email='new.person@bfcl.test'), false, '{}', '{}', 'r')$$);
select test.denied('unknown location', $$select public.user_set_scope((select id from public.app_user where email='new.person@bfcl.test'), false, '{}', array[gen_random_uuid()], 'r')$$);
do $$ declare ent uuid; loc uuid; begin
  select id into ent from public.entity limit 1; select id into loc from public.location limit 1;
  if ent is null or loc is null then raise exception 'test data missing'; end if;
  perform public.user_set_scope((select id from public.app_user where email='new.person@bfcl.test'), false, array[ent], array[loc], 'restrict to one entity and location');
end $$;
select test.eq('scope written', (select entity_scopes || '/' || location_scopes || '/' || scope_all from public.v_user_admin where email='new.person@bfcl.test'), '1/1/false');
select test.eq('scope view resolves names', (select count(*) from public.v_user_scope where user_id=(select id from public.app_user where email='new.person@bfcl.test') and name is not null), 2::bigint);
select public.user_set_scope((select id from public.app_user where email='new.person@bfcl.test'), true, '{}', '{}', 'all locations');
select test.eq('scope replaced', (select entity_scopes || '/' || location_scopes || '/' || scope_all from public.v_user_admin where email='new.person@bfcl.test'), '0/0/true');
select test.eq('scope change audited', (select count(*) from public.audit_log where table_name='user_scope' and reason='all locations') >= 1, true);

select public.user_set_status((select id from public.app_user where email='new.person@bfcl.test'), 'disabled', 'left');
select test.eq('disabled', (select status from public.app_user where email='new.person@bfcl.test'), 'disabled');
select public.user_set_status((select id from public.app_user where email='new.person@bfcl.test'), 'active', 'back');
select test.eq('re-enabling a never-signed-in user returns to invited', (select status from public.app_user where email='new.person@bfcl.test'), 'invited');
select test.denied('email of a signed-in user cannot change', $$update public.app_user set email='z@bfcl.test' where email='headhr@bfcl.test'$$);

-- ===== last admin / self-lockout =====
select test.denied('removing own role needs explicit confirmation', $$select public.user_set_roles((select id from public.app_user where email='admin@bfcl.test'), '{}', 'oops')$$);
select test.denied('removing role.admin from SUPER_ADMIN needs confirmation', $$select public.role_save('SUPER_ADMIN','Super admin',null,(select array_agg(x) from unnest((select permissions from public.v_role_admin where code='SUPER_ADMIN')) x where x <> 'role.admin'),'oops')$$);
select test.denied('disabling yourself needs confirmation', $$select public.user_set_status((select id from public.app_user where email='admin@bfcl.test'), 'disabled', 'oops')$$);
-- even when confirmed, the last role administrator can never be removed (checked at commit; here forced with SET CONSTRAINTS)
do $$ begin
  begin
    perform public.user_set_roles((select id from public.app_user where email='admin@bfcl.test'), '{}', 'confirmed but last admin', true);
    set constraints all immediate;
    raise exception 'FAIL [last admin removed]: expected AD001';
  exception when sqlstate 'AD001' then null; end;
end $$;
do $$ begin
  begin
    perform public.user_set_status((select id from public.app_user where email='admin@bfcl.test'), 'disabled', 'confirmed but last admin', true);
    set constraints all immediate;
    raise exception 'FAIL [last admin disabled]: expected AD001';
  exception when sqlstate 'AD001' then null; end;
end $$;
select test.eq('last admin still holds the role', (select roles from public.v_user_admin where email='admin@bfcl.test'), array['SUPER_ADMIN']);

-- with a second active role administrator, a confirmed self-removal succeeds
select public.user_set_roles((select id from public.app_user where email='headhr@bfcl.test'), '{HEAD_HR,SUPER_ADMIN}', 'second administrator');
select test.eq('two role administrators', (select count(*) from public.v_user_admin where is_role_admin and status='active' and signed_in), 2::bigint);
select public.user_set_roles((select id from public.app_user where email='admin@bfcl.test'), '{}', 'handing over', true);
set constraints all immediate;
select test.eq('self-removal done after explicit confirmation', (select count(*) from public.user_role ur join public.app_user u on u.id=ur.user_id where u.email='admin@bfcl.test'), 0::bigint);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('the remaining administrator keeps access', (public.my_access() -> 'permissions') ? 'role.admin', true);
select test.logout();

-- viewers see nobody
select test.login('viewer@bfcl.test');
select test.eq('viewer sees only their own user row', (select count(*) from public.v_user_admin), 1::bigint);
select test.denied('viewer cannot create roles', $$select public.role_save('Y_ROLE','Y',null,'{}','r')$$);
select test.logout();
rollback;
\echo ALL USER ROLE ADMIN TESTS PASSED
