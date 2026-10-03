-- 0016 Licence / Registration master (Phase 6.3).
-- Expiry state is DERIVED (never stored): days_to_expiry, expiry category and renewal window come from the view/functions below,
-- driven by configurable thresholds in system_config('licence.expiry_thresholds').
-- Rollback: drop view v_licence_status; drop tables licence_event, licence, licence_type; drop functions app.assign_business_id, app.licence_thresholds, app.expiry_bucket.

-- ---------- reusable business-id assignment (LIC-/CMP-/EVD-/EXC-…): runs inside the inserting transaction ----------
-- usage: create trigger … before insert on t for each row execute function app.assign_business_id('LIC','licence_no');
create or replace function app.assign_business_id() returns trigger
language plpgsql security definer set search_path = public as $$
declare col text := tg_argv[1];
begin
  if (to_jsonb(new) ->> col) is null then
    new := jsonb_populate_record(new, jsonb_build_object(col, app.next_business_id(tg_argv[0])));
  end if;
  return new;
end $$;

-- insert-only stamp for append-only tables (no updated_*/row_version columns)
create or replace function app.stamp_created() returns trigger language plpgsql as $$
begin new.created_at := now(); new.created_by := auth.uid(); return new; end $$;

-- ---------- thresholds + bucket ----------
insert into public.system_config (key, value, description) values
  ('licence.expiry_thresholds', '[90,60,30,15,7]', 'Days-to-expiry alert thresholds (descending). Used for expiry categories and licence alerts.')
on conflict (key) do nothing;

create or replace function app.licence_thresholds() returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce((select array(select x::int from jsonb_array_elements_text(value) x order by 1 desc)
                     from public.system_config where key = 'licence.expiry_thresholds' and jsonb_typeof(value) = 'array'),
                  array[90,60,30,15,7])
$$;

-- expired | within_<N> (smallest threshold still >= days) | valid | no_expiry
create or replace function app.expiry_bucket(p_days int, p_thresholds int[] default app.licence_thresholds()) returns text
language sql immutable as $$
  select case when p_days is null then 'no_expiry'
              when p_days < 0 then 'expired'
              else coalesce((select 'within_' || min(t) from unnest(p_thresholds) t where t >= p_days), 'valid') end
$$;

-- ---------- LOV: renewal status ----------
insert into public.lov_set (code, name, is_system) values ('LICENCE_RENEWAL_STATUS','Licence renewal status',true) on conflict (code) do nothing;
insert into public.lov_value (set_id, code, label, sort_order, color)
select s.id, v.code, v.label, v.ord, v.color from public.lov_set s join (values
  ('not_started','Not started',10,'grey'), ('in_progress','Renewal in progress',20,'amber'), ('applied','Applied / awaiting authority',30,'blue'), ('renewed','Renewed',40,'green')
) as v(code, label, ord, color) on s.code = 'LICENCE_RENEWAL_STATUS' on conflict (set_id, code) do nothing;

-- ---------- tables ----------
create table public.licence_type (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_.-]{1,31}$'),
  name text not null,
  authority_id uuid references public.authority(id),
  default_renewal_lead_days int not null default 60 check (default_renewal_lead_days between 0 and 730),
  default_risk text,                                  -- LOV RISK
  document_type_id uuid references public.document_type(id),
  has_expiry boolean not null default true,           -- some registrations are perpetual
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1
);

create table public.licence (
  id uuid primary key default gen_random_uuid(),
  licence_no text not null unique,                    -- LIC-000001 (internal business id)
  licence_type_id uuid not null references public.licence_type(id),
  entity_id uuid not null references public.entity(id),
  location_id uuid references public.location(id),
  authority_id uuid references public.authority(id),
  licence_number text,                                -- number issued by the authority
  issue_date date, effective_date date, expiry_date date,
  renewal_lead_days int not null default 60 check (renewal_lead_days between 0 and 730),
  owner_user_id uuid references public.app_user(id),
  risk_level text,                                    -- LOV RISK
  renewal_status text not null default 'not_started', -- LOV LICENCE_RENEWAL_STATUS
  lifecycle_status text not null default 'active' check (lifecycle_status in ('active','surrendered','cancelled')),
  is_new_application boolean not null default false,
  supersedes_id uuid references public.licence(id),   -- renewal chain
  remarks text,
  custom jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint licence_dates_ck check ((issue_date is null or expiry_date is null or expiry_date >= issue_date)
                                     and (effective_date is null or expiry_date is null or expiry_date >= effective_date)),
  constraint licence_supersedes_ck check (supersedes_id is null or supersedes_id <> id)
);
create unique index licence_authority_number_uk on public.licence(authority_id, licence_number) where authority_id is not null and licence_number is not null;
create index licence_expiry_idx on public.licence(expiry_date) where lifecycle_status = 'active';
create index licence_entity_loc_idx on public.licence(entity_id, location_id);
create index licence_type_idx on public.licence(licence_type_id);
create index licence_custom_gin on public.licence using gin (custom);

create table public.licence_event (
  id uuid primary key default gen_random_uuid(),
  licence_id uuid not null references public.licence(id),
  event_type text not null check (event_type in ('application_submitted','query_raised','query_replied','inspection','issued','renewal_applied','renewed','amended','expired','surrendered','cancelled','note')),
  event_date date not null,
  description text,
  created_at timestamptz not null default now(), created_by uuid
);
create index licence_event_idx on public.licence_event(licence_id, event_date desc);

create trigger licence_no_assign before insert on public.licence for each row execute function app.assign_business_id('LIC','licence_no');
create trigger licence_risk_lov before insert or update on public.licence for each row execute function app.validate_lov('RISK','risk_level');
create trigger licence_renewal_lov before insert or update on public.licence for each row execute function app.validate_lov('LICENCE_RENEWAL_STATUS','renewal_status');
create trigger licence_type_risk_lov before insert or update on public.licence_type for each row execute function app.validate_lov('RISK','default_risk');

-- licence_no is a permanent key: never editable
create or replace function app.licence_guard() returns trigger language plpgsql as $$
begin
  if new.licence_no is distinct from old.licence_no then raise exception 'licence_no is immutable' using errcode = '42501'; end if;
  if new.entity_id is distinct from old.entity_id then raise exception 'a licence cannot move to another entity' using errcode = '42501'; end if;
  return new;
end $$;
create trigger licence_guard before update on public.licence for each row execute function app.licence_guard();

-- stamps + audit
create trigger licence_type_stamp before insert or update on public.licence_type for each row execute function app.stamp_row();
create trigger licence_stamp before insert or update on public.licence for each row execute function app.stamp_row();
create trigger licence_event_stamp before insert on public.licence_event for each row execute function app.stamp_created();
create trigger audit_licence_type after insert or update or delete on public.licence_type for each row execute function app.audit_row();
create trigger audit_licence after insert or update or delete on public.licence for each row execute function app.audit_row();

-- ---------- derived status view (SECURITY INVOKER: RLS of the caller applies) ----------
create view public.v_licence_status with (security_invoker = true) as
select l.id, l.licence_no, l.licence_number, l.licence_type_id, t.code as licence_type_code, t.name as licence_type_name,
       l.entity_id, l.location_id, l.authority_id, l.issue_date, l.effective_date, l.expiry_date,
       l.renewal_lead_days, l.owner_user_id, l.risk_level, l.renewal_status, l.lifecycle_status, l.is_new_application,
       (l.expiry_date - current_date) as days_to_expiry,
       case when l.lifecycle_status <> 'active' then l.lifecycle_status else app.expiry_bucket(l.expiry_date - current_date) end as expiry_category,
       (l.lifecycle_status = 'active' and l.expiry_date is not null and (l.expiry_date - current_date) <= l.renewal_lead_days) as renewal_window_open
  from public.licence l join public.licence_type t on t.id = l.licence_type_id;

-- ---------- permissions, grants, RLS ----------
insert into public.permission (code, module, description) values
  ('licence.read','licence','View licences and registrations'), ('licence.write','licence','Create/update licences and log licence events')
on conflict (code) do nothing;

alter table public.licence_type enable row level security; alter table public.licence_type force row level security;
alter table public.licence enable row level security;      alter table public.licence force row level security;
alter table public.licence_event enable row level security; alter table public.licence_event force row level security;
grant select, insert, update on public.licence_type, public.licence to authenticated;
grant select, insert on public.licence_event to authenticated;
grant select on public.v_licence_status to authenticated;

create policy licence_type_sel on public.licence_type for select to authenticated using (app.has_permission('licence.read'));
create policy licence_type_ins on public.licence_type for insert to authenticated with check (app.has_permission('compliance.manage'));
create policy licence_type_upd on public.licence_type for update to authenticated using (app.has_permission('compliance.manage')) with check (app.has_permission('compliance.manage'));

create policy licence_sel on public.licence for select to authenticated using (app.has_permission('licence.read') and app.scope_ok(entity_id, location_id));
create policy licence_ins on public.licence for insert to authenticated with check (app.has_permission('licence.write') and app.scope_ok(entity_id, location_id));
create policy licence_upd on public.licence for update to authenticated
  using (app.has_permission('licence.write') and app.scope_ok(entity_id, location_id))
  with check (app.has_permission('licence.write') and app.scope_ok(entity_id, location_id));

create policy licence_event_sel on public.licence_event for select to authenticated
  using (app.has_permission('licence.read') and exists (select 1 from public.licence l where l.id = licence_id and app.scope_ok(l.entity_id, l.location_id)));
create policy licence_event_ins on public.licence_event for insert to authenticated
  with check (app.has_permission('licence.write') and exists (select 1 from public.licence l where l.id = licence_id and app.scope_ok(l.entity_id, l.location_id)));

insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r join public.permission p on p.code like 'licence.%' where
     r.code = 'SUPER_ADMIN' or (r.code in ('HEAD_HR','PLANT_HR')) or (r.code in ('HOD','VIEWER') and p.code = 'licence.read')
on conflict do nothing;
