-- 0031 Generic Import Framework (module-agnostic; NO BFCL field mappings, NO business records).
-- Principle: an import is just another way to enter the same data. Rows are validated and written through the SAME tables, triggers, constraints, RLS and audit as
-- the screens, under the importing user's own rights and scope; nothing here can write anything a user could not enter by hand.
--   import_template : registry of importable targets (columns, natural key, required permission). Seeded below with GENERIC reference-master templates only.
--   import_batch    : one uploaded file (idempotent: the same file cannot be imported twice), status machine staged -> validated -> committed | partially_committed | cancelled.
--   import_row      : every row with its raw values, resolved payload, action (insert/update/skip), errors, warnings and the resulting target record.
--   import_stage / import_validate / import_commit / import_cancel : SECURITY INVOKER functions. Validation includes a real DRY RUN of each row's write (rolled back),
--   so the database's own constraints and triggers decide - not a parallel copy of the rules.
-- Rollback: drop view public.v_import_batch; drop functions public.import_cancel, public.import_commit, public.import_validate, public.import_stage, public.import_template_columns,
--           app.import_write, app.import_apply, app.import_parse, app.import_template_guard, app.import_batch_guard; drop tables import_row, import_batch, import_template;
--           delete from numbering_rule where key = 'IMP'; delete from permission where code like 'import.%'.

insert into public.permission (code, module, description) values
  ('import.read', 'import', 'View import history'), ('import.manage', 'import', 'Upload, validate, commit and cancel imports (data is written under your own rights and scope)')
on conflict (code) do nothing;
insert into public.numbering_rule (key, description, reset_policy, pad_width) values ('IMP', 'Import batch', 'yearly', 6) on conflict (key) do nothing;

create table public.import_template (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  name text not null,
  description text,
  target_table text not null,
  write_permission text not null,
  key_columns text[] not null default '{}',
  columns jsonb not null,
  custom_module text,
  max_rows int not null default 5000 check (max_rows between 1 and 20000),
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);
create trigger import_template_stamp before insert or update on public.import_template for each row execute function app.stamp_row();
create trigger audit_import_template after insert or update or delete on public.import_template for each row execute function app.audit_row();

-- A template is data that drives dynamic SQL, so its shape is checked when it is saved: identifiers must exist, types must be known.
create or replace function app.import_template_guard() returns trigger language plpgsql as $$
declare c jsonb; keys text[] := '{}'; k text; tgt text; tgts text[] := '{}';
begin
  if to_regclass('public.' || quote_ident(new.target_table)) is null then raise exception 'unknown target table %', new.target_table using errcode = '23514'; end if;
  if not exists (select 1 from public.permission where code = new.write_permission) then raise exception 'unknown permission %', new.write_permission using errcode = '23514'; end if;
  if jsonb_typeof(new.columns) <> 'array' or jsonb_array_length(new.columns) = 0 then raise exception 'a template needs at least one column' using errcode = '23514'; end if;
  for c in select * from jsonb_array_elements(new.columns) loop
    k := c ->> 'key'; tgt := coalesce(c ->> 'target', k);
    if k is null or k !~ '^[a-z][a-z0-9_]*$' then raise exception 'invalid column key %', k using errcode = '23514'; end if;
    if k = any (keys) then raise exception 'duplicate column key %', k using errcode = '23514'; end if;
    keys := keys || k;
    if coalesce(c ->> 'type', '') not in ('text','int','number','date','boolean','list','ref') then raise exception 'column %: unknown type %', k, c ->> 'type' using errcode = '23514'; end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = new.target_table and column_name = tgt) then
      raise exception 'column %: target column %.% does not exist', k, new.target_table, tgt using errcode = '23514';
    end if;
    tgts := tgts || tgt;
    if c ->> 'type' = 'ref' then
      if to_regclass('public.' || quote_ident(c #>> '{ref,table}')) is null
         or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = c #>> '{ref,table}' and column_name = coalesce(c #>> '{ref,match}', 'code')) then
        raise exception 'column %: invalid reference', k using errcode = '23514';
      end if;
    end if;
    if c ? 'pattern' and c ->> 'pattern' is null then raise exception 'column %: invalid pattern', k using errcode = '23514'; end if;
  end loop;
  foreach k in array new.key_columns loop
    if not (k = any (tgts)) then raise exception 'key column % is not a template column target', k using errcode = '23514'; end if;
  end loop;
  return new;
end $$;
create trigger import_template_guard before insert or update on public.import_template for each row execute function app.import_template_guard();

create table public.import_batch (
  id uuid primary key default gen_random_uuid(),
  batch_no text not null unique,
  template_code text not null references public.import_template(code),
  file_name text not null check (length(trim(file_name)) > 0),
  file_hash text not null check (file_hash ~ '^[0-9a-f]{64}$'),
  on_duplicate text not null default 'skip' check (on_duplicate in ('skip','update','error')),
  status text not null default 'staged' check (status in ('staged','validated','committing','committed','partially_committed','cancelled')),
  mapping jsonb,
  total_rows int not null default 0, valid_rows int not null default 0, warning_rows int not null default 0, error_rows int not null default 0, committed_rows int not null default 0, failed_rows int not null default 0, skipped_rows int not null default 0,
  validated_at timestamptz, committed_at timestamptz, cancelled_at timestamptz, cancel_reason text,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);
-- the same file (by content hash) can be imported once per template: re-uploading it is refused instead of creating duplicates
create unique index import_batch_file_uk on public.import_batch (template_code, file_hash) where status <> 'cancelled';
create index import_batch_user_idx on public.import_batch (created_by, created_at desc);
create trigger import_batch_no before insert on public.import_batch for each row execute function app.assign_business_id('IMP', 'batch_no');
create trigger import_batch_stamp before insert or update on public.import_batch for each row execute function app.stamp_row();
create trigger audit_import_batch after insert or update or delete on public.import_batch for each row execute function app.audit_row();

create or replace function app.import_batch_guard() returns trigger language plpgsql as $$
begin
  if (new.batch_no, new.template_code, new.file_name, new.file_hash, new.created_by) is distinct from (old.batch_no, old.template_code, old.file_name, old.file_hash, old.created_by) then
    raise exception 'an import batch cannot be re-pointed at another file or template' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'staged' and new.status in ('validated','cancelled')) or (old.status = 'validated' and new.status in ('validated','committing','cancelled'))
    or (old.status = 'committing' and new.status in ('committed','partially_committed','validated')) or (old.status = 'partially_committed' and new.status in ('committing','committed'))) then
    raise exception 'import batch status cannot change from % to %', old.status, new.status using errcode = '23514';
  end if;
  if old.status in ('committed','cancelled') and new.status is distinct from old.status then raise exception 'a % batch is closed history', old.status using errcode = '23514'; end if;
  return new;
end $$;
create trigger import_batch_guard before update on public.import_batch for each row execute function app.import_batch_guard();

create table public.import_row (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.import_batch(id) on delete cascade,
  row_no int not null check (row_no >= 1),
  raw jsonb not null,
  payload jsonb,
  action text check (action in ('insert','update','skip')),
  status text not null default 'pending' check (status in ('pending','valid','warning','error','committed','failed','skipped')),
  errors jsonb not null default '[]'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  target_id uuid,
  committed_at timestamptz,
  unique (batch_id, row_no)
);
create index import_row_status_idx on public.import_row (batch_id, status);

-- ---------- value parsing (shared by every template) ----------
create or replace function app.import_parse(p_type text, p_val text) returns jsonb language plpgsql immutable as $$
declare v text := trim(p_val); n numeric;
begin
  case p_type
    when 'text' then return to_jsonb(v);
    when 'int' then
      if v !~ '^-?\d{1,9}$' then raise exception 'must be a whole number' using errcode = '22023'; end if; return to_jsonb(v::int);
    when 'number' then
      if v !~ '^-?\d{1,15}(\.\d{1,6})?$' then raise exception 'must be a number' using errcode = '22023'; end if; n := v::numeric; return to_jsonb(n);
    when 'date' then
      if v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'must be a date as YYYY-MM-DD' using errcode = '22023'; end if;
      begin perform v::date; exception when others then raise exception 'is not a valid date' using errcode = '22023'; end;
      if to_char(v::date, 'YYYY-MM-DD') <> v then raise exception 'is not a valid date' using errcode = '22023'; end if;
      return to_jsonb(v);
    when 'boolean' then
      if lower(v) in ('true','yes','y','1') then return 'true'::jsonb; elsif lower(v) in ('false','no','n','0') then return 'false'::jsonb; end if;
      raise exception 'must be yes/no (true/false)' using errcode = '22023';
    when 'list' then return coalesce((select jsonb_agg(trim(x)) from unnest(string_to_array(v, ',')) x where trim(x) <> ''), '[]'::jsonb);
    else return to_jsonb(v);
  end case;
end $$;

-- ---------- the write path: the real INSERT/UPDATE under the caller's rights ----------
create or replace function app.import_write(p_table text, p_payload jsonb, p_existing uuid) returns uuid
language plpgsql as $$
declare cols text; sets text; v_id uuid;
begin
  select string_agg(format('%I', k), ', ' order by k) into cols from jsonb_object_keys(p_payload) k;
  if cols is null then raise exception 'nothing to import in this row' using errcode = '22023'; end if;
  if p_existing is null then
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) returning id', p_table, cols, cols, p_table) into v_id using p_payload;
  else
    select string_agg(case when k = 'custom' then format('custom = coalesce(t.custom, ''{}''::jsonb) || r.custom') else format('%I = r.%I', k, k) end, ', ' order by k) into sets from jsonb_object_keys(p_payload) k;
    execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I, $1) r where t.id = $2 returning t.id', p_table, sets, p_table) into v_id using p_payload, p_existing;
    if v_id is null then raise exception 'the record to update was not found or is outside your scope' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

-- p_dry = true: perform the write and roll it back (raising a private SQLSTATE), so validation uses the database's own rules; any other error propagates.
create or replace function app.import_apply(p_table text, p_payload jsonb, p_existing uuid, p_dry boolean) returns uuid
language plpgsql as $$
declare v_id uuid;
begin
  begin
    v_id := app.import_write(p_table, p_payload, p_existing);
    if p_dry then raise exception 'dry run' using errcode = 'IM001'; end if;
  exception when sqlstate 'IM001' then return null;
  end;
  return v_id;
end $$;

-- ---------- template columns, including importable custom fields from the Field Designer ----------
create or replace function public.import_template_columns(p_template text) returns jsonb
language plpgsql stable as $$
declare t public.import_template; cols jsonb;
begin
  select * into t from public.import_template where code = p_template and is_active;
  if not found then raise exception 'unknown or inactive import template' using errcode = '22023'; end if;
  cols := t.columns;
  if t.custom_module is not null then
    cols := cols || coalesce((select jsonb_agg(jsonb_build_object('key', 'custom_' || f.key, 'label', f.label, 'type', case when f.field_type in ('integer') then 'int' when f.field_type in ('decimal','currency','percentage') then 'number'
                                  when f.field_type in ('date') then 'date' when f.field_type in ('boolean','checkbox') then 'boolean' else 'text' end,
                                  'custom', f.key, 'required', f.is_required, 'help', f.help_text) order by f.key)
                                from public.field_definition f where f.module = t.custom_module and f.is_importable and f.is_active and not f.is_core and not f.is_read_only), '[]'::jsonb);
  end if;
  return jsonb_build_object('code', t.code, 'name', t.name, 'description', t.description, 'key_columns', to_jsonb(t.key_columns), 'max_rows', t.max_rows, 'columns', cols);
end $$;

-- ---------- stage ----------
create or replace function public.import_stage(p_template text, p_file_name text, p_file_hash text, p_rows jsonb, p_mapping jsonb default null, p_on_duplicate text default 'skip') returns uuid
language plpgsql as $$
declare t public.import_template; b uuid; n int;
begin
  if not app.has_permission('import.manage') then raise exception 'permission denied: importing needs the import.manage permission' using errcode = '42501'; end if;
  select * into t from public.import_template where code = p_template and is_active;
  if not found then raise exception 'unknown or inactive import template' using errcode = '22023'; end if;
  if not app.has_permission(t.write_permission) then raise exception 'permission denied: this import needs the % permission', t.write_permission using errcode = '42501'; end if;
  if p_on_duplicate not in ('skip','update','error') then raise exception 'on_duplicate must be skip, update or error' using errcode = '22023'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'the file has no data rows' using errcode = '22023'; end if;
  n := jsonb_array_length(p_rows);
  if n > t.max_rows then raise exception 'the file has % rows; this template accepts at most % per file', n, t.max_rows using errcode = '22023'; end if;
  if exists (select 1 from public.import_batch where template_code = p_template and file_hash = p_file_hash and status <> 'cancelled') then
    raise exception 'this file was already uploaded as batch % (re-uploading the same file is refused; cancel that batch first if it was a mistake)',
      (select batch_no from public.import_batch where template_code = p_template and file_hash = p_file_hash and status <> 'cancelled') using errcode = '23505';
  end if;
  insert into public.import_batch (template_code, file_name, file_hash, on_duplicate, mapping, total_rows) values (p_template, left(trim(p_file_name), 255), p_file_hash, p_on_duplicate, p_mapping, n) returning id into b;
  insert into public.import_row (batch_id, row_no, raw) select b, o.ord::int, o.v from jsonb_array_elements(p_rows) with ordinality o(v, ord);
  return b;
end $$;

-- ---------- validate (idempotent; re-run any time before commit) ----------
create or replace function public.import_validate(p_batch uuid) returns jsonb
language plpgsql as $$
declare b public.import_batch; t public.import_template; cols jsonb; r record; c jsonb; k text; tgt text; raw text; pv jsonb; pl jsonb; errs jsonb; warns jsonb; keyvals text[]; seen jsonb := '{}'::jsonb; keystr text;
        v_exist uuid; act text; msg text; refid text; sel text; cond text; n_valid int := 0; n_warn int := 0; n_err int := 0; n_skip int := 0; ok boolean;
begin
  select * into b from public.import_batch where id = p_batch for update;
  if not found then raise exception 'import batch not found or not yours' using errcode = '42501'; end if;
  if b.status not in ('staged','validated') then raise exception 'a % batch cannot be validated again', b.status using errcode = '23514'; end if;
  select * into t from public.import_template where code = b.template_code;
  cols := public.import_template_columns(b.template_code) -> 'columns';
  perform set_config('app.audit_reason', 'Import ' || b.batch_no || ' (validation dry run)', true);
  for r in select * from public.import_row where batch_id = p_batch order by row_no loop
    errs := '[]'::jsonb; warns := '[]'::jsonb; pl := '{}'::jsonb; act := null; v_exist := null; keyvals := '{}';
    for c in select * from jsonb_array_elements(cols) loop
      k := c ->> 'key'; tgt := coalesce(c ->> 'target', k); raw := nullif(trim(coalesce(r.raw ->> k, '')), '');
      if raw is null then
        if (c ->> 'required')::boolean is true then errs := errs || jsonb_build_object('column', k, 'message', coalesce(c ->> 'label', k) || ' is required'); end if;
        continue;
      end if;
      begin
        if c ->> 'type' = 'ref' then
          refid := null; cond := case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = c #>> '{ref,table}' and column_name = 'is_active') then ' and is_active' else '' end;
          execute format('select id::text from public.%I where lower(%I::text) = lower($1)%s limit 1', c #>> '{ref,table}', coalesce(c #>> '{ref,match}', 'code'), cond) into refid using raw;
          if refid is null then raise exception 'is unknown: "%"', raw using errcode = '22023'; end if;
          pv := to_jsonb(refid);
        else
          pv := app.import_parse(c ->> 'type', raw);
        end if;
        if c ? 'max' and c ->> 'type' = 'text' and length(raw) > (c ->> 'max')::int then raise exception 'must be at most % characters', c ->> 'max' using errcode = '22023'; end if;
        if c ? 'min' and c ->> 'type' in ('int','number') and (pv #>> '{}')::numeric < (c ->> 'min')::numeric then raise exception 'must be at least %', c ->> 'min' using errcode = '22023'; end if;
        if c ? 'max' and c ->> 'type' in ('int','number') and (pv #>> '{}')::numeric > (c ->> 'max')::numeric then raise exception 'must be at most %', c ->> 'max' using errcode = '22023'; end if;
        if c ? 'pattern' and c ->> 'type' = 'text' and raw !~ (c ->> 'pattern') then raise exception '%', coalesce(c ->> 'pattern_message', 'has an invalid format') using errcode = '22023'; end if;
        if c ->> 'custom' is not null then pl := jsonb_set(pl, '{custom}', coalesce(pl -> 'custom', '{}'::jsonb) || jsonb_build_object(c ->> 'custom', pv), true);
        else pl := pl || jsonb_build_object(tgt, pv); end if;
      exception when others then
        errs := errs || jsonb_build_object('column', k, 'message', coalesce(c ->> 'label', k) || ' ' || regexp_replace(sqlerrm, '^' || coalesce(c ->> 'label', k) || ' ', ''));
      end;
    end loop;
    -- natural key: duplicates inside the file and against existing data
    if cardinality(t.key_columns) > 0 and jsonb_array_length(errs) = 0 then
      select string_agg(coalesce(pl ->> kc, ''), '|' order by kc) into keystr from unnest(t.key_columns) kc;
      if (select bool_and(pl ? kc) from unnest(t.key_columns) kc) then
        if seen ? keystr then errs := errs || jsonb_build_object('column', null, 'message', 'duplicate of row ' || (seen ->> keystr) || ' in this file (same ' || array_to_string(t.key_columns, ' + ') || ')');
        else
          seen := seen || jsonb_build_object(keystr, r.row_no);
          select string_agg(format('t.%I::text = ($1 ->> %L)', kc, kc), ' and ') into sel from unnest(t.key_columns) kc;
          execute format('select t.id from public.%I t where %s limit 1', t.target_table, sel) into v_exist using pl;
          if v_exist is not null then
            if b.on_duplicate = 'error' then errs := errs || jsonb_build_object('column', null, 'message', 'already exists (' || array_to_string(t.key_columns, ' + ') || ')');
            elsif b.on_duplicate = 'skip' then act := 'skip'; warns := warns || jsonb_build_object('column', null, 'message', 'already exists: this row will be skipped');
            else act := 'update'; warns := warns || jsonb_build_object('column', null, 'message', 'already exists: the provided values will update it'); end if;
          end if;
        end if;
      else
        warns := warns || jsonb_build_object('column', null, 'message', 'no value for the duplicate-check key (' || array_to_string(t.key_columns, ' + ') || '): duplicates cannot be detected for this row');
      end if;
    end if;
    if act is null and jsonb_array_length(errs) = 0 then act := case when v_exist is null then 'insert' else 'update' end; end if;
    -- the database's own rules: a real write, rolled back
    if jsonb_array_length(errs) = 0 and act in ('insert','update') then
      begin
        perform app.import_apply(t.target_table, pl, v_exist, true);
      exception when others then
        msg := sqlerrm;
        errs := errs || jsonb_build_object('column', null, 'message', case sqlstate when '42501' then 'not allowed: ' || msg else msg end);
      end;
    end if;
    update public.import_row set payload = case when jsonb_array_length(errs) = 0 then pl else null end,
           action = case when jsonb_array_length(errs) = 0 then act end, errors = errs, warnings = warns,
           status = case when jsonb_array_length(errs) > 0 then 'error' when jsonb_array_length(warns) > 0 then 'warning' else 'valid' end, target_id = null
     where id = r.id;
    if jsonb_array_length(errs) > 0 then n_err := n_err + 1; elsif act = 'skip' then n_skip := n_skip + 1; elsif jsonb_array_length(warns) > 0 then n_warn := n_warn + 1; else n_valid := n_valid + 1; end if;
  end loop;
  update public.import_batch set status = 'validated', validated_at = now(), valid_rows = n_valid, warning_rows = n_warn, error_rows = n_err, skipped_rows = n_skip, committed_rows = 0, failed_rows = 0 where id = p_batch;
  return jsonb_build_object('batch_id', p_batch, 'total', b.total_rows, 'valid', n_valid, 'warnings', n_warn, 'errors', n_err, 'skipped', n_skip);
end $$;

-- ---------- commit ----------
create or replace function public.import_commit(p_batch uuid, p_valid_only boolean default false) returns jsonb
language plpgsql as $$
declare b public.import_batch; t public.import_template; r record; v_id uuid; n_ok int := 0; n_fail int := 0; n_skip int := 0; first_err text;
begin
  if not app.has_permission('import.manage') then raise exception 'permission denied' using errcode = '42501'; end if;
  select * into b from public.import_batch where id = p_batch for update;
  if not found then raise exception 'import batch not found or not yours' using errcode = '42501'; end if;
  if b.status not in ('validated','partially_committed') then raise exception 'only a validated batch can be committed (this one is %)', b.status using errcode = '23514'; end if;
  select * into t from public.import_template where code = b.template_code;
  if not app.has_permission(t.write_permission) then raise exception 'permission denied: this import needs the % permission', t.write_permission using errcode = '42501'; end if;
  if b.error_rows > 0 and not p_valid_only then raise exception '% row(s) have errors: fix the file and upload it again, or commit only the valid rows', b.error_rows using errcode = '23514'; end if;
  update public.import_batch set status = 'committing' where id = p_batch;
  perform set_config('app.audit_reason', 'Import ' || b.batch_no, true);
  for r in select * from public.import_row where batch_id = p_batch and status in ('valid','warning') order by row_no loop
    if r.action = 'skip' then update public.import_row set status = 'skipped' where id = r.id; n_skip := n_skip + 1; continue; end if;
    begin
      v_id := app.import_apply(t.target_table, r.payload,
        case when r.action = 'update' then app.import_find(t.target_table, t.key_columns, r.payload) end, false);
      update public.import_row set status = 'committed', target_id = v_id, committed_at = now() where id = r.id; n_ok := n_ok + 1;
    exception when others then
      if not p_valid_only then raise exception 'row %: % (nothing was imported)', r.row_no, sqlerrm using errcode = '23514'; end if;
      first_err := coalesce(first_err, sqlerrm);
      update public.import_row set status = 'failed', errors = errors || jsonb_build_object('column', null, 'message', sqlerrm) where id = r.id; n_fail := n_fail + 1;
    end;
  end loop;
  update public.import_batch set status = case when n_fail > 0 then 'partially_committed' else 'committed' end, committed_at = now(), committed_rows = committed_rows + n_ok, failed_rows = n_fail where id = p_batch;
  return jsonb_build_object('batch_id', p_batch, 'committed', n_ok, 'failed', n_fail, 'skipped', n_skip, 'not_imported_errors', b.error_rows);
end $$;

-- natural-key lookup for updates (re-resolved at commit time, so a record deleted/changed since validation is handled by the write itself)
create or replace function app.import_find(p_table text, p_keys text[], p_payload jsonb) returns uuid
language plpgsql as $$
declare sel text; v_id uuid;
begin
  select string_agg(format('t.%I::text = ($1 ->> %L)', kc, kc), ' and ') into sel from unnest(p_keys) kc;
  execute format('select t.id from public.%I t where %s limit 1', p_table, sel) into v_id using p_payload;
  return v_id;
end $$;

create or replace function public.import_cancel(p_batch uuid, p_reason text) returns void
language plpgsql as $$
declare b public.import_batch;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'a reason is required to cancel an import' using errcode = '22023'; end if;
  select * into b from public.import_batch where id = p_batch for update;
  if not found then raise exception 'import batch not found or not yours' using errcode = '42501'; end if;
  if b.status not in ('staged','validated') then raise exception 'only a batch that has not been committed can be cancelled (this one is %)', b.status using errcode = '23514'; end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.import_batch set status = 'cancelled', cancelled_at = now(), cancel_reason = trim(p_reason) where id = p_batch;
end $$;

-- ---------- history read model ----------
create view public.v_import_batch with (security_invoker = true) as
select b.id, b.batch_no, b.template_code, t.name as template_name, b.file_name, b.status, b.on_duplicate, b.total_rows, b.valid_rows, b.warning_rows, b.error_rows, b.skipped_rows, b.committed_rows, b.failed_rows,
       b.created_at, b.created_by, u.email as created_by_email, b.validated_at, b.committed_at, b.cancelled_at, b.cancel_reason, b.row_version
  from public.import_batch b join public.import_template t on t.code = b.template_code left join public.app_user u on u.auth_user_id = b.created_by;
grant select on public.v_import_batch to authenticated;

-- ---------- RLS ----------
alter table public.import_template enable row level security; alter table public.import_template force row level security;
alter table public.import_batch enable row level security;    alter table public.import_batch force row level security;
alter table public.import_row enable row level security;      alter table public.import_row force row level security;
grant select, insert, update on public.import_template to authenticated;
grant select, insert, update on public.import_batch, public.import_row to authenticated;
create policy import_template_sel on public.import_template for select to authenticated using (app.has_permission('import.manage') or app.has_permission('import.read'));
create policy import_template_ins on public.import_template for insert to authenticated with check (app.has_permission('config.write'));
create policy import_template_upd on public.import_template for update to authenticated using (app.has_permission('config.write')) with check (app.has_permission('config.write'));
-- batches: history is visible to import.read; staged rows (which may hold data of locations the reader cannot see) only to the person who uploaded them
create policy import_batch_sel on public.import_batch for select to authenticated using (created_by = auth.uid() or app.has_permission('import.read'));
create policy import_batch_ins on public.import_batch for insert to authenticated with check (app.has_permission('import.manage') and created_by = auth.uid());
create policy import_batch_upd on public.import_batch for update to authenticated using (created_by = auth.uid() and app.has_permission('import.manage')) with check (created_by = auth.uid());
create policy import_row_sel on public.import_row for select to authenticated using (exists (select 1 from public.import_batch b where b.id = batch_id and b.created_by = auth.uid()));
create policy import_row_ins on public.import_row for insert to authenticated with check (exists (select 1 from public.import_batch b where b.id = batch_id and b.created_by = auth.uid() and b.status = 'staged'));
create policy import_row_upd on public.import_row for update to authenticated using (exists (select 1 from public.import_batch b where b.id = batch_id and b.created_by = auth.uid())) with check (exists (select 1 from public.import_batch b where b.id = batch_id and b.created_by = auth.uid()));

revoke all on function public.import_template_columns(text), public.import_stage(text, text, text, jsonb, jsonb, text), public.import_validate(uuid), public.import_commit(uuid, boolean), public.import_cancel(uuid, text) from public, anon;
grant execute on function public.import_template_columns(text), public.import_stage(text, text, text, jsonb, jsonb, text), public.import_validate(uuid), public.import_commit(uuid, boolean), public.import_cancel(uuid, text) to authenticated;
revoke all on function app.import_parse(text, text), app.import_write(text, jsonb, uuid), app.import_apply(text, jsonb, uuid, boolean), app.import_find(text, text[], jsonb) from public, anon;
grant execute on function app.import_parse(text, text), app.import_write(text, jsonb, uuid), app.import_apply(text, jsonb, uuid, boolean), app.import_find(text, text[], jsonb) to authenticated;

insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r join public.permission p on p.code like 'import.%' where r.code in ('SUPER_ADMIN','HEAD_HR') on conflict do nothing;

-- ---------- GENERIC reference-master templates (structure only; no data, no BFCL mapping) ----------
-- column spec: key (file header), label, type (text|int|number|date|boolean|list|ref), required, target (table column if different), max/min/pattern, ref {table, match, [target is the table column]}
insert into public.import_template (code, name, description, target_table, write_permission, key_columns, columns, custom_module) values
('compliance_master', 'Compliance Master', 'Stable compliance identities. Rule logic (frequency, due dates, evidence) is added as rule versions in the application, never through this file.', 'compliance_master', 'compliance.manage', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":40,"pattern":"^[A-Z0-9][A-Z0-9_.-]{1,39}$","pattern_message":"must be capital letters, digits, dot, dash or underscore (2-40)"},
   {"key":"name","label":"Name","type":"text","required":true,"max":200},{"key":"description","label":"Description","type":"text","max":2000},{"key":"domain","label":"Domain","type":"text"},
   {"key":"category_code","label":"Category code","type":"ref","target":"category_id","ref":{"table":"compliance_category","match":"code"}},
   {"key":"law_code","label":"Law code","type":"ref","target":"law_id","ref":{"table":"law","match":"code"}},
   {"key":"section_reference","label":"Section reference","type":"text","max":200},{"key":"legal_source","label":"Legal source","type":"text","max":500},
   {"key":"last_reviewed_at","label":"Last reviewed","type":"date"},
   {"key":"owner_department_code","label":"Owner department code","type":"ref","target":"owner_department_id","ref":{"table":"department","match":"code"}},
   {"key":"default_owner_email","label":"Default owner email","type":"ref","target":"default_owner_user_id","ref":{"table":"app_user","match":"email"}},
   {"key":"effective_from","label":"Effective from","type":"date"},{"key":"effective_to","label":"Effective to","type":"date"},{"key":"is_active","label":"Active","type":"boolean"}]', 'compliance'),
('licence_type', 'Licence / Registration Type', 'Licence and registration types with their default renewal lead time.', 'licence_type', 'compliance.manage', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":32,"pattern":"^[A-Z0-9][A-Z0-9_.-]{1,31}$","pattern_message":"must be capital letters, digits, dot, dash or underscore (2-32)"},
   {"key":"name","label":"Name","type":"text","required":true,"max":200},{"key":"authority_code","label":"Authority code","type":"ref","target":"authority_id","ref":{"table":"authority","match":"code"}},
   {"key":"default_renewal_lead_days","label":"Renewal lead (days)","type":"int","min":0,"max":730},{"key":"default_risk","label":"Default risk","type":"text"},
   {"key":"document_type_code","label":"Certificate document type code","type":"ref","target":"document_type_id","ref":{"table":"document_type","match":"code"}},
   {"key":"has_expiry","label":"Has expiry","type":"boolean"},{"key":"is_active","label":"Active","type":"boolean"}]', null),
('law', 'Laws & Acts', 'Legal reference master. Citations must be supplied by BFCL; nothing is invented.', 'law', 'master.write', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":40},{"key":"name","label":"Name","type":"text","required":true,"max":300},{"key":"short_name","label":"Short name","type":"text","max":80},
   {"key":"jurisdiction","label":"Jurisdiction","type":"text","max":120},{"key":"legal_source","label":"Legal source","type":"text","max":500},{"key":"last_reviewed_at","label":"Last reviewed","type":"date"},
   {"key":"effective_from","label":"Effective from","type":"date"},{"key":"effective_to","label":"Effective to","type":"date"},{"key":"is_active","label":"Active","type":"boolean"}]', null),
('authority', 'Authorities', 'Regulators and issuing authorities.', 'authority', 'master.write', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":40},{"key":"name","label":"Name","type":"text","required":true,"max":300},{"key":"authority_type","label":"Type","type":"text","max":80},
   {"key":"office","label":"Office","type":"text","max":200},{"key":"address","label":"Address","type":"text","max":500},{"key":"contact_person","label":"Contact person","type":"text","max":120},
   {"key":"email","label":"Email","type":"text","max":200,"pattern":"^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$","pattern_message":"must be a valid email address"},{"key":"phone","label":"Phone","type":"text","max":40},{"key":"is_active","label":"Active","type":"boolean"}]', null),
('department', 'Departments', 'Departments (parent codes must already exist).', 'department', 'master.write', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":40},{"key":"name","label":"Name","type":"text","required":true,"max":200},
   {"key":"parent_code","label":"Parent department code","type":"ref","target":"parent_id","ref":{"table":"department","match":"code"}},{"key":"is_active","label":"Active","type":"boolean"}]', null),
('compliance_category', 'Compliance Categories', 'Categories for the Compliance Master.', 'compliance_category', 'compliance.manage', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":32},{"key":"name","label":"Name","type":"text","required":true,"max":200},
   {"key":"parent_code","label":"Parent category code","type":"ref","target":"parent_id","ref":{"table":"compliance_category","match":"code"}},{"key":"is_active","label":"Active","type":"boolean"}]', null),
('document_type', 'Document Types', 'Evidence document types with allowed file types and size.', 'document_type', 'master.write', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":40},{"key":"name","label":"Name","type":"text","required":true,"max":200},{"key":"category","label":"Category","type":"text"},
   {"key":"allowed_mime_types","label":"Allowed file types (MIME, comma separated)","type":"list","target":"allowed_mime_types"},{"key":"max_size_mb","label":"Maximum size (MB)","type":"int","min":1,"max":200},{"key":"is_active","label":"Active","type":"boolean"}]', null),
('location', 'Locations', 'Plants, offices and sites under a legal entity (the entity code must already exist). Writes are limited to your scope.', 'location', 'master.write', '{code}',
 '[{"key":"code","label":"Code","type":"text","required":true,"max":40},{"key":"name","label":"Name","type":"text","required":true,"max":200},
   {"key":"entity_code","label":"Legal entity code","type":"ref","target":"entity_id","required":true,"ref":{"table":"entity","match":"code"}},
   {"key":"state","label":"State","type":"text","max":80},{"key":"district","label":"District","type":"text","max":80},{"key":"address","label":"Address","type":"text","max":500},
   {"key":"establishment_type","label":"Establishment type","type":"text","max":80},{"key":"employee_headcount","label":"Employees","type":"int","min":0,"max":1000000},
   {"key":"contractor_headcount","label":"Contractors","type":"int","min":0,"max":1000000},{"key":"effective_from","label":"Effective from","type":"date"},{"key":"effective_to","label":"Effective to","type":"date"},{"key":"is_active","label":"Active","type":"boolean"}]', null),
('licence', 'Licences & Registrations', 'Licence records. The internal number (LIC-…) is assigned by the system; duplicates are detected on authority + number when both are given.', 'licence', 'licence.write', '{authority_id,licence_number}',
 '[{"key":"licence_type_code","label":"Licence type code","type":"ref","target":"licence_type_id","required":true,"ref":{"table":"licence_type","match":"code"}},
   {"key":"entity_code","label":"Legal entity code","type":"ref","target":"entity_id","required":true,"ref":{"table":"entity","match":"code"}},
   {"key":"location_code","label":"Location code","type":"ref","target":"location_id","ref":{"table":"location","match":"code"}},
   {"key":"authority_code","label":"Authority code","type":"ref","target":"authority_id","ref":{"table":"authority","match":"code"}},
   {"key":"licence_number","label":"Licence number (as issued)","type":"text","max":100},{"key":"issue_date","label":"Issue date","type":"date"},{"key":"effective_date","label":"Effective date","type":"date"},
   {"key":"expiry_date","label":"Expiry date","type":"date"},{"key":"renewal_lead_days","label":"Renewal lead (days)","type":"int","min":0,"max":730},
   {"key":"owner_email","label":"Owner email","type":"ref","target":"owner_user_id","ref":{"table":"app_user","match":"email"}},{"key":"risk_level","label":"Risk","type":"text"},
   {"key":"renewal_status","label":"Renewal status","type":"text"},{"key":"remarks","label":"Remarks","type":"text","max":2000}]', 'licence')
on conflict (code) do nothing;
