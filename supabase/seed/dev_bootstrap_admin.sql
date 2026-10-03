-- DEVELOPMENT ONLY bootstrap identity (authorised by the project owner). Production identity moves to a BFCL Workspace account.
-- Idempotent. After this, sign in once with Google using the same email to link the auth user.
insert into public.app_user (email, full_name, scope_all, status)
values ('vivek.dansena08@gmail.com', 'Vivek (dev admin)', true, 'invited')
on conflict (email) do nothing;
insert into public.user_role (user_id, role_id)
select u.id, r.id from public.app_user u, public.role r
where u.email = 'vivek.dansena08@gmail.com' and r.code = 'SUPER_ADMIN'
on conflict do nothing;
