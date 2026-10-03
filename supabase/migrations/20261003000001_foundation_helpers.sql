-- 0001 Foundation helpers: extensions, private schema, audit-stamp triggers.
-- Rollback: drop schema app cascade; (no data at this stage).
-- Extensions live in `extensions` (not `public`) so their functions are never exposed through the Data API.
create schema if not exists extensions;
create extension if not exists citext with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- `app` holds security/helper functions. It is NOT exposed through the REST API.
create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to authenticated, service_role;

-- Stamps created_*/updated_* columns and keeps row_version. Actor comes from the JWT (auth.uid()).
create or replace function app.stamp_row() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
    new.created_by := coalesce(new.created_by, auth.uid());
    new.row_version := 1;
  else
    new.created_at := old.created_at;
    new.created_by := old.created_by;
    new.row_version := old.row_version + 1;
  end if;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

-- Reusable guard: effective_to must not precede effective_from.
create or replace function app.valid_period(f date, t date) returns boolean
language sql immutable as $$ select t is null or f is null or t >= f $$;
