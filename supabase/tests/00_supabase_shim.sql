-- LOCAL TEST ONLY: emulates the parts of Supabase that migrations rely on.
-- Never applied to a real Supabase project (it provides these natively).
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);
create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(coalesce(current_setting('request.jwt.claim.sub', true), ''), '')::uuid $$;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

-- Mirror of what the REAL project contains (found by the live audit): the platform's Automatic-RLS helper, executable by
-- PUBLIC/authenticated, and default privileges owned by supabase_admin that grant to API roles (we cannot change those).
create or replace function public.rls_auto_enable() returns event_trigger language plpgsql security definer as $fn$ begin null; end $fn$;
grant execute on function public.rls_auto_enable() to authenticated;
do $$ begin if not exists (select 1 from pg_roles where rolname='supabase_admin') then create role supabase_admin nologin; end if; end $$;
alter default privileges for role supabase_admin in schema public grant all on tables to anon, authenticated, service_role;
