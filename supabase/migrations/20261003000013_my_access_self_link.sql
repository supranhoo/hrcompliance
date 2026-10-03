-- 0013 Make first-login linking order-independent.
-- Problem (reproduced locally): linking happened only in an AFTER INSERT trigger on auth.users. If a person signed in BEFORE an
-- admin provisioned their app_user row (or the row was added later), auth_user_id stayed NULL and my_access() returned {} forever,
-- so the app redirected a valid, active user to /no-access.
-- Fix: my_access() links the caller to a pre-provisioned, still-unlinked app_user whose email matches the caller's CONFIRMED
-- auth email. It never re-links a row that already has an auth_user_id, never links unconfirmed emails, never activates a
-- disabled user, and the change is audited (audit_app_user trigger).
-- Rollback: re-create the previous stable SQL version of public.my_access() from migration 0003.
create or replace function public.my_access() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null then return '{}'::jsonb; end if;

  update public.app_user u
     set auth_user_id = v_uid,
         status = case when u.status = 'invited' then 'active' else u.status end,
         full_name = coalesce(u.full_name, a.raw_user_meta_data ->> 'full_name'),
         last_login_at = now()
    from auth.users a
   where a.id = v_uid
     and a.email_confirmed_at is not null
     and u.auth_user_id is null
     and u.email = a.email::extensions.citext;

  select jsonb_build_object(
      'user_id', u.id, 'email', u.email, 'full_name', u.full_name, 'scope_all', u.scope_all,
      'roles', coalesce((select jsonb_agg(r.code order by r.code) from public.user_role ur join public.role r on r.id = ur.role_id where ur.user_id = u.id), '[]'::jsonb),
      'permissions', coalesce((select jsonb_agg(distinct rp.permission_code order by rp.permission_code) from public.user_role ur join public.role_permission rp on rp.role_id = ur.role_id where ur.user_id = u.id), '[]'::jsonb),
      'scopes', coalesce((select jsonb_agg(jsonb_build_object('type', s.scope_type, 'id', s.scope_id)) from public.user_scope s where s.user_id = u.id), '[]'::jsonb))
    into v_result
    from public.app_user u
   where u.auth_user_id = v_uid and u.status = 'active';

  return coalesce(v_result, '{}'::jsonb);
end $$;
revoke all on function public.my_access() from public, anon;
grant execute on function public.my_access() to authenticated;
