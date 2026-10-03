-- 0027 Coverage read model for the Applicability admin screen: every active compliance x active location, with the effective decision, conflicts and the unmapped gaps.
-- A view over public.compliance_coverage() (F-1: the function filters by the caller's scope; this view adds no new access). The register pages through it server-side.
-- Rollback: drop view public.v_compliance_coverage;
create view public.v_compliance_coverage with (security_invoker = true) as
select c.compliance_id, c.compliance_code, c.location_id, c.location_code, c.decision, c.effective_status, c.conflict, c.missing_facts, coalesce(cardinality(c.missing_facts), 0) as missing_fact_count,
       (c.effective_status = 'unmapped') as is_gap
  from public.compliance_coverage() c;
grant select on public.v_compliance_coverage to authenticated;

-- End an in-effect applicability decision (reason mandatory, audited). Invoker rights: RLS and F-1 scope apply. In-effect rows are otherwise immutable.
-- Rollback (also): drop function public.applicability_end(uuid, date, text);
create or replace function public.applicability_end(p_id uuid, p_effective_to date, p_reason text) returns void
language plpgsql security invoker as $$
declare o public.compliance_applicability;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then raise exception 'a reason is required to end an applicability decision' using errcode = '22023'; end if;
  select * into o from public.compliance_applicability where id = p_id for update;
  if not found then raise exception 'applicability row not found or outside your scope' using errcode = '42501'; end if;
  if p_effective_to is null or p_effective_to < o.effective_from then raise exception 'the end date cannot be before the start date (%)', o.effective_from using errcode = '22023'; end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.compliance_applicability set effective_to = p_effective_to where id = p_id;
end $$;
revoke all on function public.applicability_end(uuid, date, text) from public, anon;
grant execute on function public.applicability_end(uuid, date, text) to authenticated;
