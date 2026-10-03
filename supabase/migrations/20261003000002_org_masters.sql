-- 0002 Organisation & reference masters.
-- Convention for every master/transaction table:
--   id uuid PK (internal), code/business id (human), is_active, effective_from/to,
--   created_at/by, updated_at/by, row_version (optimistic concurrency), soft delete via is_active / deleted_at.
-- created_by/updated_by are plain uuid (no FK) so audit survives user deletion.

create table public.entity (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  legal_name text,
  pan text, gstin text, cin text,
  is_active boolean not null default true,
  effective_from date, effective_to date,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint entity_code_uk unique (code),
  constraint entity_period_ck check (app.valid_period(effective_from, effective_to))
);

create table public.location (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.entity(id),
  code text not null,
  name text not null,
  state text,                       -- free text until State master is confirmed from source data
  district text,
  address text,
  establishment_type text,          -- becomes LOV-backed (lov_set ESTABLISHMENT_TYPE)
  employee_headcount int check (employee_headcount is null or employee_headcount >= 0),
  contractor_headcount int check (contractor_headcount is null or contractor_headcount >= 0),
  is_active boolean not null default true,
  effective_from date, effective_to date,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint location_code_uk unique (code),
  constraint location_period_ck check (app.valid_period(effective_from, effective_to))
);
create index location_entity_idx on public.location(entity_id);

create table public.business_unit (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.entity(id),
  code text not null, name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint business_unit_code_uk unique (code)
);
create index business_unit_entity_idx on public.business_unit(entity_id);

create table public.unit (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.business_unit(id),
  location_id uuid references public.location(id),
  code text not null, name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint unit_code_uk unique (code)
);
create index unit_bu_idx on public.unit(business_unit_id);

create table public.department (
  id uuid primary key default gen_random_uuid(),
  code text not null, name text not null,
  parent_id uuid references public.department(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint department_code_uk unique (code),
  constraint department_not_self_parent check (parent_id is null or parent_id <> id)
);

create table public.designation (
  id uuid primary key default gen_random_uuid(),
  code text not null, name text not null, grade text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint designation_code_uk unique (code)
);

-- Government / statutory authorities (ESIC, EPFO, Labour Dept, ...). Content comes from BFCL data, not seeded.
create table public.authority (
  id uuid primary key default gen_random_uuid(),
  code text not null, name text not null,
  authority_type text,              -- LOV: AUTHORITY_TYPE
  office text, address text, contact_person text, email extensions.citext, phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint authority_code_uk unique (code)
);

-- Laws / regulations. legal_source + last_reviewed_at are mandatory-by-design (requirement 79):
-- we store where a legal fact came from; we never invent it.
create table public.law (
  id uuid primary key default gen_random_uuid(),
  code text not null, name text not null,
  short_name text, jurisdiction text,
  legal_source text,                -- citation / URL of authoritative text
  last_reviewed_at date, reviewed_by uuid,
  is_active boolean not null default true,
  effective_from date, effective_to date,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint law_code_uk unique (code),
  constraint law_period_ck check (app.valid_period(effective_from, effective_to))
);

create table public.document_type (
  id uuid primary key default gen_random_uuid(),
  code text not null, name text not null,
  category text,
  allowed_mime_types text[] not null default '{application/pdf,image/jpeg,image/png}',
  max_size_mb int not null default 25 check (max_size_mb between 1 and 200),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint document_type_code_uk unique (code)
);

do $$
declare t text;
begin
  foreach t in array array['entity','location','business_unit','unit','department','designation','authority','law','document_type']
  loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function app.stamp_row()', t||'_stamp', t);
  end loop;
end $$;
