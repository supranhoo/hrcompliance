-- LIVE AUTHORIZATION SANITY CHECK for migration 0039 (RLS evaluated once per statement).
-- READ-ONLY against application data; uses a session-local temp function (pg_temp, disappears when the session ends). Grants nothing, creates no permanent object, changes no data.
-- Run: Supabase SQL Editor -> new empty tab -> paste this ENTIRE file -> Run once. Nothing to edit. Last line is "-- END OF FILE".
-- It AUTO-DISCOVERS three existing, ACTIVE, auth-linked users (first by email among those holding the most read permissions):
--   profile 1: scope_all = true
--   profile 2: restricted, with entity or location scope AND department scope
--   profile 3: restricted, with entity or location scope and NO department scope
-- A profile with no suitable user is reported as "N/A - suitable existing user not found" (nothing is fabricated).
-- For each selected user it impersonates them (role authenticated + their JWT subject, as the app does) and compares the exact row ids RLS returns with the rows the ORIGINAL pre-0039
-- predicate (app.has_permission + app.scope_ok incl. department, evaluated without RLS) allows, for Compliance Register, Exceptions, Licences, plus Management Dashboard counts.
-- extra   = rows visible now that the original predicate would NOT allow  (must be 0)
-- missing = rows the original predicate allows that are NOT visible now   (must be 0)
-- EXPECTED FINAL ROW: 'ALL PROFILES' | 'OVERALL' | result PASS   (INCOMPLETE = no failure but some profile was N/A; FAIL = a mismatch: stop and report)
create or replace function pg_temp.pick(p_profile int) returns text language sql as $$
  select u.email from public.app_user u
   where u.status = 'active' and u.auth_user_id is not null
     and case p_profile
           when 1 then u.scope_all
           when 2 then not u.scope_all and exists (select 1 from public.user_scope s where s.user_id = u.id and s.scope_type in ('entity','location'))
                                       and exists (select 1 from public.user_scope s where s.user_id = u.id and s.scope_type = 'department')
           else        not u.scope_all and exists (select 1 from public.user_scope s where s.user_id = u.id and s.scope_type in ('entity','location'))
                                       and not exists (select 1 from public.user_scope s where s.user_id = u.id and s.scope_type = 'department')
         end
   order by (select count(*) from public.user_role ur join public.role_permission rp on rp.role_id = ur.role_id
              where ur.user_id = u.id and rp.permission_code in ('compliance.read','exception.read','licence.read')) desc, u.email
   limit 1
$$;

create or replace function pg_temp.sanity(p_profile text, p_email text) returns table(ord int, profile text, test_user text, what text, visible bigint, expected bigint, extra bigint, missing bigint, result text)
language plpgsql as $$
declare
  uid uuid; adm text := current_user; dash jsonb; scopes text;
  v_reg uuid[]; v_exc uuid[]; v_lic uuid[]; e_reg uuid[]; e_exc uuid[]; e_lic uuid[];
  v_od bigint; v_ta bigint; e_od bigint; e_ta bigint;
begin
  if p_email is null then
    return query select 0, p_profile, null::text, 'N/A - suitable existing user not found', null::bigint, null::bigint, null::bigint, null::bigint, 'N/A'; return;
  end if;
  select u.auth_user_id, format('roles: %s; scopes: %s entity, %s location, %s department', coalesce((select string_agg(r.code, ',' order by r.code) from public.user_role ur join public.role r on r.id = ur.role_id where ur.user_id = u.id), 'none'),
         (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'entity'), (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'location'),
         (select count(*) from public.user_scope s where s.user_id = u.id and s.scope_type = 'department')) || case when u.scope_all then '; scope_all' else '' end
    into uid, scopes from public.app_user u where u.email = p_email;
  return query select 0, p_profile, p_email, 'selected user (' || scopes || ')', null::bigint, null::bigint, null::bigint, null::bigint, 'INFO';
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  -- ORIGINAL pre-0039 predicate, evaluated without RLS (identity still comes from the JWT subject above)
  e_reg := array(select id from public.compliance_instance where app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
  e_exc := array(select id from public.exception where app.has_permission('exception.read') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id)));
  e_lic := array(select id from public.licence where app.has_permission('licence.read') and app.scope_ok(entity_id, location_id));
  e_od := (select count(*) from public.compliance_instance where status in ('open','in_progress') and due_date < current_date and app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
  e_ta := (select count(*) from public.compliance_instance where status <> 'not_applicable' and due_date between (current_date - interval '12 months')::date and current_date and app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id)));
  -- WHAT THE APP SEES: switch to the authenticated role so RLS applies
  perform set_config('role', 'authenticated', true);
  v_reg := array(select id from public.compliance_instance);
  v_exc := array(select id from public.exception);
  v_lic := array(select id from public.licence);
  begin dash := public.management_dashboard(); exception when others then dash := null; end;
  perform set_config('role', adm, true);
  v_od := coalesce((dash -> 'kpis' ->> 'overdue')::bigint, 0); v_ta := coalesce((dash -> 'kpis' ->> 'total_applicable')::bigint, 0);
  return query select 1, p_profile, p_email, 'Compliance Register rows', cardinality(v_reg)::bigint, cardinality(e_reg)::bigint,
    (select count(*) from unnest(v_reg) x where x <> all (e_reg)), (select count(*) from unnest(e_reg) x where x <> all (v_reg)), null::text;
  return query select 2, p_profile, p_email, 'Exceptions rows', cardinality(v_exc)::bigint, cardinality(e_exc)::bigint,
    (select count(*) from unnest(v_exc) x where x <> all (e_exc)), (select count(*) from unnest(e_exc) x where x <> all (v_exc)), null::text;
  return query select 3, p_profile, p_email, 'Licences rows', cardinality(v_lic)::bigint, cardinality(e_lic)::bigint,
    (select count(*) from unnest(v_lic) x where x <> all (e_lic)), (select count(*) from unnest(e_lic) x where x <> all (v_lic)), null::text;
  return query select 4, p_profile, p_email, 'Dashboard: overdue', v_od, e_od, greatest(v_od - e_od, 0), greatest(e_od - v_od, 0), null::text;
  return query select 5, p_profile, p_email, 'Dashboard: total applicable (12 months)', v_ta, e_ta, greatest(v_ta - e_ta, 0), greatest(e_ta - v_ta, 0), null::text;
end $$;

with raw as (
  select s.* from (values (1, 'profile 1: scope_all'), (2, 'profile 2: restricted, entity/location + department'), (3, 'profile 3: restricted, entity/location, no department')) p(n, label),
       lateral pg_temp.sanity(p.label, pg_temp.pick(p.n)) s
), res as (
  select ord, profile, test_user, what, visible, expected, extra, missing,
         case when result is not null then result when extra = 0 and missing = 0 then 'PASS' else 'FAIL' end as result
    from raw)
select * from (select * from res
union all
select 9, 'ALL PROFILES', null, 'OVERALL', null, null, coalesce(sum(extra), 0), coalesce(sum(missing), 0),
       case when bool_or(result = 'FAIL') then 'FAIL' when bool_or(result = 'N/A') or not bool_or(result = 'PASS') then 'INCOMPLETE' else 'PASS' end
  from res) z
order by (profile = 'ALL PROFILES'), profile, ord;
-- END OF FILE
