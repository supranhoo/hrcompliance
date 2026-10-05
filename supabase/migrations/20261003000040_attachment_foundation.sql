-- 0040 Generic attachment foundation (reusable by GRC, Liaison, Plant Visit/CAPA, Disciplinary). The compliance `evidence` model is NOT touched.
-- Model: attachment (identity) -> attachment_version (immutable file metadata) ; attachment_target = registry of allowed parent object types ; attachment_access_log = append-only record of confidential reads.
-- AUTHORISATION DERIVES FROM THE PARENT: every read/write is decided by app.attachment_parent_access(parent_type, parent_id, action), which looks the type up in the registry and FAILS CLOSED for anything unregistered, disabled, missing or erroring.
-- No parent type is registered here (GRC etc. do not exist yet); each later module registers its own type in its own migration. An unlinked upload is PENDING: visible and readable only to its uploader and attachment.admin.
-- STORAGE: private Supabase Storage bucket 'attachments'. The browser never chooses a path: the DATABASE mints the object key (attachment_begin_upload); storage policies on storage.objects accept an upload only for a reserved key of the caller and a read only when the attachment's authorisation says so
-- (confidential/restricted reads additionally need a fresh access-log row written by attachment_authorize_download). No signed bearer URLs are minted: downloads use the caller's own JWT, evaluated per request. No update/delete policy exists, so stored objects cannot be overwritten or removed through the API.
-- File metadata, versions, confidentiality, audit and business authorisation live in PostgreSQL. There is no cleanup job for abandoned pending uploads (pg_cron stays OFF); a quota limits pending items per user.
-- Rollback: (only before any data exists) drop view public.v_attachment; drop functions public.attachment_* and app.attachment_*, app.safe_filename; drop tables public.attachment_access_log, public.attachment_version, public.attachment, public.attachment_target; remove storage policies attachments_obj_* and bucket 'attachments'; delete the permission attachment.admin, numbering rule ATT and the two system_config keys. After data exists: forward-fix migration only.

insert into public.permission(code, module, description) values ('attachment.admin', 'attachment', 'Administer pending/unlinked attachments and the attachment registry') on conflict do nothing;
insert into public.role_permission(role_id, permission_code) select id, 'attachment.admin' from public.role where code = 'SUPER_ADMIN' on conflict do nothing;
insert into public.numbering_rule(key, description, reset_policy, pad_width) values ('ATT', 'Attachment', 'yearly', 6) on conflict (key) do nothing;
insert into public.system_config(key, value, description) values
  ('attachment.max_bytes', '26214400', 'Absolute maximum attachment size in bytes (25 MB); the storage bucket limit mirrors it'),
  ('attachment.max_pending_per_user', '20', 'Maximum unlinked (PENDING) attachments one user may hold; there is no automatic cleanup job')
on conflict (key) do nothing;

-- ---------- helpers ----------
-- Safe display filename: no path separators/control/bidi characters, no leading dots, bounded length. The stored object key never contains it.
create or replace function app.safe_filename(p text) returns text language sql immutable as $$
  select nullif(left(btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''), '[\\/:*?"<>|[:cntrl:]‪-‮⁦-⁩]', '_', 'g'), '^\.+', '', 'g'), '\.{2,}', '.', 'g'), '\s+', ' ', 'g')), 150), '')
$$;

-- ---------- registry of allowed parent object types (written by migrations only) ----------
create table public.attachment_target (
  parent_type text primary key check (parent_type ~ '^[a-z][a-z0-9_]{1,40}$'),
  module text not null references public.module_definition(code),
  parent_table text not null,                                  -- existing public table with a uuid id column
  read_permission text not null references public.permission(code),
  write_permission text not null references public.permission(code),
  access_function text not null check (access_function ~ '^app\.[a-z0-9_]+$'),   -- app.<fn>(uuid, text) returns boolean ; actions: read | write | restricted_read
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);
create or replace function app.attachment_target_validate() returns trigger language plpgsql as $$
declare c regclass; f regprocedure;
begin
  c := to_regclass(new.parent_table);
  if c is null or not exists (select 1 from pg_attribute a where a.attrelid = c and a.attname = 'id' and a.atttypid = 'uuid'::regtype and not a.attisdropped) then
    raise exception 'attachment parent table % must exist and have a uuid id column', new.parent_table using errcode = '22023'; end if;
  f := to_regprocedure(new.access_function || '(uuid,text)');
  if f is null or (select prorettype from pg_proc where oid = f) <> 'boolean'::regtype then
    raise exception 'access function % must exist as (uuid, text) returning boolean', new.access_function using errcode = '22023'; end if;
  return new;
end $$;
create trigger attachment_target_validate before insert or update on public.attachment_target for each row execute function app.attachment_target_validate();
create trigger attachment_target_stamp before insert or update on public.attachment_target for each row execute function app.stamp_row();

-- ---------- attachment identity ----------
create table public.attachment (
  id uuid primary key default gen_random_uuid(),
  attachment_no text unique,                                   -- ATT-2026-000001
  link_status text not null default 'PENDING' check (link_status in ('PENDING', 'LINKED')),
  parent_type text references public.attachment_target(parent_type),
  parent_id uuid,
  document_type_id uuid not null references public.document_type(id),
  confidentiality text not null default 'standard' check (confidentiality in ('standard', 'confidential', 'restricted')),
  owner_user_id uuid not null references public.app_user(id),  -- the uploader; sole reader while PENDING
  current_version_id uuid,
  is_active boolean not null default true,
  deactivated_reason text, deactivated_by uuid, deactivated_at timestamptz,
  linked_by uuid, linked_at timestamptz,
  remarks text,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint attachment_link_ck check ((link_status = 'LINKED') = (parent_type is not null and parent_id is not null and linked_at is not null)),
  constraint attachment_deactivated_ck check (is_active or length(btrim(coalesce(deactivated_reason, ''))) > 0)
);
create index attachment_parent_idx on public.attachment(parent_type, parent_id) where link_status = 'LINKED';
create index attachment_owner_pending_idx on public.attachment(owner_user_id) where link_status = 'PENDING';
create trigger attachment_no_assign before insert on public.attachment for each row execute function app.assign_business_id('ATT', 'attachment_no');
create trigger attachment_stamp before insert or update on public.attachment for each row execute function app.stamp_row();

create table public.attachment_version (
  id uuid primary key default gen_random_uuid(),
  attachment_id uuid not null references public.attachment(id),
  version_no int not null check (version_no >= 1),
  file_name text not null check (file_name = app.safe_filename(file_name)),
  mime_type text not null check (mime_type ~ '^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$'),
  size_bytes bigint not null check (size_bytes > 0),           -- declared at reservation, verified against the stored object at completion
  checksum_sha256 text not null check (checksum_sha256 ~ '^[0-9a-f]{64}$'),   -- declared by the uploader; preserved immutably (the database cannot re-hash the object)
  storage_provider text not null default 'supabase_storage' check (storage_provider in ('supabase_storage', 'google_drive', 'external_link')),
  storage_bucket text not null default 'attachments',
  storage_key text not null unique,                            -- minted by the database, never by the browser
  upload_status text not null default 'RESERVED' check (upload_status in ('RESERVED', 'AVAILABLE')),
  uploaded_by uuid not null references public.app_user(id),
  uploaded_at timestamptz not null default now(),
  available_at timestamptz,
  is_current boolean not null default false,
  superseded_by uuid references public.attachment_version(id),
  replace_reason text,
  unique (attachment_id, version_no),
  constraint attachment_version_available_ck check ((upload_status = 'AVAILABLE') = (available_at is not null)),
  constraint attachment_version_super_ck check (superseded_by is null or not is_current),
  constraint attachment_version_reason_ck check (version_no = 1 or length(btrim(coalesce(replace_reason, ''))) > 0)
);
create unique index attachment_one_current_version on public.attachment_version(attachment_id) where is_current;
alter table public.attachment add constraint attachment_current_version_fk foreign key (current_version_id) references public.attachment_version(id);

create table public.attachment_access_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  user_id uuid not null references public.app_user(id),
  attachment_id uuid not null references public.attachment(id),
  version_id uuid not null references public.attachment_version(id),
  action text not null check (action in ('download')),
  confidentiality text not null
);
create index attachment_access_log_recent_idx on public.attachment_access_log(user_id, version_id, at desc);
create or replace function app.attachment_log_immutable() returns trigger language plpgsql as $$
begin raise exception 'attachment_access_log is append-only' using errcode = '42501'; end $$;
create trigger attachment_access_log_no_mutation before update or delete on public.attachment_access_log for each row execute function app.attachment_log_immutable();
create trigger attachment_access_log_no_truncate before truncate on public.attachment_access_log for each statement execute function app.attachment_log_immutable();

-- ---------- integrity guards (apply to every writer, including superusers; the attachment functions set the flag) ----------
create or replace function app.attachment_version_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'attachment versions are never deleted' using errcode = '42501'; end if;
  if current_setting('app.attachment_rpc', true) is distinct from 'on' then
    raise exception 'attachment versions change only through the attachment functions' using errcode = '42501'; end if;
  if tg_op = 'UPDATE' then
    if (new.id, new.attachment_id, new.version_no, new.file_name, new.mime_type, new.size_bytes, new.checksum_sha256, new.storage_provider, new.storage_bucket, new.storage_key, new.uploaded_by, new.uploaded_at)
       is distinct from (old.id, old.attachment_id, old.version_no, old.file_name, old.mime_type, old.size_bytes, old.checksum_sha256, old.storage_provider, old.storage_bucket, old.storage_key, old.uploaded_by, old.uploaded_at) then
      raise exception 'attachment file metadata is immutable' using errcode = '42501'; end if;
    if old.upload_status = 'AVAILABLE' and new.upload_status <> 'AVAILABLE' then raise exception 'an available version cannot go back to reserved' using errcode = '42501'; end if;
    if old.superseded_by is not null and (new.superseded_by is distinct from old.superseded_by or new.replace_reason is distinct from old.replace_reason) then
      raise exception 'supersession is final' using errcode = '42501'; end if;
    if new.superseded_by is not null and not exists (select 1 from public.attachment_version n where n.id = new.superseded_by and n.attachment_id = new.attachment_id and n.version_no > new.version_no) then
      raise exception 'a version can only be superseded by a later version of the same attachment' using errcode = '23514'; end if;
  end if;
  return new;
end $$;
create trigger attachment_version_guard before insert or update or delete on public.attachment_version for each row execute function app.attachment_version_guard();

create or replace function app.attachment_guard() returns trigger language plpgsql as $$
declare t public.attachment_target; present boolean;
begin
  if tg_op = 'DELETE' then raise exception 'attachments are never deleted; deactivate instead' using errcode = '42501'; end if;
  if current_setting('app.attachment_rpc', true) is distinct from 'on' then
    raise exception 'attachments change only through the attachment functions' using errcode = '42501'; end if;
  if tg_op = 'UPDATE' then
    if (new.id, new.attachment_no, new.document_type_id, new.owner_user_id) is distinct from (old.id, old.attachment_no, old.document_type_id, old.owner_user_id) then
      raise exception 'attachment identity is immutable' using errcode = '42501'; end if;
    if old.link_status = 'LINKED' and (new.link_status <> 'LINKED' or new.parent_type is distinct from old.parent_type or new.parent_id is distinct from old.parent_id) then
      raise exception 'a linked attachment cannot be re-parented or unlinked' using errcode = '42501'; end if;
  end if;
  if new.parent_type is not null then      -- polymorphic link: registry membership + parent existence are validated by the database, never trusted from the caller
    select * into t from public.attachment_target where parent_type = new.parent_type and is_enabled;
    if not found then raise exception 'attachment parent type % is not registered or is disabled', new.parent_type using errcode = '22023'; end if;
    execute format('select exists(select 1 from %s where id = $1)', t.parent_table::regclass) into present using new.parent_id;
    if not coalesce(present, false) then
      raise exception 'attachment parent % does not exist', new.parent_id using errcode = '23503'; end if;
  end if;
  return new;
end $$;
create trigger attachment_guard before insert or update or delete on public.attachment for each row execute function app.attachment_guard();

-- ---------- authorisation (fails closed) ----------
create or replace function app.attachment_parent_access(p_type text, p_id uuid, p_action text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare t public.attachment_target; ok boolean; present boolean;
begin
  if p_type is null or p_id is null or p_action is null or p_action not in ('read', 'write', 'restricted_read') then return false; end if;
  select * into t from public.attachment_target where parent_type = p_type and is_enabled;
  if not found then return false; end if;                                                      -- unknown / disabled parent type
  if not app.has_permission(case when p_action = 'write' then t.write_permission else t.read_permission end) then return false; end if;
  begin
    execute format('select exists(select 1 from %s where id = $1)', t.parent_table::regclass) into present using p_id;
    if not coalesce(present, false) then return false; end if;                                 -- missing parent
    execute format('select %s($1, $2)', t.access_function::regproc) into ok using p_id, p_action;
  exception when others then return false;                                                     -- any error in the parent's function: deny
  end;
  return coalesce(ok, false);
end $$;

create or replace function app.attachment_access(p_attachment_id uuid, p_action text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare a public.attachment; uid uuid := app.current_user_id();
begin
  if uid is null or p_action not in ('read', 'write') then return false; end if;
  select * into a from public.attachment where id = p_attachment_id;
  if not found then return false; end if;
  if a.link_status = 'PENDING' then return a.owner_user_id = uid or app.has_permission('attachment.admin'); end if;   -- pending: uploader or explicit admin only
  if not app.attachment_parent_access(a.parent_type, a.parent_id, p_action) then return false; end if;
  if p_action = 'read' then
    if a.confidentiality = 'restricted' and not app.attachment_parent_access(a.parent_type, a.parent_id, 'restricted_read') then return false; end if;
    if not a.is_active and not app.attachment_parent_access(a.parent_type, a.parent_id, 'write') then return false; end if;
  end if;
  return true;
end $$;

-- Decides storage.objects access for the 'attachments' bucket. Exact key match only: unknown names, other buckets and guessed paths are denied.
create or replace function app.attachment_object_ok(p_name text, p_action text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v public.attachment_version; a public.attachment; uid uuid := app.current_user_id(); ok boolean;
begin
  if uid is null or p_name is null or p_action not in ('insert', 'select') then return false; end if;
  select * into v from public.attachment_version where storage_provider = 'supabase_storage' and storage_bucket = 'attachments' and storage_key = p_name;
  if not found then return false; end if;
  if p_action = 'insert' then return v.upload_status = 'RESERVED' and v.uploaded_by = uid; end if;
  if v.upload_status <> 'AVAILABLE' then return false; end if;
  select * into a from public.attachment where id = v.attachment_id;
  ok := app.attachment_access(a.id, 'read');
  if ok and a.confidentiality <> 'standard' then
    ok := exists (select 1 from public.attachment_access_log l where l.user_id = uid and l.version_id = v.id and l.at > now() - interval '120 seconds');   -- logged read only
  end if;
  return coalesce(ok, false);
end $$;

-- ---------- validation hook (content type / size); extend here for malware scanning later ----------
create or replace function app.attachment_validate_file(p_document_type_id uuid, p_mime text, p_size bigint) returns void language plpgsql stable as $$
declare d public.document_type; cap bigint := coalesce((select (value #>> '{}')::bigint from public.system_config where key = 'attachment.max_bytes'), 26214400);
begin
  select * into d from public.document_type where id = p_document_type_id and is_active;
  if not found then raise exception 'unknown or inactive document type' using errcode = '22023'; end if;
  if p_size is null or p_size <= 0 or p_size > cap then raise exception 'file size must be between 1 byte and % bytes', cap using errcode = '22023'; end if;
  if d.max_size_mb is not null and p_size > d.max_size_mb::bigint * 1048576 then raise exception 'file exceeds the % MB limit of this document type', d.max_size_mb using errcode = '22023'; end if;
  if d.allowed_mime_types is not null and cardinality(d.allowed_mime_types) > 0 and not (lower(p_mime) = any (select lower(m) from unnest(d.allowed_mime_types) m)) then
    raise exception 'content type % is not allowed for this document type', p_mime using errcode = '22023'; end if;
end $$;

create or replace function app.storage_object_meta(p_bucket text, p_key text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if to_regclass('storage.objects') is null then return null; end if;
  execute 'select metadata from storage.objects where bucket_id = $1 and name = $2' into r using p_bucket, p_key;
  return r;
end $$;

-- ---------- row level security ----------
alter table public.attachment_target enable row level security;      alter table public.attachment_target force row level security;
alter table public.attachment enable row level security;             alter table public.attachment force row level security;
alter table public.attachment_version enable row level security;     alter table public.attachment_version force row level security;
alter table public.attachment_access_log enable row level security;  alter table public.attachment_access_log force row level security;
revoke all on public.attachment_target, public.attachment, public.attachment_version, public.attachment_access_log from anon, authenticated;
grant select on public.attachment_target, public.attachment, public.attachment_access_log to authenticated;
grant select (id, attachment_id, version_no, file_name, mime_type, size_bytes, checksum_sha256, storage_provider, upload_status, uploaded_by, uploaded_at, available_at, is_current, superseded_by, replace_reason)
  on public.attachment_version to authenticated;                    -- storage_key / storage_bucket are NOT readable: no object enumeration; the key is returned only by the logged functions
create policy attachment_target_sel on public.attachment_target for select to authenticated using (app.has_permission('attachment.admin') or app.has_permission('audit.read'));
create policy attachment_sel on public.attachment for select to authenticated using (app.attachment_access(id, 'read'));
create policy attachment_version_sel on public.attachment_version for select to authenticated using (app.attachment_access(attachment_id, 'read') and (upload_status = 'AVAILABLE' or uploaded_by = app.current_user_id()));
create policy attachment_access_log_sel on public.attachment_access_log for select to authenticated using (user_id = app.current_user_id() or app.has_permission('audit.read'));
-- no insert/update/delete policies and no write grants: every change goes through the SECURITY DEFINER functions below.

-- ---------- functions (the only write path) ----------
create or replace function public.attachment_begin_upload(p_document_type_id uuid, p_file_name text, p_mime_type text, p_size_bytes bigint, p_sha256 text, p_confidentiality text default 'standard')
returns table(attachment_id uuid, version_id uuid, storage_bucket text, storage_key text)
language plpgsql security definer set search_path = public as $$
declare uid uuid := app.current_user_id(); a uuid; v uuid := gen_random_uuid(); k text; fn text := app.safe_filename(p_file_name); lim int;
begin
  if uid is null then raise exception 'not authorised' using errcode = '42501'; end if;
  if fn is null then raise exception 'a usable file name is required' using errcode = '22023'; end if;
  if p_confidentiality not in ('standard', 'confidential', 'restricted') then raise exception 'invalid confidentiality' using errcode = '22023'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'a lower-case SHA-256 checksum is required' using errcode = '22023'; end if;
  perform app.attachment_validate_file(p_document_type_id, lower(p_mime_type), p_size_bytes);
  lim := coalesce((select (value #>> '{}')::int from public.system_config where key = 'attachment.max_pending_per_user'), 20);
  if (select count(*) from public.attachment x where x.owner_user_id = uid and x.link_status = 'PENDING' and x.is_active) >= lim then
    raise exception 'too many unlinked attachments (limit %); link or deactivate existing ones', lim using errcode = '54000'; end if;
  perform set_config('app.attachment_rpc', 'on', true);
  k := v::text || '/' || gen_random_uuid()::text;                                           -- <version id>/<random>; never derived from the file name
  insert into public.attachment(document_type_id, confidentiality, owner_user_id) values (p_document_type_id, p_confidentiality, uid) returning id into a;
  insert into public.attachment_version(id, attachment_id, version_no, file_name, mime_type, size_bytes, checksum_sha256, storage_key, uploaded_by) values (v, a, 1, fn, lower(p_mime_type), p_size_bytes, p_sha256, k, uid);
  perform set_config('app.attachment_rpc', 'off', true);
  return query select a, v, 'attachments'::text, k;
end $$;

create or replace function public.attachment_new_version(p_attachment_id uuid, p_file_name text, p_mime_type text, p_size_bytes bigint, p_sha256 text, p_reason text)
returns table(attachment_id uuid, version_id uuid, storage_bucket text, storage_key text)
language plpgsql security definer set search_path = public as $$
declare uid uuid := app.current_user_id(); a public.attachment; v uuid := gen_random_uuid(); k text; fn text := app.safe_filename(p_file_name); n int;
begin
  select * into a from public.attachment where id = p_attachment_id;
  if uid is null or not found or not app.attachment_access(a.id, 'write') then raise exception 'not authorised' using errcode = '42501'; end if;
  if not a.is_active then raise exception 'attachment is inactive' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'a replacement reason is required' using errcode = '22023'; end if;
  if fn is null then raise exception 'a usable file name is required' using errcode = '22023'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'a lower-case SHA-256 checksum is required' using errcode = '22023'; end if;
  if exists (select 1 from public.attachment_version x where x.attachment_id = a.id and x.upload_status = 'RESERVED') then raise exception 'a previous upload for this attachment is still reserved' using errcode = '55000'; end if;
  perform app.attachment_validate_file(a.document_type_id, lower(p_mime_type), p_size_bytes);
  select coalesce(max(x.version_no), 0) + 1 into n from public.attachment_version x where x.attachment_id = a.id;
  perform set_config('app.attachment_rpc', 'on', true);
  k := v::text || '/' || gen_random_uuid()::text;
  insert into public.attachment_version(id, attachment_id, version_no, file_name, mime_type, size_bytes, checksum_sha256, storage_key, uploaded_by, replace_reason) values (v, a.id, n, fn, lower(p_mime_type), p_size_bytes, p_sha256, k, uid, btrim(p_reason));
  perform set_config('app.attachment_rpc', 'off', true);
  return query select a.id, v, 'attachments'::text, k;
end $$;

-- Verifies the stored object against the declaration, then makes the version available (and current, superseding the previous current version).
create or replace function public.attachment_complete_upload(p_version_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := app.current_user_id(); v public.attachment_version; a public.attachment; meta jsonb; prev uuid;
begin
  select * into v from public.attachment_version where id = p_version_id;
  if uid is null or not found or v.uploaded_by <> uid then raise exception 'not authorised' using errcode = '42501'; end if;
  if v.upload_status = 'AVAILABLE' then return; end if;                                      -- idempotent
  select * into a from public.attachment where id = v.attachment_id;
  if a.link_status = 'LINKED' and not app.attachment_parent_access(a.parent_type, a.parent_id, 'write') then raise exception 'not authorised' using errcode = '42501'; end if;
  meta := case when v.storage_provider = 'supabase_storage' then app.storage_object_meta(v.storage_bucket, v.storage_key) end;
  if meta is null then raise exception 'the uploaded object was not found in storage' using errcode = '55000'; end if;
  if (meta ->> 'size')::bigint is distinct from v.size_bytes then raise exception 'stored object size does not match the declaration' using errcode = '22023'; end if;
  if lower(coalesce(meta ->> 'mimetype', '')) <> v.mime_type then raise exception 'stored object content type does not match the declaration' using errcode = '22023'; end if;
  perform set_config('app.attachment_rpc', 'on', true);
  select x.id into prev from public.attachment_version x where x.attachment_id = v.attachment_id and x.is_current;
  if prev is not null then update public.attachment_version set is_current = false where id = prev; end if;
  update public.attachment_version set upload_status = 'AVAILABLE', available_at = now(), is_current = true where id = v.id;
  if prev is not null then update public.attachment_version set superseded_by = v.id where id = prev; end if;
  update public.attachment set current_version_id = v.id where id = v.attachment_id;
  perform set_config('app.attachment_rpc', 'off', true);
end $$;

-- Links a PENDING attachment to a registered parent object. The caller must own it and hold WRITE access to the parent; the parent is validated again by the guard trigger.
create or replace function public.attachment_link(p_attachment_id uuid, p_parent_type text, p_parent_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := app.current_user_id(); a public.attachment;
begin
  select * into a from public.attachment where id = p_attachment_id;
  if uid is null or not found or a.owner_user_id <> uid or a.link_status <> 'PENDING' or not a.is_active then raise exception 'not authorised' using errcode = '42501'; end if;
  if not exists (select 1 from public.attachment_version v where v.id = a.current_version_id and v.upload_status = 'AVAILABLE') then raise exception 'the upload has not been completed' using errcode = '55000'; end if;
  if not app.attachment_parent_access(p_parent_type, p_parent_id, 'write') then raise exception 'not authorised for that parent object' using errcode = '42501'; end if;
  perform set_config('app.attachment_rpc', 'on', true);
  update public.attachment set link_status = 'LINKED', parent_type = p_parent_type, parent_id = p_parent_id, linked_by = uid, linked_at = now() where id = a.id;
  perform set_config('app.attachment_rpc', 'off', true);
end $$;

create or replace function public.attachment_deactivate(p_attachment_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := app.current_user_id();
begin
  if uid is null or not app.attachment_access(p_attachment_id, 'write') then raise exception 'not authorised' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'a reason is required' using errcode = '22023'; end if;
  perform set_config('app.attachment_rpc', 'on', true);
  update public.attachment set is_active = false, deactivated_reason = btrim(p_reason), deactivated_by = uid, deactivated_at = now() where id = p_attachment_id and is_active;
  perform set_config('app.attachment_rpc', 'off', true);
end $$;

-- Confidentiality may be raised by anyone with write access to the parent; lowering it needs attachment.admin. A reason is always required (audited).
create or replace function public.attachment_set_confidentiality(p_attachment_id uuid, p_level text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := app.current_user_id(); a public.attachment; rank_old int; rank_new int;
begin
  select * into a from public.attachment where id = p_attachment_id;
  if uid is null or not found or not app.attachment_access(a.id, 'write') then raise exception 'not authorised' using errcode = '42501'; end if;
  if p_level not in ('standard', 'confidential', 'restricted') or length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'a valid level and a reason are required' using errcode = '22023'; end if;
  rank_old := array_position(array['standard', 'confidential', 'restricted'], a.confidentiality); rank_new := array_position(array['standard', 'confidential', 'restricted'], p_level);
  if rank_new < rank_old and not app.has_permission('attachment.admin') then raise exception 'lowering confidentiality needs attachment.admin' using errcode = '42501'; end if;
  perform set_config('app.attachment_rpc', 'on', true);
  update public.attachment set confidentiality = p_level, remarks = coalesce(remarks || E'\n', '') || 'confidentiality ' || a.confidentiality || ' -> ' || p_level || ': ' || btrim(p_reason) where id = a.id;
  perform set_config('app.attachment_rpc', 'off', true);
end $$;

-- The only way to obtain a storage key for reading. Logs confidential/restricted reads BEFORE returning (the storage policy then accepts the read for 120 s).
create or replace function public.attachment_authorize_download(p_version_id uuid)
returns table(storage_bucket text, storage_key text, file_name text, mime_type text, size_bytes bigint, checksum_sha256 text)
language plpgsql security definer set search_path = public as $$
declare uid uuid := app.current_user_id(); v public.attachment_version; a public.attachment;
begin
  select * into v from public.attachment_version where id = p_version_id;
  if uid is null or not found or v.upload_status <> 'AVAILABLE' then raise exception 'attachment not available' using errcode = '42501'; end if;
  select * into a from public.attachment where id = v.attachment_id;
  if not app.attachment_access(a.id, 'read') then raise exception 'attachment not available' using errcode = '42501'; end if;     -- same message for missing and forbidden: no enumeration
  if a.confidentiality <> 'standard' then
    insert into public.attachment_access_log(user_id, attachment_id, version_id, action, confidentiality) values (uid, a.id, v.id, 'download', a.confidentiality);
  end if;
  return query select v.storage_bucket, v.storage_key, v.file_name, v.mime_type, v.size_bytes, v.checksum_sha256;
end $$;

revoke all on function public.attachment_begin_upload(uuid, text, text, bigint, text, text), public.attachment_new_version(uuid, text, text, bigint, text, text), public.attachment_complete_upload(uuid),
  public.attachment_link(uuid, text, uuid), public.attachment_deactivate(uuid, text), public.attachment_set_confidentiality(uuid, text, text), public.attachment_authorize_download(uuid) from public, anon;
grant execute on function public.attachment_begin_upload(uuid, text, text, bigint, text, text), public.attachment_new_version(uuid, text, text, bigint, text, text), public.attachment_complete_upload(uuid),
  public.attachment_link(uuid, text, uuid), public.attachment_deactivate(uuid, text), public.attachment_set_confidentiality(uuid, text, text), public.attachment_authorize_download(uuid) to authenticated;
revoke all on function app.attachment_parent_access(text, uuid, text), app.attachment_access(uuid, text), app.attachment_object_ok(text, text), app.attachment_validate_file(uuid, text, bigint), app.storage_object_meta(text, text) from public, anon;
grant execute on function app.attachment_parent_access(text, uuid, text), app.attachment_access(uuid, text), app.attachment_object_ok(text, text), app.safe_filename(text) to authenticated;

-- Listing view (no storage key, no bucket): rows are exactly those the caller may read.
create view public.v_attachment with (security_invoker = true) as
select a.id, a.attachment_no, a.parent_type, a.parent_id, a.link_status, a.confidentiality, a.owner_user_id, a.is_active, a.document_type_id,
       v.id as version_id, v.version_no, v.upload_status, v.file_name, v.mime_type, v.size_bytes, v.checksum_sha256, v.uploaded_at, v.uploaded_by
  from public.attachment a
  left join lateral (select x.id, x.version_no, x.upload_status, x.file_name, x.mime_type, x.size_bytes, x.checksum_sha256, x.uploaded_at, x.uploaded_by from public.attachment_version x where x.attachment_id = a.id order by x.is_current desc, x.version_no desc limit 1) v on true;   -- current version, else the latest (reserved) one
grant select on public.v_attachment to authenticated;

-- ---------- audit ----------
create trigger audit_attachment_target after insert or update or delete on public.attachment_target for each row execute function app.audit_row();
create trigger audit_attachment after insert or update or delete on public.attachment for each row execute function app.audit_row();
create trigger audit_attachment_version after insert or update or delete on public.attachment_version for each row execute function app.audit_row();

-- ---------- private storage bucket + storage policies (skipped, loudly, where no storage schema exists) ----------
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise warning 'storage schema not found: private bucket and storage policies were NOT created';
    return;
  end if;
  begin
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
      values ('attachments', 'attachments', false, 26214400, array['application/pdf', 'image/jpeg', 'image/png'])
      on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
    execute 'create policy attachments_obj_insert on storage.objects for insert to authenticated with check (bucket_id = ''attachments'' and app.attachment_object_ok(name, ''insert''))';
    execute 'create policy attachments_obj_select on storage.objects for select to authenticated using (bucket_id = ''attachments'' and app.attachment_object_ok(name, ''select''))';
    -- deliberately NO update / delete policy: stored objects are immutable through the API
  exception when insufficient_privilege then
    raise warning 'insufficient privilege to configure storage: create bucket "attachments" (private) and the two policies manually, then re-run the live check';
  end;
end $$;
