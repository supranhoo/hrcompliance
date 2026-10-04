-- Department scope: an additional dimension only where the resource has a department (obligation department = its master's owner department; null = not department-specific). Rolled back.
\set ON_ERROR_STOP on
begin;
insert into public.department (code, name) values ('DA', 'Dept A'), ('DB', 'Dept B');
insert into public.compliance_master (code, name, owner_department_id) values
  ('DM-A', 'dept A obligation', (select id from public.department where code='DA')), ('DM-B', 'dept B obligation', (select id from public.department where code='DB')), ('DM-N', 'entity-wide obligation', null);
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', date '2020-01-01' from public.compliance_master where code like 'DM-%';
update public.compliance_rule_version set status='active' where compliance_id in (select id from public.compliance_master where code like 'DM-%');
insert into public.compliance_instance (instance_no, compliance_id, rule_version_id, entity_id, location_id, period_start, period_end, due_date, source)
  select 'DS-' || m.code || '-' || l.code, m.id, v.id, l.entity_id, l.id, date '2031-01-01', date '2031-01-31', date '2031-02-20', 'manual'
    from public.compliance_master m join public.compliance_rule_version v on v.compliance_id = m.id and v.status = 'active', public.location l where m.code like 'DM-%' and l.code in ('L-E1','L-E2');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from)
  select m.id, l.id, 'applicable', 'ds ' || m.code || ' ' || l.code, date '2020-01-01' from public.compliance_master m, public.location l where m.code like 'DM-%' and l.code in ('L-E1','L-E2');
insert into public.role (code, name) values ('NOPERM', 'no permissions');

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
select test.mkuser('ds_all@bfcl.test', 'HEAD_HR', true);
select test.mkuser('ds_ea@bfcl.test', 'HEAD_HR', false);      select test.scope('ds_ea@bfcl.test', 'entity', 'E1');     select test.scope('ds_ea@bfcl.test', 'department', 'DA');
select test.mkuser('ds_la@bfcl.test', 'HEAD_HR', false);      select test.scope('ds_la@bfcl.test', 'location', 'L-E1'); select test.scope('ds_la@bfcl.test', 'department', 'DA');
select test.mkuser('ds_nodept@bfcl.test', 'HEAD_HR', false);  select test.scope('ds_nodept@bfcl.test', 'entity', 'E1');
select test.mkuser('ds_deponly@bfcl.test', 'HEAD_HR', false); select test.scope('ds_deponly@bfcl.test', 'department', 'DA');
select test.mkuser('ds_a_e2@bfcl.test', 'HEAD_HR', false);    select test.scope('ds_a_e2@bfcl.test', 'location', 'L-E2'); select test.scope('ds_a_e2@bfcl.test', 'department', 'DA');
select test.mkuser('ds_none@bfcl.test', 'HEAD_HR', false);
select test.mkuser('ds_noperm@bfcl.test', 'NOPERM', false);   select test.scope('ds_noperm@bfcl.test', 'entity', 'E1');     select test.scope('ds_noperm@bfcl.test', 'department', 'DA');
create or replace function test.rows(p_stmt text) returns bigint language plpgsql as $$ declare n bigint; begin execute p_stmt; get diagnostics n = row_count; return n; end $$;
grant execute on all functions in schema test to authenticated, anon;

create or replace function test.inst(p_master text, p_loc text) returns bigint language sql stable as $$
  select count(*) from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.location l on l.id = i.location_id where m.code = p_master and l.code = p_loc $$;
create or replace function test.insts() returns text language sql stable as $$
  select coalesce(string_agg(m.code || '@' || l.code, ',' order by m.code, l.code), '-') from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.location l on l.id = i.location_id where m.code like 'DM-%' $$;
grant execute on all functions in schema test to authenticated, anon;

select test.login('ds_all@bfcl.test');
select test.eq('scope_all sees every department and location', test.insts(), 'DM-A@L-E1,DM-A@L-E2,DM-B@L-E1,DM-B@L-E2,DM-N@L-E1,DM-N@L-E2');
select test.logout();
select test.login('ds_ea@bfcl.test');
select test.eq('entity + department: own entity, own department and entity-wide only (no Dept B, no other entity)', test.insts(), 'DM-A@L-E1,DM-N@L-E1');
select test.eq('same location, other department is denied', test.inst('DM-B', 'L-E1'), 0::bigint);
select test.logout();
select test.login('ds_la@bfcl.test');
select test.eq('location + department: matches', test.insts(), 'DM-A@L-E1,DM-N@L-E1');
select test.logout();
select test.login('ds_nodept@bfcl.test');
select test.eq('no department scope: department-specific records are denied, entity-wide ones follow entity/location', test.insts(), 'DM-N@L-E1');
select test.eq('department_id null falls back to the existing rule (visible)', test.inst('DM-N', 'L-E1'), 1::bigint);
select test.eq('Dept A obligation hidden without Dept A scope', test.inst('DM-A', 'L-E1'), 0::bigint);
select test.eq('applicability follows the same rule', test.count($$select 1 from public.compliance_applicability a join public.compliance_master m on m.id = a.compliance_id where m.code in ('DM-A','DM-B')$$), 0::bigint);
select test.eq('...and entity-wide applicability is visible', test.count($$select 1 from public.compliance_applicability a join public.compliance_master m on m.id = a.compliance_id where m.code = 'DM-N' and a.reason like 'ds %'$$), 1::bigint);
select test.eq('coverage follows the same rule', (select string_agg(compliance_code || '@' || location_code, ',' order by compliance_code) from public.compliance_coverage() where compliance_code like 'DM-%' and location_code in ('L-E1','L-E2')), 'DM-N@L-E1');
select test.eq('no UPDATE on a department-specific obligation (0 rows)', test.rows($$update public.compliance_instance set custom = '{"x":1}' where instance_no like 'DS-DM-A-%'$$), 0::bigint);
select test.logout();
select test.login('ds_ea@bfcl.test');
select test.eq('with department scope the update works', test.rows($$update public.compliance_instance set custom = '{"x":1}' where instance_no = 'DS-DM-A-L-E1'$$), 1::bigint);
select test.eq('applicability for the own department is visible', test.count($$select 1 from public.compliance_applicability a join public.compliance_master m on m.id = a.compliance_id where m.code = 'DM-A' and a.reason like 'ds %'$$), 1::bigint);
select test.eq('coverage shows own department + entity-wide at own location', (select string_agg(compliance_code || '@' || location_code, ',' order by compliance_code) from public.compliance_coverage() where compliance_code like 'DM-%' and location_code in ('L-E1','L-E2')), 'DM-A@L-E1,DM-N@L-E1');
select test.logout();
select test.login('ds_a_e2@bfcl.test');
select test.eq('matching department but wrong location: denied (L-E1 hidden, L-E2 visible)', test.insts(), 'DM-A@L-E2,DM-N@L-E2');
select test.logout();
select test.login('ds_deponly@bfcl.test');
select test.eq('department alone never grants access (fail closed)', test.insts(), '-');
select test.logout();
select test.login('ds_none@bfcl.test');
select test.eq('no scope at all: fail closed', test.insts(), '-');
select test.eq('...but globally readable masters are unaffected: locations', test.count($$select 1 from public.location where code in ('L-E1','L-E2')$$), 2::bigint);
select test.eq('...entities', test.count($$select 1 from public.entity where code in ('E1','E2')$$), 2::bigint);
select test.eq('...and the Compliance Master', test.count($$select 1 from public.compliance_master where code like 'DM-%'$$), 3::bigint);
select test.logout();
select test.login('ds_noperm@bfcl.test');
select test.eq('scope without the role permission is not enough', test.insts(), '-');
select test.logout();

-- helper contracts
select test.login('ds_nodept@bfcl.test');
select test.eq('2-argument in_scope is unchanged', app.in_scope((select id from public.entity where code='E1'), (select id from public.location where code='L-E1')), true);
select test.eq('3-argument with a department the user lacks', app.in_scope((select id from public.entity where code='E1'), (select id from public.location where code='L-E1'), (select id from public.department where code='DA')), false);
select test.eq('3-argument with no department behaves like the 2-argument form', app.in_scope((select id from public.entity where code='E1'), (select id from public.location where code='L-E1'), null), true);
select test.logout();
select test.eq('user_scope_ok: matching department', app.user_scope_ok((select id from public.app_user where email='ds_ea@bfcl.test'), (select id from public.entity where code='E1'), (select id from public.location where code='L-E1'), (select id from public.department where code='DA')), true);
select test.eq('user_scope_ok: wrong department', app.user_scope_ok((select id from public.app_user where email='ds_ea@bfcl.test'), (select id from public.entity where code='E1'), (select id from public.location where code='L-E1'), (select id from public.department where code='DB')), false);
select test.eq('user_scope_ok: scope_all', app.user_scope_ok((select id from public.app_user where email='ds_all@bfcl.test'), null, null, (select id from public.department where code='DB')), true);
select test.eq('existing 3-argument user_scope_ok is unchanged', app.user_scope_ok((select id from public.app_user where email='ds_nodept@bfcl.test'), (select id from public.entity where code='E1'), (select id from public.location where code='L-E1')), true);
select test.eq('recipients: a role recipient is only resolved for users who could open the obligation',
  (select string_agg(a.email, ',' order by a.email) from app.resolve_recipients('["role:HEAD_HR"]'::jsonb, null, (select id from public.entity where code='E1'), (select id from public.location where code='L-E1'), (select id from public.department where code='DA')) r(u) join public.app_user a on a.id = r.u where a.email like 'ds\_%'),
  'ds_all@bfcl.test,ds_ea@bfcl.test,ds_la@bfcl.test');
select test.eq('recipients: entity-wide obligation reaches every user in entity scope',
  (select string_agg(a.email, ',' order by a.email) from app.resolve_recipients('["role:HEAD_HR"]'::jsonb, null, (select id from public.entity where code='E1'), (select id from public.location where code='L-E1'), null) r(u) join public.app_user a on a.id = r.u where a.email like 'ds\_%'),
  'ds_all@bfcl.test,ds_ea@bfcl.test,ds_la@bfcl.test,ds_nodept@bfcl.test');
rollback;
\echo ALL DEPARTMENT SCOPE TESTS PASSED
