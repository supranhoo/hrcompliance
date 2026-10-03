-- 0026 Master Data Administration backend (Compliance Master, Rule Versions, Applicability Matrix).
-- The admin UI writes through the SAME tables, triggers, RLS and audit as every other path; this migration only adds what the UI needs and cannot do safely
-- with a plain INSERT/UPDATE:
--   * Compliance Master is a STABLE IDENTITY: its code (and id) can never change once created; the rule logic lives in versioned rule versions, never in the master.
--   * v_compliance_master / v_compliance_rule_version / v_applicability: read models with joined names (security_invoker: the caller's RLS and scope apply).
--   * compliance_rule_new_draft(): "editing an effective rule creates a new version" - clones the latest version (and its evidence requirements) into ONE draft.
--   * compliance_rule_discard_draft(): removes a never-published draft (published/retired versions are history and can never be removed).
--   * applicability_replace(): ends the in-effect row and adds the replacement in ONE transaction, with a mandatory reason (in-effect rows are immutable, F-1 scope applies).
-- Activation still goes through compliance_activate_rule_version() (reason mandatory, F-2 reconciliation runs inside it).
-- Rollback: drop function public.applicability_replace(uuid, jsonb, text), public.compliance_rule_discard_draft(uuid), public.compliance_rule_new_draft(uuid, date);
--           drop view public.v_applicability, public.v_compliance_rule_version, public.v_compliance_master; drop trigger compliance_master_identity on public.compliance_master;
--           drop function app.compliance_master_identity_guard();

-- ---------- Compliance Master: stable identity ----------
create or replace function app.compliance_master_identity_guard() returns trigger language plpgsql as $$
begin
  if new.id is distinct from old.id or new.code is distinct from old.code then
    raise exception 'the code of a compliance master is its identity and cannot be changed; deactivate it and create a new master' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger compliance_master_identity before update on public.compliance_master for each row execute function app.compliance_master_identity_guard();

-- ---------- read models ----------
create view public.v_compliance_master with (security_invoker = true) as
select m.id, m.code, m.name, m.description, m.domain, m.category_id, c.name as category_name, m.law_id, l.name as law_name, m.section_reference, m.legal_source,
       m.last_reviewed_at, m.owner_department_id, d.name as department_name, m.default_owner_user_id, u.email as owner_email, m.is_active, m.effective_from, m.effective_to,
       m.row_version, m.updated_at,
       av.id as active_version_id, av.version as active_version, av.frequency as active_frequency, av.risk_level as active_risk, av.criticality as active_criticality,
       (select count(*) from public.compliance_rule_version v where v.compliance_id = m.id) as version_count,
       (select count(*) from public.compliance_rule_version v where v.compliance_id = m.id and v.status = 'draft') as draft_count
  from public.compliance_master m
  left join public.compliance_category c on c.id = m.category_id
  left join public.law l on l.id = m.law_id
  left join public.department d on d.id = m.owner_department_id
  left join public.app_user u on u.id = m.default_owner_user_id
  left join public.compliance_rule_version av on av.compliance_id = m.id and av.status = 'active';
grant select on public.v_compliance_master to authenticated;

create view public.v_compliance_rule_version with (security_invoker = true) as
select v.id, v.compliance_id, m.code as compliance_code, m.name as compliance_name, v.version, v.status, v.compliance_type, v.frequency, v.period_start_month, v.due_rule,
       v.risk_level, v.criticality, v.evidence_required, v.alert_rule_code, v.escalation_rule_code, v.effective_from, v.effective_to, v.change_reason, v.row_version, v.created_at, v.updated_at,
       (select count(*) from public.compliance_rule_evidence e where e.rule_version_id = v.id) as evidence_count,
       (select count(*) from public.compliance_instance i where i.rule_version_id = v.id and i.status <> 'superseded') as obligation_count
  from public.compliance_rule_version v join public.compliance_master m on m.id = v.compliance_id;
grant select on public.v_compliance_rule_version to authenticated;

create view public.v_applicability with (security_invoker = true) as
select a.id, a.compliance_id, m.code as compliance_code, m.name as compliance_name, a.entity_id, e.code as entity_code, a.location_id, l.code as location_code, l.name as location_name,
       a.business_unit_id, b.name as business_unit_name, a.state, a.establishment_type, a.industry,
       a.employee_headcount_min, a.employee_headcount_max, a.contractor_headcount_min, a.contractor_headcount_max,
       a.status, a.condition, a.reason, a.source_reference, a.effective_from, a.effective_to, a.is_active, a.row_version, a.updated_at,
       (a.is_active and a.effective_from <= current_date and (a.effective_to is null or a.effective_to >= current_date)) as in_effect
  from public.compliance_applicability a join public.compliance_master m on m.id = a.compliance_id
  left join public.entity e on e.id = a.entity_id left join public.location l on l.id = a.location_id left join public.business_unit b on b.id = a.business_unit_id;
grant select on public.v_applicability to authenticated;

-- ---------- rule versions ----------
create or replace function public.compliance_rule_new_draft(p_compliance uuid, p_effective_from date default null) returns uuid
language plpgsql security invoker as $$
declare src public.compliance_rule_version; v_new uuid;
begin
  if not app.has_permission('compliance.manage') then raise exception 'permission denied' using errcode = '42501'; end if;
  if exists (select 1 from public.compliance_rule_version where compliance_id = p_compliance and status = 'draft') then
    raise exception 'a draft version already exists for this compliance: edit or discard it first' using errcode = '23505';
  end if;
  select * into src from public.compliance_rule_version where compliance_id = p_compliance order by version desc limit 1;
  if not found then raise exception 'this compliance has no rule version to copy; create the first version instead' using errcode = '22023'; end if;
  insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, period_start_month, due_rule, risk_level, criticality, evidence_required,
                                              alert_rule_code, escalation_rule_code, effective_from, custom)
  values (src.compliance_id, src.compliance_type, src.frequency, src.period_start_month, src.due_rule, src.risk_level, src.criticality, src.evidence_required,
          src.alert_rule_code, src.escalation_rule_code, coalesce(p_effective_from, greatest(src.effective_from + 1, current_date)), src.custom)
  returning id into v_new;
  insert into public.compliance_rule_evidence (rule_version_id, document_type_id, is_mandatory)
  select v_new, e.document_type_id, e.is_mandatory from public.compliance_rule_evidence e where e.rule_version_id = src.id;
  return v_new;
end $$;

create or replace function public.compliance_rule_discard_draft(p_version uuid) returns void
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  if not app.has_permission('compliance.manage') then raise exception 'permission denied' using errcode = '42501'; end if;
  select status into st from public.compliance_rule_version where id = p_version for update;
  if not found then raise exception 'unknown rule version' using errcode = '22023'; end if;
  if st <> 'draft' then raise exception 'only a never-published draft can be discarded; published and retired versions are history' using errcode = '42501'; end if;
  delete from public.compliance_rule_evidence where rule_version_id = p_version;
  delete from public.compliance_rule_version where id = p_version;
end $$;

-- ---------- applicability ----------
create or replace function public.applicability_replace(p_old uuid, p_new jsonb, p_reason text) returns uuid
language plpgsql security invoker as $$
declare o public.compliance_applicability; n public.compliance_applicability; v_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'a reason is required to change an applicability decision' using errcode = '22023'; end if;
  select * into o from public.compliance_applicability where id = p_old for update;
  if not found then raise exception 'applicability row not found or outside your scope' using errcode = '42501'; end if;
  n := jsonb_populate_record(null::public.compliance_applicability, p_new);
  if n.effective_from is null or n.effective_from <= o.effective_from then raise exception 'the replacement must take effect after %', o.effective_from using errcode = '22023'; end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.compliance_applicability set effective_to = n.effective_from - 1 where id = o.id and (effective_to is null or effective_to >= n.effective_from);
  insert into public.compliance_applicability (compliance_id, entity_id, location_id, business_unit_id, state, establishment_type, industry,
        employee_headcount_min, employee_headcount_max, contractor_headcount_min, contractor_headcount_max, status, condition, reason, source_reference, effective_from, effective_to)
  values (o.compliance_id, n.entity_id, n.location_id, n.business_unit_id, n.state, n.establishment_type, n.industry,
        n.employee_headcount_min, n.employee_headcount_max, n.contractor_headcount_min, n.contractor_headcount_max, n.status, n.condition,
        coalesce(nullif(trim(n.reason), ''), trim(p_reason)), n.source_reference, n.effective_from, n.effective_to)
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.compliance_rule_new_draft(uuid, date), public.compliance_rule_discard_draft(uuid), public.applicability_replace(uuid, jsonb, text) from public, anon;
grant execute on function public.compliance_rule_new_draft(uuid, date), public.compliance_rule_discard_draft(uuid), public.applicability_replace(uuid, jsonb, text) to authenticated;
