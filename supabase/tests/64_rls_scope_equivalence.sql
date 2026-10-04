-- The per-statement RLS predicates (migration 0039) must grant exactly what the original per-row functions grant: for every kind of user, the rows RLS returns equal the rows
-- the original predicate (app.has_permission AND app.scope_ok with the department) selects. Rolled back.
\set ON_ERROR_STOP on
begin;
insert into public.department (code, name) values ('EQ-X', 'eq dept X'), ('EQ-Y', 'eq dept Y');
insert into public.compliance_master (code, name, owner_department_id) values
  ('EQ-M0', 'no dept', null), ('EQ-MX', 'dept X', (select id from public.department where code = 'EQ-X')), ('EQ-MY', 'dept Y', (select id from public.department where code = 'EQ-Y'));
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', date '2000-01-01' from public.compliance_master where code like 'EQ-M%';
update public.compliance_rule_version set status = 'active' where compliance_id in (select id from public.compliance_master where code like 'EQ-M%');
insert into public.compliance_instance (instance_no, compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, status, source)
  select 'EQ-' || m.code || '-' || l.code, m.id, v.id, l.entity_id, l.id, date '2001-01-01', date '2001-01-28', date '2001-02-10', 'open', 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l where m.code like 'EQ-M%' and l.code in ('L-E1','L-E1B','L-E2');
insert into public.exception (exception_no, category, severity, description, compliance_instance_id, entity_id, location_id, detection_key, source, status)
  select 'EQ-EXC-' || i.instance_no, 'manual', 'low', 'eq', i.id, i.entity_id, i.location_id, 'eq:' || i.instance_no, 'manual', 'open' from public.compliance_instance i where i.instance_no like 'EQ-%';
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from)
  select m.id, l.id, 'applicable', 'eq ' || m.code || l.code, date '2020-01-01' from public.compliance_master m, public.location l where m.code like 'EQ-M%' and l.code in ('L-E1','L-E2');
insert into public.compliance_applicability (compliance_id, status, effective_from) select id, 'applicable', date '2020-01-01' from public.compliance_master where code = 'EQ-M0';       -- global row: scope_all only
insert into public.compliance_applicability (compliance_id, entity_id, status, effective_from) select m.id, e.id, 'applicable', date '2020-01-01' from public.compliance_master m, public.entity e where m.code = 'EQ-MX' and e.code = 'E1';
insert into public.authority (code, name) values ('EQ-AUTH', 'eq authority');
insert into public.licence_type (code, name, authority_id, default_risk) select 'EQ-LT', 'eq type', id, 'low' from public.authority where code = 'EQ-AUTH';
insert into public.licence (licence_type_id, entity_id, location_id, authority_id, licence_number, issue_date, expiry_date)
  select (select id from public.licence_type where code = 'EQ-LT'), l.entity_id, l.id, (select id from public.authority where code = 'EQ-AUTH'), 'EQ-' || l.code, date '2020-01-01', current_date + 100 from public.location l where l.code in ('L-E1','L-E1B','L-E2');
insert into public.licence (licence_type_id, entity_id, authority_id, licence_number, issue_date, expiry_date)           -- entity-level licence without a location
  select (select id from public.licence_type where code = 'EQ-LT'), e.id, (select id from public.authority where code = 'EQ-AUTH'), 'EQ-ENT-' || e.code, date '2020-01-01', current_date + 100 from public.entity e where e.code in ('E1','E2');

create or replace function test.mkuser(p_email text, p_role text, p_all boolean) returns void language plpgsql as $$
begin
  insert into public.app_user (email, status, scope_all) values (p_email, 'active', p_all);
  insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email = p_email and r.code = p_role;
  insert into auth.users (id, email) select gen_random_uuid(), p_email where not exists (select 1 from auth.users where email = p_email);
  update public.app_user set auth_user_id = (select id from auth.users where email = p_email) where email = p_email;
end $$;
create or replace function test.scope(p_email text, p_type text, p_code text) returns void language sql as $$
  insert into public.user_scope (user_id, scope_type, scope_id)
  select u.id, p_type, case p_type when 'entity' then (select id from public.entity where code = p_code) when 'location' then (select id from public.location where code = p_code) else (select id from public.department where code = p_code) end
    from public.app_user u where u.email = p_email $$;
insert into public.role (code, name) values ('EQ_NOPERM', 'no perms');
select test.mkuser('eq_all@bfcl.test', 'HEAD_HR', true);
select test.mkuser('eq_ent@bfcl.test', 'HEAD_HR', false);        select test.scope('eq_ent@bfcl.test', 'entity', 'E1');
select test.mkuser('eq_loc@bfcl.test', 'HEAD_HR', false);        select test.scope('eq_loc@bfcl.test', 'location', 'L-E1B');
select test.mkuser('eq_entdep@bfcl.test', 'HEAD_HR', false);     select test.scope('eq_entdep@bfcl.test', 'entity', 'E1'); select test.scope('eq_entdep@bfcl.test', 'department', 'EQ-X');
select test.mkuser('eq_locdep@bfcl.test', 'HEAD_HR', false);     select test.scope('eq_locdep@bfcl.test', 'location', 'L-E2'); select test.scope('eq_locdep@bfcl.test', 'department', 'EQ-Y'); select test.scope('eq_locdep@bfcl.test', 'department', 'EQ-X');
select test.mkuser('eq_deponly@bfcl.test', 'HEAD_HR', false);    select test.scope('eq_deponly@bfcl.test', 'department', 'EQ-X');
select test.mkuser('eq_mixed@bfcl.test', 'HEAD_HR', false);      select test.scope('eq_mixed@bfcl.test', 'entity', 'E2'); select test.scope('eq_mixed@bfcl.test', 'location', 'L-E1B'); select test.scope('eq_mixed@bfcl.test', 'department', 'EQ-Y');
select test.mkuser('eq_none@bfcl.test', 'HEAD_HR', false);
select test.mkuser('eq_noperm@bfcl.test', 'EQ_NOPERM', true);
select test.mkuser('eq_viewer@bfcl.test', 'VIEWER', false);      select test.scope('eq_viewer@bfcl.test', 'entity', 'E1');
update public.app_user set status = 'disabled' where email = 'eq_viewer@bfcl.test';

-- owner-executed (bypasses RLS) evaluation of the ORIGINAL predicates under the caller's identity (auth.uid() still comes from the session)
create or replace function test.expected(p_sql text) returns text language plpgsql security definer set search_path = public as $$
declare r text; begin execute 'select coalesce(string_agg(x::text, '','' order by x::text), ''-'') from (' || p_sql || ') s(x)' into r; return r; end $$;
create or replace function test.visible(p_sql text) returns text language plpgsql as $$
declare r text; begin execute 'select coalesce(string_agg(x::text, '','' order by x::text), ''-'') from (' || p_sql || ') s(x)' into r; return r; end $$;
grant execute on all functions in schema test to authenticated, anon;

create or replace function test.compare(p_user text) returns void language plpgsql as $$
declare t record; v text; e text; begin
  perform test.login(p_user);
  for t in select * from (values
    ('compliance_instance', $q$select id from public.compliance_instance where instance_no like 'EQ-%'$q$, $q$select id from public.compliance_instance where instance_no like 'EQ-%' and app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id))$q$),
    ('exception', $q$select id from public.exception where exception_no like 'EQ-EXC-%'$q$, $q$select id from public.exception where exception_no like 'EQ-EXC-%' and app.has_permission('exception.read') and app.scope_ok(entity_id, location_id, app.instance_department(compliance_instance_id))$q$),
    ('licence', $q$select id from public.licence where licence_number like 'EQ-%'$q$, $q$select id from public.licence where licence_number like 'EQ-%' and app.has_permission('licence.read') and app.scope_ok(entity_id, location_id)$q$),
    ('applicability', $q$select id from public.compliance_applicability where compliance_id in (select id from public.compliance_master where code like 'EQ-M%')$q$, $q$select id from public.compliance_applicability where compliance_id in (select id from public.compliance_master where code like 'EQ-M%') and app.has_permission('compliance.read') and app.scope_ok(entity_id, location_id, app.compliance_department(compliance_id))$q$)
  ) as x(tbl, vis, exp) loop
    v := test.visible(t.vis); e := test.expected(t.exp);
    if v is distinct from e then raise exception 'FAIL [% / %]: RLS shows % but the original predicate grants %', p_user, t.tbl, v, e; end if;
    raise notice 'ok   - % sees the same % rows as the original predicate (%)', p_user, t.tbl, (select count(*) from regexp_split_to_table(case when v = '-' then '' else v end, ',') where true) ;
  end loop;
  perform test.logout();
end $$;
grant execute on all functions in schema test to authenticated, anon;

select test.compare(u) from unnest(array['eq_all@bfcl.test','eq_ent@bfcl.test','eq_loc@bfcl.test','eq_entdep@bfcl.test','eq_locdep@bfcl.test','eq_deponly@bfcl.test','eq_mixed@bfcl.test','eq_none@bfcl.test','eq_noperm@bfcl.test','eq_viewer@bfcl.test','admin@bfcl.test','plant@bfcl.test']) u;

-- sanity: the fixture really discriminates (some users see some rows, none see everything but scope_all)
select test.login('eq_entdep@bfcl.test');
select test.eq('entity+department user sees E1 obligations of its department or of no department only', test.visible($$select substr(instance_no, 4, 5) || '@' || location_code from public.v_compliance_instance where instance_no like 'EQ-%'$$), test.visible($$select substr(instance_no, 4, 5) || '@' || location_code from public.v_compliance_instance where instance_no like 'EQ-%' and location_code in ('L-E1','L-E1B') and substr(instance_no, 4, 5) in ('EQ-M0','EQ-MX')$$));
select test.logout();
select test.login('eq_all@bfcl.test');
select test.eq('all-locations user sees every fixture obligation', (select count(*) from public.compliance_instance where instance_no like 'EQ-%'), 9::bigint);
select test.logout();
select test.login('eq_none@bfcl.test');
select test.eq('no scope: nothing', (select count(*) from public.compliance_instance where instance_no like 'EQ-%'), 0::bigint);
select test.logout();
rollback;
\echo ALL RLS SCOPE EQUIVALENCE TESTS PASSED
