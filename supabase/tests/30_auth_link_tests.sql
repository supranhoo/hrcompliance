-- First-login linking is order-independent and safe. Reuses helpers from 10_rls_and_rules.sql.
\set ON_ERROR_STOP on
create or replace function test.my_access_as(p_auth uuid) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_auth::text, false);
  execute 'set role authenticated';
  r := public.my_access();
  execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false);
  return r;
end $$;
grant execute on function test.my_access_as(uuid) to authenticated;

-- 1. Login BEFORE provisioning (the production order that failed)
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'Late.User@Bfcl.test');
select test.eq('unprovisioned login -> {}', test.my_access_as('11111111-1111-1111-1111-111111111111'), '{}'::jsonb);
insert into public.app_user (email, full_name) values ('late.user@bfcl.test', 'Late User');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='late.user@bfcl.test' and r.code='SUPER_ADMIN';
select test.eq('provisioned later: row still unlinked before next call', (select auth_user_id is null from public.app_user where email='late.user@bfcl.test'), true);
select test.eq('provisioned later: my_access self-links and returns profile', test.my_access_as('11111111-1111-1111-1111-111111111111') ->> 'email', 'late.user@bfcl.test');
select test.eq('linked + activated', (select status || ':' || (auth_user_id = '11111111-1111-1111-1111-111111111111')::text from public.app_user where email='late.user@bfcl.test'), 'active:true');
select test.eq('profile carries SUPER_ADMIN permissions', test.my_access_as('11111111-1111-1111-1111-111111111111') -> 'permissions' ? 'user.admin', true);
select test.eq('self-link is audited', (select count(*) from public.audit_log where table_name='app_user' and action='UPDATE' and changed_fields @> array['auth_user_id'] and new_data ->> 'email' = 'late.user@bfcl.test'), 1::bigint);
select test.eq('idempotent: second call does not write again', (select count(*) from public.audit_log where table_name='app_user' and changed_fields @> array['auth_user_id'] and new_data ->> 'email' = 'late.user@bfcl.test'), 1::bigint);

-- 2. Unconfirmed email must never link
insert into auth.users (id, email, email_confirmed_at) values ('22222222-2222-2222-2222-222222222222', 'unconfirmed@bfcl.test', null);
insert into public.app_user (email) values ('unconfirmed@bfcl.test');
select test.eq('unconfirmed email -> {}', test.my_access_as('22222222-2222-2222-2222-222222222222'), '{}'::jsonb);
select test.eq('unconfirmed email not linked', (select auth_user_id is null from public.app_user where email='unconfirmed@bfcl.test'), true);

-- 3. A row already linked to another identity is never taken over
insert into public.app_user (email, auth_user_id, status) values ('taken@bfcl.test', '99999999-9999-9999-9999-999999999999', 'active');
insert into auth.users (id, email) values ('33333333-3333-3333-3333-333333333333', 'taken@bfcl.test');
select test.eq('already-linked row not hijacked', test.my_access_as('33333333-3333-3333-3333-333333333333'), '{}'::jsonb);
select test.eq('original link preserved', (select auth_user_id::text from public.app_user where email='taken@bfcl.test'), '99999999-9999-9999-9999-999999999999');

-- 4. Disabled users stay out even though they get linked
insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444', 'blocked@bfcl.test');
insert into public.app_user (email, status) values ('blocked@bfcl.test', 'disabled');
select test.eq('disabled user -> {}', test.my_access_as('44444444-4444-4444-4444-444444444444'), '{}'::jsonb);
select test.eq('disabled status unchanged', (select status from public.app_user where email='blocked@bfcl.test'), 'disabled');

-- 5. No JWT / unknown identity
select test.eq('no auth uid -> {}', test.my_access_as(null), '{}'::jsonb);
select test.eq('unknown auth uid -> {}', test.my_access_as('55555555-5555-5555-5555-555555555555'), '{}'::jsonb);
\echo ALL AUTH LINK TESTS PASSED
