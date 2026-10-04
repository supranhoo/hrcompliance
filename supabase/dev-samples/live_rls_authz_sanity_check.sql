-- LIVE AUTHORIZATION SANITY CHECK for migration 0039. READ-ONLY, creates nothing permanent (one temp function that disappears with the session), grants nothing, changes no data.
-- Supabase SQL Editor: new empty tab, paste the ENTIRE file, edit ONLY the email list on the line marked EDIT, Run once. Last line is "-- END OF FILE".
-- For each listed user it impersonates them (role authenticated + their JWT subject, exactly as the app does) and compares what row-level security returns with what the ORIGINAL pre-0039 predicate
-- (app.has_permission + app.scope_ok incl. department, evaluated without RLS) says they may see: Compliance Register rows, Exceptions, Licences, and the Management Dashboard counts.
-- EXPECTED: every row result = PASS (visible = expected, extra = 0). Any extra > 0 means MORE rows are visible than before 0039: stop and report.
-- Use at least: a SUPER_ADMIN / scope_all user, a restricted entity/location/department user, a restricted user with NO department scope (if that is a valid configuration for you).
create or replace function pg_temp.sanity(p_email text) returns table(who text, what text, visible bigint, expected bigint, extra bigint, result text) language plpgsql as $$
declare
  uid uuid; adm text := current_user; dash jsonb;
  v_reg bigint; v_exc bigint; v_lic bigint; v_od bigint; v_ta bigint;
  e_reg bigint; e_exc bigint; e_lic bigint; e_od bigint; e_ta bigint;
  x_reg bigint; x_exc bigint; x_lic bigint;
begin
  select auth_user_id into uid from public.app_user where email = p_email;
  if uid is null then return query select p_email, 'user not found / no auth id', null::bigint, null::bigint, null::bigint, 'FAIL'; return; end if;
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  -- ORIGINAL predicate, evaluated without RLS (as the admin role, identity still comes from the JWT subject above)
  e_reg := (select count(*) from public.compliance_instance where app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
  e_exc := (select count(*) from public.exception where app.has_permission('exception.read') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));
  e_lic := (select count(*) from public.licence where app.has_permission('licence.read') and app.scope_ok(entity_id, location_id));
  e_od := (select count(*) from public.compliance_instance where status in ('open','in_progress') and due_date < current_date and app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
  e_ta := (select count(*) from public.compliance_instance where status <> 'not_applicable' and due_date between (current_date - interval '12 months')::date and current_date and app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
  -- WHAT THE APP SEES: switch to the authenticated role, so RLS applies
  perform set_config('role', 'authenticated', true);
  v_reg := (select count(*) from public.compliance_instance);
  v_exc := (select count(*) from public.exception);
  v_lic := (select count(*) from public.licence);
  begin dash := public.management_dashboard(); exception when others then dash := null; end;
  v_od := (dash -> 'kpis' ->> 'overdue')::bigint; v_ta := (dash -> 'kpis' ->> 'total_applicable')::bigint;
  if dash is not null and v_od is null then v_od := (dash ->> 'overdue')::bigint; v_ta := (dash ->> 'total_applicable')::bigint; end if;
  perform set_config('role', adm, true);
  return query select p_email, 'Compliance Register rows', v_reg, e_reg, greatest(v_reg - e_reg, 0), case when v_reg = e_reg then 'PASS' else 'FAIL' end;
  return query select p_email, 'Exceptions rows', v_exc, e_exc, greatest(v_exc - e_exc, 0), case when v_exc = e_exc then 'PASS' else 'FAIL' end;
  return query select p_email, 'Licences rows', v_lic, e_lic, greatest(v_lic - e_lic, 0), case when v_lic = e_lic then 'PASS' else 'FAIL' end;
  return query select p_email, 'Dashboard: overdue', v_od, e_od, greatest(coalesce(v_od, 0) - e_od, 0), case when v_od = e_od or (dash is null and e_reg = 0) then 'PASS' else 'FAIL' end;
  return query select p_email, 'Dashboard: total applicable (12 months)', v_ta, e_ta, greatest(coalesce(v_ta, 0) - e_ta, 0), case when v_ta = e_ta or (dash is null and e_reg = 0) then 'PASS' else 'FAIL' end;
end $$;

with res as (
  select r.*
    from unnest(array[
      'REPLACE_WITH_SUPER_ADMIN_EMAIL',            -- EDIT: scope_all user
      'REPLACE_WITH_RESTRICTED_USER_EMAIL',        -- EDIT: restricted entity/location + department scopes
      'REPLACE_WITH_USER_WITHOUT_DEPARTMENT_SCOPE' -- EDIT: restricted user with no department scope (delete this line if none exists)
    ]) as u(email), lateral pg_temp.sanity(u.email) r)
select * from res
union all
select 'ALL USERS', 'OVERALL', null, null, sum(extra), case when bool_and(result = 'PASS') then 'PASS' else 'FAIL' end from res
order by 1, 2;
-- END OF FILE
