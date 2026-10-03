-- 0028 Configuration administration guards. The LOV / status / settings admin screens write through the same tables; these database rules make that safe:
--   * LOV: a value's code is its identity (rows reference it as text) so it can never change; values are deactivated, never deleted; values the engines rely on
--     (meta.protected = true) can never be deactivated or have that flag removed through the API; system sets can't be deleted/deactivated or recoded.
--   * Status definitions: engine-referenced statuses (is_system) can't be recoded, re-categorised, deactivated or have their initial/terminal meaning changed.
--   * system_config: known keys are type- and range-checked in the database (the UI validates the same rules); unknown keys are unchanged.
-- Rollback: drop triggers lov_set_guard/lov_value_guard/status_definition_guard/system_config_guard and their functions; alter table status_definition drop column is_system;
--           update lov_value set meta = meta - 'protected'.

-- ---------- LOV ----------
create or replace function app.lov_set_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'lists are never deleted; deactivate a non-system list instead' using errcode = '42501'; end if;
  if new.code is distinct from old.code then raise exception 'the code of a list is its identity and cannot be changed' using errcode = '42501'; end if;
  if old.is_system and (new.is_system is distinct from old.is_system or new.is_active = false) then raise exception 'a system list cannot be deactivated or downgraded' using errcode = '42501'; end if;
  return new;
end $$;
create trigger lov_set_guard before update or delete on public.lov_set for each row execute function app.lov_set_guard();

create or replace function app.lov_value_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if (new.meta ->> 'protected') = 'true' and auth.uid() is not null then raise exception 'only the platform marks values as protected' using errcode = '42501'; end if;
    return new;
  end if;
  if tg_op = 'DELETE' then raise exception 'values are never deleted (rows refer to them); deactivate the value instead' using errcode = '42501'; end if;
  if new.code is distinct from old.code or new.set_id is distinct from old.set_id then raise exception 'the code of a list value is its identity and cannot be changed' using errcode = '42501'; end if;
  if (old.meta ->> 'protected') = 'true' then
    if new.is_active = false then raise exception 'value "%" is used by system logic and cannot be deactivated (labels, colour and order can be edited)', old.code using errcode = '42501'; end if;
    if (new.meta ->> 'protected') is distinct from 'true' and auth.uid() is not null then raise exception 'the protected flag of a system value cannot be removed' using errcode = '42501'; end if;
  elsif (new.meta ->> 'protected') = 'true' and auth.uid() is not null then
    raise exception 'only the platform marks values as protected' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger lov_value_guard before insert or update or delete on public.lov_value for each row execute function app.lov_value_guard();

update public.lov_value v set meta = coalesce(v.meta, '{}'::jsonb) || '{"protected": true}'::jsonb
  from public.lov_set s where s.id = v.set_id and s.code in ('RISK','SEVERITY','CRITICALITY','EXCEPTION_CATEGORY','LICENCE_RENEWAL_STATUS');

-- ---------- status definitions ----------
alter table public.status_definition add column is_system boolean not null default false;
update public.status_definition set is_system = true;     -- every status seeded so far is referenced by an engine or a trigger
create or replace function app.status_definition_guard() returns trigger language plpgsql as $$
begin
  if new.code is distinct from old.code or new.module is distinct from old.module then raise exception 'a status code is its identity and cannot be changed' using errcode = '42501'; end if;
  if old.is_system then
    if new.is_system is distinct from old.is_system or new.category is distinct from old.category or new.is_initial is distinct from old.is_initial or new.is_terminal is distinct from old.is_terminal then
      raise exception 'status "%" is used by system logic: its meaning (category, initial, terminal) cannot be changed; label, colour and order can', old.code using errcode = '42501';
    end if;
    if new.is_active = false then raise exception 'status "%" is used by system logic and cannot be deactivated', old.code using errcode = '42501'; end if;
  elsif new.is_system and auth.uid() is not null then raise exception 'only the platform marks statuses as system' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger status_definition_guard before update on public.status_definition for each row execute function app.status_definition_guard();
create or replace function app.status_definition_insert_guard() returns trigger language plpgsql as $$
begin
  if new.is_system and auth.uid() is not null then new.is_system := false; end if;
  return new;
end $$;
create trigger status_definition_insert_guard before insert on public.status_definition for each row execute function app.status_definition_insert_guard();

-- ---------- system_config: typed validation of the keys the admin screen edits ----------
create or replace function app.system_config_guard() returns trigger language plpgsql as $$
declare v jsonb := new.value; k text := new.key; x jsonb; prev int; sev text;
begin
  if k in ('compliance.due_soon_days','compliance.generation_horizon_days','compliance.generation_lookback_days','exception.overdue_grace_days','alert.catchup_days') then
    if jsonb_typeof(v) <> 'number' or (v #>> '{}') !~ '^\d{1,3}$' then raise exception '% must be a whole number of days (0-999)', k using errcode = '23514'; end if;
    if k = 'compliance.generation_horizon_days' and (v #>> '{}')::int < 1 then raise exception 'the generation horizon must be at least 1 day' using errcode = '23514'; end if;
    if k = 'compliance.generation_horizon_days' and (v #>> '{}')::int > 400 then raise exception 'the generation horizon cannot exceed 400 days' using errcode = '23514'; end if;
  elsif k = 'ui.page_size' then
    if jsonb_typeof(v) <> 'number' or (v #>> '{}') !~ '^\d{1,3}$' or (v #>> '{}')::int not between 5 and 200 then raise exception 'ui.page_size must be between 5 and 200' using errcode = '23514'; end if;
  elsif k = 'licence.expiry_thresholds' then
    if jsonb_typeof(v) <> 'array' or jsonb_array_length(v) = 0 or jsonb_array_length(v) > 12 then raise exception 'licence.expiry_thresholds must be a list of 1-12 day counts' using errcode = '23514'; end if;
    prev := null;
    for x in select * from jsonb_array_elements(v) loop
      if jsonb_typeof(x) <> 'number' or (x #>> '{}') !~ '^\d{1,4}$' or (x #>> '{}')::int < 1 then raise exception 'licence.expiry_thresholds must contain whole days >= 1' using errcode = '23514'; end if;
      if prev is not null and (x #>> '{}')::int >= prev then raise exception 'licence.expiry_thresholds must be strictly descending (e.g. 90, 60, 30, 15, 7)' using errcode = '23514'; end if;
      prev := (x #>> '{}')::int;
    end loop;
  elsif k = 'exception.target_days' then
    if jsonb_typeof(v) <> 'object' then raise exception 'exception.target_days must be an object keyed by severity' using errcode = '23514'; end if;
    for sev in select lv.code from public.lov_value lv join public.lov_set ls on ls.id = lv.set_id where ls.code = 'SEVERITY' and lv.is_active loop
      if not (v ? sev) or jsonb_typeof(v -> sev) <> 'number' or (v ->> sev) !~ '^\d{1,3}$' or (v ->> sev)::int < 1 then
        raise exception 'exception.target_days needs a whole number of days (>= 1) for every severity; "%" is missing or invalid', sev using errcode = '23514';
      end if;
    end loop;
  end if;
  return new;
end $$;
create trigger system_config_guard before insert or update on public.system_config for each row execute function app.system_config_guard();
