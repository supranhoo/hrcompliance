-- 0015 Rule evaluator + Applicability Matrix (Phase 6.2).
-- Applicability decides which (compliance, location) pairs generate obligations. Rows are effective-dated and, once in effect,
-- immutable in scope/decision (a change is a NEW row), so history is never rewritten (req. 78).
-- Resolution: highest specificity wins; ties are resolved fail-safe toward applicability and flagged as conflicts;
-- pairs with no decision are reported as UNMAPPED (never silently dropped).
-- Not yet implemented dimensions (documented, deliberately absent until their records exist): Department (owner level, Phase 8+),
-- Contractor type (contractor-level requirements, Phase 8).
-- Rollback: drop function public.compliance_coverage, app.applicability_for, app.location_facts, app.rule_missing_facts, app.rule_eval, app.scope_ok;
--           drop table compliance_applicability.

-- ---------- rule evaluator (interprets ONLY the whitelisted AST; same shape app.rule_is_valid accepts) ----------
create or replace function app.rule_eval(r jsonb, facts jsonb, ref date default current_date) returns boolean
language plpgsql stable as $$
declare op text := r ->> 'op'; a jsonb; l text; v jsonb := r -> 'value'; vt text := jsonb_typeof(r -> 'value'); ld date;
begin
  if not app.rule_is_valid(r) then raise exception 'invalid rule' using errcode = '22023'; end if;
  if op = 'and' then
    for a in select * from jsonb_array_elements(r -> 'args') loop if not app.rule_eval(a, facts, ref) then return false; end if; end loop;
    return true;
  elsif op = 'or' then
    for a in select * from jsonb_array_elements(r -> 'args') loop if app.rule_eval(a, facts, ref) then return true; end if; end loop;
    return false;
  end if;
  l := facts #>> string_to_array(r ->> 'field', '.');
  if op = 'is_blank'     then return l is null or length(trim(l)) = 0; end if;
  if op = 'is_not_blank' then return l is not null and length(trim(l)) > 0; end if;
  if l is null or length(trim(l)) = 0 then return op in ('neq','not_in'); end if;   -- unknown fact: comparisons are false (reported via rule_missing_facts)
  case op
    when 'eq'  then return case when vt = 'number' then l::numeric = (v #>> '{}')::numeric else lower(l) = lower(v #>> '{}') end;
    when 'neq' then return case when vt = 'number' then l::numeric <> (v #>> '{}')::numeric else lower(l) <> lower(v #>> '{}') end;
    when 'gt'  then return l::numeric >  (v #>> '{}')::numeric;
    when 'gte' then return l::numeric >= (v #>> '{}')::numeric;
    when 'lt'  then return l::numeric <  (v #>> '{}')::numeric;
    when 'lte' then return l::numeric <= (v #>> '{}')::numeric;
    when 'contains' then return position(lower(v #>> '{}') in lower(l)) > 0;
    when 'in'     then return exists (select 1 from jsonb_array_elements_text(v) e where lower(e) = lower(l));
    when 'not_in' then return not exists (select 1 from jsonb_array_elements_text(v) e where lower(e) = lower(l));
    when 'before' then return l::date <  (v #>> '{}')::date;
    when 'after'  then return l::date >  (v #>> '{}')::date;
    when 'within_days' then ld := l::date; return ld between ref and ref + (v #>> '{}')::int;
    else raise exception 'unsupported operator %', op using errcode = '22023';
  end case;
end $$;

-- Facts a rule refers to that are missing/blank (so "false because unknown" is distinguishable from "false because no").
create or replace function app.rule_missing_facts(r jsonb, facts jsonb) returns text[]
language plpgsql stable as $$
declare out text[] := '{}'; a jsonb; f text;
begin
  if r ? 'args' then
    for a in select * from jsonb_array_elements(r -> 'args') loop out := out || app.rule_missing_facts(a, facts); end loop;
    return array(select distinct x from unnest(out) x order by x);
  end if;
  f := r ->> 'field';
  if r ->> 'op' not in ('is_blank','is_not_blank') and coalesce(length(trim(facts #>> string_to_array(f, '.'))), 0) = 0 then out := array[f]; end if;
  return out;
end $$;

create or replace function app.location_facts(p_location uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'entity', jsonb_build_object('code', e.code, 'industry', e.industry),
    'location', jsonb_build_object('code', l.code, 'state', l.state, 'district', l.district, 'establishment_type', l.establishment_type,
                                   'employee_headcount', l.employee_headcount, 'contractor_headcount', l.contractor_headcount))
  from public.location l join public.entity e on e.id = l.entity_id where l.id = p_location
$$;

-- Row-level scope helper for policies: a row with no entity/location is "global" and needs unrestricted scope.
create or replace function app.scope_ok(p_entity uuid, p_location uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare e uuid := p_entity;
begin
  if p_location is not null and e is null then select entity_id into e from public.location where id = p_location; end if;
  if e is null and p_location is null then
    return exists (select 1 from public.app_user u where u.auth_user_id = auth.uid() and u.status = 'active' and u.scope_all);
  end if;
  return app.in_scope(e, p_location);
end $$;

-- ---------- Applicability Matrix ----------
create table public.compliance_applicability (
  id uuid primary key default gen_random_uuid(),
  compliance_id uuid not null references public.compliance_master(id),
  -- scope dimensions: NULL = "any"
  entity_id uuid references public.entity(id),
  location_id uuid references public.location(id),
  business_unit_id uuid references public.business_unit(id),
  state text,
  establishment_type text,
  industry text,
  employee_headcount_min int check (employee_headcount_min is null or employee_headcount_min >= 0),
  employee_headcount_max int check (employee_headcount_max is null or employee_headcount_max >= 0),
  contractor_headcount_min int check (contractor_headcount_min is null or contractor_headcount_min >= 0),
  contractor_headcount_max int check (contractor_headcount_max is null or contractor_headcount_max >= 0),
  -- decision
  status text not null check (status in ('applicable','not_applicable','conditional')),
  condition jsonb,                               -- whitelisted rule AST over location facts; required for 'conditional'
  reason text,
  source_reference text,
  reviewed_by uuid references public.app_user(id),
  reviewed_at timestamptz,
  effective_from date not null,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  updated_at timestamptz not null default now(), updated_by uuid,
  row_version int not null default 1,
  constraint appl_period_ck check (app.valid_period(effective_from, effective_to)),
  constraint appl_condition_ck check ((status = 'conditional') = (condition is not null) and (condition is null or app.rule_is_valid(condition))),
  constraint appl_reason_ck check (status <> 'not_applicable' or length(trim(coalesce(reason, ''))) > 0),
  constraint appl_review_ck check ((reviewed_by is null) = (reviewed_at is null)),
  constraint appl_hc_emp_ck check (employee_headcount_min is null or employee_headcount_max is null or employee_headcount_min <= employee_headcount_max),
  constraint appl_hc_con_ck check (contractor_headcount_min is null or contractor_headcount_max is null or contractor_headcount_min <= contractor_headcount_max)
);
create index appl_compliance_idx on public.compliance_applicability(compliance_id, effective_from);
create index appl_location_idx on public.compliance_applicability(location_id) where location_id is not null;
create index appl_entity_idx on public.compliance_applicability(entity_id) where entity_id is not null;

-- Once a row is in effect its scope and decision cannot be rewritten; end it (effective_to / is_active) and add a new row.
create or replace function app.applicability_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and old.effective_from <= current_date then
    if (new.compliance_id, new.entity_id, new.location_id, new.business_unit_id, new.state, new.establishment_type, new.industry,
        new.employee_headcount_min, new.employee_headcount_max, new.contractor_headcount_min, new.contractor_headcount_max,
        new.status, new.condition, new.effective_from)
       is distinct from
       (old.compliance_id, old.entity_id, old.location_id, old.business_unit_id, old.state, old.establishment_type, old.industry,
        old.employee_headcount_min, old.employee_headcount_max, old.contractor_headcount_min, old.contractor_headcount_max,
        old.status, old.condition, old.effective_from) then
      raise exception 'applicability row is in effect and immutable; end it and add a new row' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger applicability_guard before update on public.compliance_applicability for each row execute function app.applicability_guard();
create trigger compliance_applicability_stamp before insert or update on public.compliance_applicability for each row execute function app.stamp_row();
create trigger audit_compliance_applicability after insert or update or delete on public.compliance_applicability for each row execute function app.audit_row();

-- ---------- resolution ----------
create or replace function app.applicability_for(p_compliance uuid, p_location uuid, p_on date)
returns table (applicability_id uuid, decision text, effective_status text, specificity int, conflict boolean, missing_facts text[])
language plpgsql stable security definer set search_path = public as $$
declare facts jsonb := app.location_facts(p_location);
begin
  return query
  with loc as (
    select l.id as lid, l.entity_id as eid, l.state as lstate, l.establishment_type as letype,
           l.employee_headcount as lemp, l.contractor_headcount as lcon, e.industry as eind
      from public.location l join public.entity e on e.id = l.entity_id where l.id = p_location),
  cand as (
    select a.id as aid, a.status as astatus, a.condition as acond, a.created_at as acreated,
           (case when a.location_id is not null then 100 else 0 end + case when a.business_unit_id is not null then 50 else 0 end
          + case when a.entity_id is not null then 30 else 0 end + case when a.state is not null then 20 else 0 end
          + case when a.establishment_type is not null then 10 else 0 end + case when a.industry is not null then 10 else 0 end
          + case when a.employee_headcount_min is not null or a.employee_headcount_max is not null then 5 else 0 end
          + case when a.contractor_headcount_min is not null or a.contractor_headcount_max is not null then 5 else 0 end) as spec
      from public.compliance_applicability a cross join loc
     where a.compliance_id = p_compliance and a.is_active
       and a.effective_from <= p_on and (a.effective_to is null or a.effective_to >= p_on)
       and (a.entity_id is null or a.entity_id = loc.eid)
       and (a.location_id is null or a.location_id = loc.lid)
       and (a.business_unit_id is null or exists (select 1 from public.unit u where u.business_unit_id = a.business_unit_id and u.location_id = loc.lid and u.is_active))
       and (a.state is null or lower(a.state) = lower(coalesce(loc.lstate, '')))
       and (a.establishment_type is null or lower(a.establishment_type) = lower(coalesce(loc.letype, '')))
       and (a.industry is null or lower(a.industry) = lower(coalesce(loc.eind, '')))
       and ((a.employee_headcount_min is null and a.employee_headcount_max is null)
            or (loc.lemp is not null and loc.lemp >= coalesce(a.employee_headcount_min, 0) and loc.lemp <= coalesce(a.employee_headcount_max, 2147483647)))
       and ((a.contractor_headcount_min is null and a.contractor_headcount_max is null)
            or (loc.lcon is not null and loc.lcon >= coalesce(a.contractor_headcount_min, 0) and loc.lcon <= coalesce(a.contractor_headcount_max, 2147483647)))),
  tied as (select * from cand where spec = (select max(spec) from cand)),
  pick as (select * from tied order by case astatus when 'applicable' then 1 when 'conditional' then 2 else 3 end, acreated, aid limit 1)
  select p.aid, p.astatus,
         case when p.astatus = 'conditional' then case when app.rule_eval(p.acond, facts, p_on) then 'applicable' else 'not_applicable' end else p.astatus end,
         p.spec,
         (select count(distinct t.astatus) from tied t) > 1,
         case when p.astatus = 'conditional' then app.rule_missing_facts(p.acond, facts) else '{}'::text[] end
    from pick p;
end $$;

-- Coverage for every active compliance x active location, INCLUDING the unmapped gaps. SECURITY INVOKER: RLS applies.
create or replace function public.compliance_coverage(p_on date default current_date)
returns table (compliance_id uuid, compliance_code text, location_id uuid, location_code text, decision text, effective_status text, conflict boolean, missing_facts text[])
language sql stable as $$
  select c.id, c.code, l.id, l.code, coalesce(r.decision, 'unmapped'), coalesce(r.effective_status, 'unmapped'), coalesce(r.conflict, false), coalesce(r.missing_facts, '{}'::text[])
    from public.compliance_master c
    cross join public.location l
    left join lateral app.applicability_for(c.id, l.id, p_on) r on true
   where c.is_active and l.is_active
   order by c.code, l.code
$$;
revoke all on function public.compliance_coverage(date) from public, anon;
grant execute on function public.compliance_coverage(date) to authenticated;

-- ---------- RLS ----------
alter table public.compliance_applicability enable row level security;
alter table public.compliance_applicability force row level security;
grant select, insert, update on public.compliance_applicability to authenticated;
create policy appl_sel on public.compliance_applicability for select to authenticated using (app.has_permission('compliance.read'));
create policy appl_ins on public.compliance_applicability for insert to authenticated
  with check (app.has_permission('compliance.manage') and app.scope_ok(entity_id, location_id));
create policy appl_upd on public.compliance_applicability for update to authenticated
  using (app.has_permission('compliance.manage') and app.scope_ok(entity_id, location_id))
  with check (app.has_permission('compliance.manage') and app.scope_ok(entity_id, location_id));
