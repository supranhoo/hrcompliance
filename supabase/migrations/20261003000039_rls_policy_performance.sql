-- 0039 RLS policy performance: evaluate permission and scope once per statement instead of once per row.
-- EVIDENCE (docs/PERFORMANCE_BASELINE.md, synthetic 10,080 obligations / 25,000 exceptions): no index was missing; the time went into per-row calls of app.has_permission() / app.scope_ok() /
-- app.compliance_department() in the row-level-security predicates. Before: Compliance Register count 177 ms, Exceptions first page 547 ms, Management dashboard 1.6 s (all-locations user) and 1.7 s (scoped user).
-- Change (semantics identical, proven by suite 64 against the original functions): (1) permission checks are wrapped in (select ...) so PostgreSQL evaluates them once as an InitPlan; (2) an all-locations user short-circuits on a
-- once-per-statement flag; (3) scoped users compare entity/location/department against the user's scope arrays, built once per statement (app.my_scope_ids) instead of querying app_user/user_scope for every row.
-- Rows with no entity AND no location still need scope_all (null never matches an array); compliance_applicability keeps app.scope_ok because its entity/location are nullable and entity is derived from the location there.
-- Rollback: recreate the 18 policies from migration 0033 (and 0015/0018/0019/0016 for licence/evidence); drop functions app.is_scope_all(), app.my_scope_ids(text).
create or replace function app.is_scope_all() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_user u where u.auth_user_id = auth.uid() and u.status = 'active' and u.scope_all)
$$;
create or replace function app.my_scope_ids(p_type text) returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(s.scope_id), '{}'::uuid[]) from public.app_user u join public.user_scope s on s.user_id = u.id
   where u.auth_user_id = auth.uid() and u.status = 'active' and s.scope_type = p_type
$$;
revoke all on function app.is_scope_all(), app.my_scope_ids(text) from public, anon;
grant execute on function app.is_scope_all(), app.my_scope_ids(text) to authenticated;

drop policy appl_ins on public.compliance_applicability;
create policy appl_ins on public.compliance_applicability for insert to authenticated
  with check ((select app.has_permission('compliance.manage')) and ((select app.is_scope_all()) or app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id))));
drop policy appl_sel on public.compliance_applicability;
create policy appl_sel on public.compliance_applicability for select to authenticated
  using ((select app.has_permission('compliance.read')) and ((select app.is_scope_all()) or app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id))));
drop policy appl_upd on public.compliance_applicability;
create policy appl_upd on public.compliance_applicability for update to authenticated
  using ((select app.has_permission('compliance.manage')) and ((select app.is_scope_all()) or app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id))))
  with check ((select app.has_permission('compliance.manage')) and ((select app.is_scope_all()) or app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id))));
drop policy ci_sel on public.compliance_instance;
create policy ci_sel on public.compliance_instance for select to authenticated
  using ((select app.has_permission('compliance.read')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.compliance_department(compliance_id) is null or app.compliance_department(compliance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy ci_upd on public.compliance_instance;
create policy ci_upd on public.compliance_instance for update to authenticated
  using ((select app.has_permission('compliance.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.compliance_department(compliance_id) is null or app.compliance_department(compliance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))))
  with check ((select app.has_permission('compliance.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.compliance_department(compliance_id) is null or app.compliance_department(compliance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy evidence_ins on public.evidence;
create policy evidence_ins on public.evidence for insert to authenticated
  with check ((select app.has_permission('evidence.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy evidence_sel on public.evidence;
create policy evidence_sel on public.evidence for select to authenticated
  using ((select app.has_permission('evidence.read')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy evidence_upd on public.evidence;
create policy evidence_upd on public.evidence for update to authenticated
  using ((select app.has_permission('evidence.read')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))) and ((select app.has_permission('evidence.write')) or (select app.has_permission('evidence.verify'))))
  with check (((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy exception_ins on public.exception;
create policy exception_ins on public.exception for insert to authenticated
  with check ((select app.has_permission('exception.write')) and source = 'manual' and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy exception_sel on public.exception;
create policy exception_sel on public.exception for select to authenticated
  using ((select app.has_permission('exception.read')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy exception_upd on public.exception;
create policy exception_upd on public.exception for update to authenticated
  using ((select app.has_permission('exception.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))))
  with check ((select app.has_permission('exception.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(compliance_instance_id) is null or app.instance_department(compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[]))))));
drop policy exception_action_ins on public.exception_action;
create policy exception_action_ins on public.exception_action for insert to authenticated
  with check (action_type = 'comment' and (select app.has_permission('exception.write')) and exists (select 1 from public.exception x where x.id = exception_action.exception_id and ((select app.is_scope_all()) or ((x.entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or x.location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(x.compliance_instance_id) is null or app.instance_department(x.compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[])))))));
drop policy exception_action_sel on public.exception_action;
create policy exception_action_sel on public.exception_action for select to authenticated
  using ((select app.has_permission('exception.read')) and exists (select 1 from public.exception x where x.id = exception_action.exception_id and ((select app.is_scope_all()) or ((x.entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or x.location_id = any(((select app.my_scope_ids('location'))::uuid[]))) and (app.instance_department(x.compliance_instance_id) is null or app.instance_department(x.compliance_instance_id) = any(((select app.my_scope_ids('department'))::uuid[])))))));
drop policy licence_ins on public.licence;
create policy licence_ins on public.licence for insert to authenticated
  with check ((select app.has_permission('licence.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))))));
drop policy licence_sel on public.licence;
create policy licence_sel on public.licence for select to authenticated
  using ((select app.has_permission('licence.read')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))))));
drop policy licence_upd on public.licence;
create policy licence_upd on public.licence for update to authenticated
  using ((select app.has_permission('licence.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))))))
  with check ((select app.has_permission('licence.write')) and ((select app.is_scope_all()) or ((entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or location_id = any(((select app.my_scope_ids('location'))::uuid[]))))));
drop policy licence_event_ins on public.licence_event;
create policy licence_event_ins on public.licence_event for insert to authenticated
  with check ((select app.has_permission('licence.write')) and exists (select 1 from public.licence l where l.id = licence_event.licence_id and ((select app.is_scope_all()) or ((l.entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or l.location_id = any(((select app.my_scope_ids('location'))::uuid[])))))));
drop policy licence_event_sel on public.licence_event;
create policy licence_event_sel on public.licence_event for select to authenticated
  using ((select app.has_permission('licence.read')) and exists (select 1 from public.licence l where l.id = licence_event.licence_id and ((select app.is_scope_all()) or ((l.entity_id = any(((select app.my_scope_ids('entity'))::uuid[])) or l.location_id = any(((select app.my_scope_ids('location'))::uuid[])))))));
