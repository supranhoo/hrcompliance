-- 0018 Evidence architecture (Phase 6.5).
-- Files live in Google Drive (or another provider behind DocumentStorageService); the database keeps the file reference, metadata,
-- version chain and verification state. File identity is IMMUTABLE after insert: replacing evidence creates a new version that
-- supersedes the old one (reason mandatory); nothing is silently overwritten (req. 36).
-- "Missing" and "Expired" are DERIVED against the mandatory document types of the rule version (view below).
-- Parent links are real foreign keys (compliance_instance_id | licence_id; exactly one). Later modules add their own FK column
-- and extend the one-parent check in their migration.
-- Rollback: drop view v_evidence_requirement; drop functions public.evidence_replace, app.evidence_*; drop table evidence.

create table public.evidence (
  id uuid primary key default gen_random_uuid(),
  evidence_no text not null unique,                    -- EVD-2026-000001
  compliance_instance_id uuid references public.compliance_instance(id),
  licence_id uuid references public.licence(id),
  entity_id uuid not null references public.entity(id),   -- denormalised from the parent by trigger (scope checks)
  location_id uuid references public.location(id),
  document_type_id uuid not null references public.document_type(id),
  period_start date, period_end date,
  storage_provider text not null default 'google_drive' check (storage_provider in ('google_drive','supabase_storage','external_link')),
  storage_file_id text not null check (length(trim(storage_file_id)) > 0),   -- Drive file id; never the file content
  file_name text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_at timestamptz not null default now(),
  uploaded_by uuid,
  verification_status text not null default 'pending_review' check (verification_status in ('pending_review','verified','rejected')),
  verified_by uuid, verified_at timestamptz, verification_remarks text,
  expiry_date date,
  version int not null default 1,
  supersedes_id uuid references public.evidence(id),
  is_current boolean not null default true,
  replace_reason text,
  remarks text,
  custom jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint evidence_one_parent_ck check (num_nonnulls(compliance_instance_id, licence_id) = 1),
  constraint evidence_period_ck check (period_end is null or period_start is null or period_end >= period_start),
  constraint evidence_rejected_ck check (verification_status <> 'rejected' or length(trim(coalesce(verification_remarks, ''))) > 0),
  constraint evidence_verified_ck check ((verification_status = 'pending_review') = (verified_at is null)),
  constraint evidence_replace_ck check (supersedes_id is null or length(trim(coalesce(replace_reason, ''))) > 0)
);
-- one CURRENT evidence per parent + document type + period: a second upload must go through evidence_replace()
create unique index evidence_one_current_uk on public.evidence (coalesce(compliance_instance_id, licence_id), document_type_id, coalesce(period_start, date '0001-01-01')) where is_current;
create index evidence_instance_idx on public.evidence(compliance_instance_id) where compliance_instance_id is not null;
create index evidence_licence_idx on public.evidence(licence_id) where licence_id is not null;
create index evidence_scope_idx on public.evidence(entity_id, location_id);
create index evidence_expiry_idx on public.evidence(expiry_date) where is_current and expiry_date is not null;
create index evidence_status_idx on public.evidence(verification_status) where is_current;

create trigger evidence_no_assign before insert on public.evidence for each row execute function app.assign_business_id('EVD','evidence_no');

-- insert: derive scope from parent, validate file against document type, force version fields
create or replace function app.evidence_before_insert() returns trigger language plpgsql security definer set search_path = public as $$
declare dt public.document_type; ci public.compliance_instance; li public.licence; flagged boolean := coalesce(current_setting('app.evidence_replace', true), '') = '1';
begin
  if num_nonnulls(new.compliance_instance_id, new.licence_id) <> 1 then raise exception 'evidence must be attached to exactly one parent record' using errcode = '23514'; end if;
  if new.compliance_instance_id is not null then
    select * into ci from public.compliance_instance where id = new.compliance_instance_id;
    if not found then raise exception 'unknown compliance instance' using errcode = '22023'; end if;
    new.entity_id := ci.entity_id; new.location_id := ci.location_id;
    new.period_start := coalesce(new.period_start, ci.period_start); new.period_end := coalesce(new.period_end, ci.period_end);
  else
    select * into li from public.licence where id = new.licence_id;
    if not found then raise exception 'unknown licence' using errcode = '22023'; end if;
    new.entity_id := li.entity_id; new.location_id := li.location_id;
  end if;
  select * into dt from public.document_type where id = new.document_type_id and is_active;
  if not found then raise exception 'unknown or inactive document type' using errcode = '22023'; end if;
  if not (lower(new.mime_type) = any (select lower(x) from unnest(dt.allowed_mime_types) x)) then
    raise exception 'file type % is not allowed for document type %', new.mime_type, dt.code using errcode = '23514';
  end if;
  if new.size_bytes > dt.max_size_mb::bigint * 1024 * 1024 then
    raise exception 'file exceeds the % MB limit for document type %', dt.max_size_mb, dt.code using errcode = '23514';
  end if;
  if not flagged then
    if new.supersedes_id is not null then raise exception 'use evidence_replace() to add a new version' using errcode = '42501'; end if;
    new.version := 1; new.is_current := true; new.replace_reason := null;
  end if;
  new.uploaded_by := coalesce(auth.uid(), new.uploaded_by); new.uploaded_at := now();
  new.verification_status := 'pending_review'; new.verified_by := null; new.verified_at := null; new.verification_remarks := null;
  return new;
end $$;
create trigger evidence_before_insert before insert on public.evidence for each row execute function app.evidence_before_insert();

-- update: file identity immutable; verification needs evidence.verify; only evidence_replace() may retire a version
create or replace function app.evidence_before_update() returns trigger language plpgsql security definer set search_path = public as $$
declare flagged boolean := coalesce(current_setting('app.evidence_replace', true), '') = '1';
begin
  if (new.evidence_no, new.compliance_instance_id, new.licence_id, new.entity_id, new.location_id, new.document_type_id, new.period_start, new.period_end,
      new.storage_provider, new.storage_file_id, new.file_name, new.mime_type, new.size_bytes, new.checksum_sha256, new.uploaded_at, new.uploaded_by,
      new.version, new.supersedes_id, new.replace_reason)
     is distinct from
     (old.evidence_no, old.compliance_instance_id, old.licence_id, old.entity_id, old.location_id, old.document_type_id, old.period_start, old.period_end,
      old.storage_provider, old.storage_file_id, old.file_name, old.mime_type, old.size_bytes, old.checksum_sha256, old.uploaded_at, old.uploaded_by,
      old.version, old.supersedes_id, old.replace_reason) then
    raise exception 'evidence file identity is immutable; add a new version with evidence_replace()' using errcode = '42501';
  end if;
  if new.is_current is distinct from old.is_current and not (flagged and old.is_current and not new.is_current) then
    raise exception 'only evidence_replace() can retire a version' using errcode = '42501';
  end if;
  if (new.verification_status, new.verified_by, new.verified_at, new.verification_remarks)
     is distinct from (old.verification_status, old.verified_by, old.verified_at, old.verification_remarks) then
    if auth.uid() is not null and not app.has_permission('evidence.verify') then
      raise exception 'verifying evidence requires the evidence.verify permission' using errcode = '42501';
    end if;
    if new.verification_status = 'pending_review' then new.verified_by := null; new.verified_at := null;
    else new.verified_by := coalesce(auth.uid(), new.verified_by); new.verified_at := now(); end if;
  end if;
  return new;
end $$;
create trigger evidence_before_update before update on public.evidence for each row execute function app.evidence_before_update();
create trigger evidence_stamp before insert or update on public.evidence for each row execute function app.stamp_row();
create trigger audit_evidence after insert or update or delete on public.evidence for each row execute function app.audit_row();

-- Replace = new version row; the previous version is kept (is_current=false) with its original file reference.
create or replace function public.evidence_replace(p_old uuid, p_storage_file_id text, p_file_name text, p_mime_type text, p_size_bytes bigint,
                                                    p_checksum text, p_expiry date, p_reason text) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.evidence; v_id uuid;
begin
  select * into o from public.evidence where id = p_old for update;
  if not found then raise exception 'unknown evidence' using errcode = '22023'; end if;
  if not (app.has_permission('evidence.write') and app.scope_ok(o.entity_id, o.location_id)) then raise exception 'permission denied' using errcode = '42501'; end if;
  if not o.is_current then raise exception 'only the current version can be replaced' using errcode = '22023'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'a reason is required to replace evidence' using errcode = '22023'; end if;
  perform set_config('app.evidence_replace', '1', true);
  update public.evidence set is_current = false where id = o.id;
  insert into public.evidence (compliance_instance_id, licence_id, entity_id, location_id, document_type_id, period_start, period_end, storage_provider,
                               storage_file_id, file_name, mime_type, size_bytes, checksum_sha256, expiry_date, version, supersedes_id, is_current, replace_reason, remarks)
  values (o.compliance_instance_id, o.licence_id, o.entity_id, o.location_id, o.document_type_id, o.period_start, o.period_end, o.storage_provider,
          p_storage_file_id, p_file_name, p_mime_type, p_size_bytes, p_checksum, p_expiry, o.version + 1, o.id, true, p_reason, o.remarks)
  returning id into v_id;
  perform set_config('app.evidence_replace', '', true);
  return v_id;
end $$;
revoke all on function public.evidence_replace(uuid, text, text, text, bigint, text, date, text) from public, anon;
grant execute on function public.evidence_replace(uuid, text, text, text, bigint, text, date, text) to authenticated;

-- ---------- derived requirement state: mandatory document types per instance ----------
-- evidence_state: missing | pending_review | verified | rejected | expired
create view public.v_evidence_requirement with (security_invoker = true) as
select i.id as compliance_instance_id, i.instance_no, i.compliance_id, i.entity_id, i.location_id, i.due_date, i.status as instance_status,
       rq.document_type_id, dt.code as document_type_code, dt.name as document_type_name, rq.is_mandatory,
       e.id as evidence_id, e.evidence_no, e.version, e.verification_status, e.expiry_date,
       case when e.id is null then 'missing'
            when e.expiry_date is not null and e.expiry_date < current_date then 'expired'
            else e.verification_status end as evidence_state
  from public.compliance_instance i
  join public.compliance_rule_version v on v.id = i.rule_version_id and v.evidence_required
  join public.compliance_rule_evidence rq on rq.rule_version_id = v.id
  join public.document_type dt on dt.id = rq.document_type_id
  left join public.evidence e on e.compliance_instance_id = i.id and e.document_type_id = rq.document_type_id and e.is_current;

-- ---------- permissions, grants, RLS ----------
insert into public.permission (code, module, description) values
  ('evidence.read','evidence','View evidence metadata'), ('evidence.write','evidence','Add and replace evidence'), ('evidence.verify','evidence','Verify or reject evidence')
on conflict (code) do nothing;
alter table public.evidence enable row level security; alter table public.evidence force row level security;
grant select, insert, update on public.evidence to authenticated;
grant select on public.v_evidence_requirement to authenticated;
create policy evidence_sel on public.evidence for select to authenticated using (app.has_permission('evidence.read') and app.scope_ok(entity_id, location_id));
-- insert: the BEFORE trigger overwrites entity/location from the parent, so scope is checked against the real parent
create policy evidence_ins on public.evidence for insert to authenticated with check (app.has_permission('evidence.write') and app.scope_ok(entity_id, location_id));
create policy evidence_upd on public.evidence for update to authenticated
  using (app.has_permission('evidence.read') and app.scope_ok(entity_id, location_id) and (app.has_permission('evidence.write') or app.has_permission('evidence.verify')))
  with check (app.scope_ok(entity_id, location_id));
insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r join public.permission p on p.code like 'evidence.%' where
     r.code in ('SUPER_ADMIN','HEAD_HR') or (r.code = 'PLANT_HR' and p.code in ('evidence.read','evidence.write')) or (r.code in ('HOD','VIEWER') and p.code = 'evidence.read')
on conflict do nothing;
