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
  email_confirmed_at timestamptz default now(),
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

-- Mirror of Supabase's migration history table (the CLI/integration records each applied version here).
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text);

-- Minimal emulation of Supabase Storage (metadata tables only; no files). Real projects provide this natively. RLS on storage.objects is enabled as in Supabase.
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text not null, public boolean not null default false, file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now());
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text, owner uuid, metadata jsonb, created_at timestamptz default now(), unique (bucket_id, name));
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to authenticated, service_role;
grant select on storage.buckets to authenticated, service_role;
