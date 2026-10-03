-- 0006 Configuration metadata: LOVs, Field Designer, Section Designer, Rule definitions.
-- Dynamic fields: critical fields are typed columns; admin-added fields are described by field_definition and
-- stored in a `custom jsonb` column on each business table (added per module, GIN-indexed). See docs/DECISIONS.md D-004.
-- Rollback: drop tables in reverse order of creation; drop function app.rule_is_valid.

create table public.lov_set (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z][A-Z0-9_]*$'),
  name text not null, description text,
  is_system boolean not null default false,    -- system sets cannot be deleted (values still editable)
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);
create table public.lov_value (
  id uuid primary key default gen_random_uuid(),
  set_id uuid not null references public.lov_set(id) on delete cascade,
  code text not null, label text not null,
  sort_order int not null default 0,
  color text,                                   -- optional semantic hint: green|amber|red|blue|grey
  meta jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  effective_from date, effective_to date,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (set_id, code),
  constraint lov_value_period_ck check (app.valid_period(effective_from, effective_to))
);
create index lov_value_set_idx on public.lov_value(set_id, sort_order);

-- Whitelist rule validator: configuration can only express approved operators (requirement 28). No SQL/JS ever.
create or replace function app.rule_is_valid(r jsonb, depth int default 0) returns boolean
language plpgsql immutable as $$
declare op text; a jsonb;
begin
  if depth > 8 or r is null or jsonb_typeof(r) <> 'object' then return false; end if;
  op := r ->> 'op';
  if op in ('and','or') then
    if jsonb_typeof(r -> 'args') <> 'array' or jsonb_array_length(r -> 'args') = 0 then return false; end if;
    for a in select * from jsonb_array_elements(r -> 'args') loop
      if not app.rule_is_valid(a, depth + 1) then return false; end if;
    end loop;
    return true;
  end if;
  if op not in ('eq','neq','gt','gte','lt','lte','contains','is_blank','is_not_blank','in','not_in','before','after','within_days') then
    return false;
  end if;
  if coalesce(r ->> 'field', '') !~ '^[a-z][a-z0-9_.]{0,63}$' then return false; end if;
  if op in ('is_blank','is_not_blank') then return not (r ? 'value'); end if;
  if op in ('in','not_in') then return jsonb_typeof(r -> 'value') = 'array'; end if;
  if op = 'within_days' then return jsonb_typeof(r -> 'value') = 'number'; end if;
  return r ? 'value' and jsonb_typeof(r -> 'value') in ('string','number','boolean');
end $$;

create table public.rule_definition (
  id uuid primary key default gen_random_uuid(),
  scope text not null,                           -- applicability | exception | visibility | hold | alert ...
  code text not null, name text not null, description text,
  definition jsonb not null,
  version int not null default 1 check (version >= 1),
  is_active boolean not null default true,
  effective_from date, effective_to date,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (scope, code, version),
  constraint rule_valid_ck check (app.rule_is_valid(definition)),
  constraint rule_period_ck check (app.valid_period(effective_from, effective_to))
);

create table public.field_definition (
  id uuid primary key default gen_random_uuid(),
  module text not null check (module ~ '^[a-z_]+$'),
  key text not null check (key ~ '^[a-z][a-z0-9_]{0,62}$'),
  label text not null,
  field_type text not null check (field_type in (
    'short_text','long_text','integer','decimal','currency','percentage','date','datetime','time','boolean','checkbox','radio',
    'single_select','multi_select','employee_lookup','contractor_lookup','department_lookup','entity_lookup','location_lookup',
    'authority_lookup','user_lookup','compliance_lookup','licence_lookup','email','phone','url','attachment','multi_attachment',
    'status','risk','auto_number','calculated','system')),
  lov_set_id uuid references public.lov_set(id),
  is_core boolean not null default false,        -- true = backed by a typed column; cannot be deleted from UI
  is_required boolean not null default false,
  is_read_only boolean not null default false,
  is_searchable boolean not null default false,
  is_filterable boolean not null default false,
  is_sortable boolean not null default false,
  is_reportable boolean not null default true,
  is_importable boolean not null default true,
  is_exportable boolean not null default true,
  show_in_list boolean not null default false,
  show_in_detail boolean not null default true,
  show_in_quick_view boolean not null default false,
  default_value jsonb, placeholder text, help_text text,
  validation jsonb not null default '{}'::jsonb, -- {min,max,min_length,max_length,pattern,date_min,date_max,...} validated app-side by zod
  conditional_visibility jsonb,                  -- rule AST
  conditional_required jsonb,                    -- rule AST
  version int not null default 1 check (version >= 1),
  is_active boolean not null default true,
  effective_from date, effective_to date,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (module, key, version),
  constraint field_cv_ck check (conditional_visibility is null or app.rule_is_valid(conditional_visibility)),
  constraint field_cr_ck check (conditional_required is null or app.rule_is_valid(conditional_required)),
  constraint field_lov_ck check (field_type not in ('single_select','multi_select','radio') or lov_set_id is not null),
  constraint field_period_ck check (app.valid_period(effective_from, effective_to))
);
-- Only one live version per field key.
create unique index field_definition_live_uk on public.field_definition(module, key) where is_active;
create index field_definition_module_idx on public.field_definition(module) where is_active;

create table public.form_section (
  id uuid primary key default gen_random_uuid(),
  module text not null check (module ~ '^[a-z_]+$'),
  code text not null, label text not null,
  sort_order int not null default 0,
  collapsed_by_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  unique (module, code)
);
create table public.form_section_field (
  section_id uuid not null references public.form_section(id) on delete cascade,
  field_key text not null,
  module text not null,
  sort_order int not null default 0,
  primary key (section_id, field_key)
);
-- Per-role field access. Absence of a row = follow the default for the field.
create table public.field_role_access (
  field_id uuid not null references public.field_definition(id) on delete cascade,
  role_id uuid not null references public.role(id) on delete cascade,
  can_view boolean not null default true,
  can_edit boolean not null default true,
  primary key (field_id, role_id)
);

do $$
declare t text;
begin
  foreach t in array array['lov_set','lov_value','rule_definition','field_definition','form_section']
  loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function app.stamp_row()', t||'_stamp', t);
  end loop;
  foreach t in array array['lov_set','lov_value','rule_definition','field_definition','form_section','form_section_field','field_role_access']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function app.audit_row()', 'audit_'||t, t);
  end loop;
end $$;
