-- 0024 F-1 (owner-decided 2026-10-03): legal/reference masters, the Compliance Master and the base LOCATION MASTER stay readable by every
-- authorised user regardless of scope (unchanged: policies compliance.read / master.read have no scope condition - proven by suite 50).
-- The APPLICABILITY MATRIX and its derived COVERAGE report are location-specific decisions and become SCOPE-CONTROLLED:
--   * a row is readable only when the reader's scope covers its entity/location; a GLOBAL row (no entity, no location) only by a scope_all user;
--   * compliance_coverage() lists only (compliance x location) pairs inside the caller's scope. Service/maintenance sessions (no auth.uid()) see everything.
-- Sensitive location attributes, if ever introduced, belong in a separate SCOPED extension table - the base location master is not restricted.
-- Rollback: drop policy appl_sel on public.compliance_applicability; create policy appl_sel on public.compliance_applicability for select to authenticated using (app.has_permission('compliance.read'));
--           restore public.compliance_coverage(date) from migration 0015.

drop policy appl_sel on public.compliance_applicability;
create policy appl_sel on public.compliance_applicability for select to authenticated
  using (app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id));

create or replace function public.compliance_coverage(p_on date default current_date)
returns table (compliance_id uuid, compliance_code text, location_id uuid, location_code text, decision text, effective_status text, conflict boolean, missing_facts text[])
language sql stable as $$
  select c.id, c.code, l.id, l.code, coalesce(r.decision, 'unmapped'), coalesce(r.effective_status, 'unmapped'), coalesce(r.conflict, false), coalesce(r.missing_facts, '{}'::text[])
    from public.compliance_master c
    cross join public.location l
    left join lateral app.applicability_for(c.id, l.id, p_on) r on true
   where c.is_active and l.is_active
     and (auth.uid() is null or app.scope_ok(l.entity_id, l.id))        -- F-1: coverage is location-specific, so it is scope-controlled
   order by c.code, l.code
$$;
revoke all on function public.compliance_coverage(date) from public, anon;
grant execute on function public.compliance_coverage(date) to authenticated;
