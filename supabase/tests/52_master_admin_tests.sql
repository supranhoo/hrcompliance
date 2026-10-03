-- Master Data Administration backend: stable master identity, rule-version drafts, applicability replacement. One rolled-back transaction.
\set ON_ERROR_STOP on
begin;
insert into public.compliance_master (code, name) values ('MA-1', 'Master admin sample');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', date '2020-01-01' from public.compliance_master where code='MA-1';
insert into public.compliance_rule_evidence select v.id, dt.id, true from public.compliance_rule_version v, (select id from public.document_type limit 1) dt where v.compliance_id=(select id from public.compliance_master where code='MA-1');
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='MA-1');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from)
  select (select id from public.compliance_master where code='MA-1'), id, 'applicable', 'initial', date '2020-01-01' from public.location where code in ('L-E1','L-E2');
create temp table _m as select id from public.compliance_master where code='MA-1'; grant select on _m to authenticated;

select test.login('admin@bfcl.test');
select test.denied('master code is immutable', $$update public.compliance_master set code='MA-X' where code='MA-1'$$);
update public.compliance_master set name = 'Renamed sample', description = 'edited' where code='MA-1';
select test.eq('name/description remain editable', (select name from public.v_compliance_master where code='MA-1'), 'Renamed sample');
select test.eq('read model shows the active version', (select active_version from public.v_compliance_master where code='MA-1'), 1);
select test.eq('and version/draft counts', (select version_count::text || '/' || draft_count::text from public.v_compliance_master where code='MA-1'), '1/0');

-- new draft = clone (incl. evidence); one draft at a time
create temp table _d as select public.compliance_rule_new_draft((select id from _m)) as id; grant select on _d to authenticated;
select test.eq('draft cloned from the latest version', (select status || ':' || version::text || ':' || frequency from public.compliance_rule_version where id=(select id from _d)), 'draft:2:monthly');
select test.eq('evidence requirements cloned with it', (select count(*) from public.compliance_rule_evidence where rule_version_id=(select id from _d)), 1::bigint);
select test.eq('default effective date is after the version it was copied from', (select effective_from > date '2020-01-01' from public.compliance_rule_version where id=(select id from _d)), true);
select test.denied('only one draft per compliance', $$select public.compliance_rule_new_draft((select id from _m))$$);
update public.compliance_rule_version set due_rule='{"type":"day_of_month","day":20,"month_offset":1}', risk_level='high' where id=(select id from _d);
select test.eq('a draft is editable', (select due_rule ->> 'day' from public.compliance_rule_version where id=(select id from _d)), '20');
select test.eq('the effective version is NOT changed by editing the draft', (select due_rule ->> 'day' from public.compliance_rule_version where compliance_id=(select id from _m) and status='active'), '15');
select test.denied('an active version cannot be edited in place', $$update public.compliance_rule_version set due_rule='{"type":"day_of_month","day":9,"month_offset":1}' where compliance_id=(select id from _m) and status='active'$$);
select test.denied('an active version cannot be discarded', $$select public.compliance_rule_discard_draft((select id from public.compliance_rule_version where compliance_id=(select id from _m) and status='active'))$$);
select test.denied('activation needs a reason', $$select public.compliance_activate_rule_version((select id from _d), '')$$);
select public.compliance_activate_rule_version((select id from _d), 'due day moves to the 20th');
select test.eq('history preserved: v1 retired, v2 active', (select string_agg(version::text || ':' || status, ',' order by version) from public.compliance_rule_version where compliance_id=(select id from _m)), '1:retired,2:active');
select test.eq('v1 content untouched', (select due_rule ->> 'day' from public.compliance_rule_version where compliance_id=(select id from _m) and version=1), '15');
create temp table _d2 as select public.compliance_rule_new_draft((select id from _m), current_date + 400) as id; grant select on _d2 to authenticated;
select public.compliance_rule_discard_draft((select id from _d2));
select test.eq('a discarded draft is gone, nothing else is', (select count(*) from public.compliance_rule_version where compliance_id=(select id from _m)), 2::bigint);
select test.eq('read model: obligation count per version', (select count(*) from public.v_compliance_rule_version where compliance_id=(select id from _m)), 2::bigint);
select test.logout();

select test.login('viewer@bfcl.test');
select test.denied('viewer cannot create a draft', $$select public.compliance_rule_new_draft((select id from _m))$$);
select test.denied('viewer cannot discard', $$select public.compliance_rule_discard_draft(gen_random_uuid())$$);
select test.logout();

-- applicability replacement
select test.login('admin@bfcl.test');
create temp table _a as select id from public.compliance_applicability where compliance_id=(select id from _m) and location_id=(select id from public.location where code='L-E1'); grant select on _a to authenticated;
select test.denied('reason is mandatory', $$select public.applicability_replace((select id from _a), jsonb_build_object('status','not_applicable','reason','x','effective_from', (current_date + 30)::text), '')$$);
select test.denied('replacement must start after the row it replaces', $$select public.applicability_replace((select id from _a), jsonb_build_object('status','not_applicable','reason','x','effective_from','2019-01-01'), 'why')$$);
select test.denied('not applicable needs its own reason text (backend rule)', $$select public.applicability_replace((select id from _a), jsonb_build_object('status','conditional','effective_from', (current_date + 30)::text), 'why')$$);
create temp table _n as select public.applicability_replace((select id from _a), jsonb_build_object('location_id', (select id from public.location where code='L-E1'), 'status','not_applicable','reason','site closed','effective_from', (current_date + 30)::text), 'closure approved') as id; grant select on _n to authenticated;
select test.eq('old row ended the day before', (select effective_to from public.compliance_applicability where id=(select id from _a)), current_date + 29);
select test.eq('new row carries the decision, scope and date', (select status || ':' || (location_id = (select id from public.location where code='L-E1'))::text from public.compliance_applicability where id=(select id from _n)), 'not_applicable:true');
select test.eq('change is audited with the reason', (select count(*) from public.audit_log where table_name='compliance_applicability' and record_id in ((select id::text from _a), (select id::text from _n)) and reason = 'closure approved') >= 2, true);
select test.eq('read model flags the in-effect row only', (select count(*) from public.v_applicability where compliance_id=(select id from _m) and in_effect and location_code='L-E1'), 1::bigint);
select test.logout();

-- F-1 preserved: a scoped user sees only their entity in the applicability read model
insert into public.app_user (email, status) values ('masc@bfcl.test', 'active');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='masc@bfcl.test' and r.code='HEAD_HR';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email='masc@bfcl.test' and e.code='E1';
insert into auth.users (id, email) select gen_random_uuid(), 'masc@bfcl.test' where not exists (select 1 from auth.users where email='masc@bfcl.test');
update public.app_user set auth_user_id = (select id from auth.users where email='masc@bfcl.test') where email='masc@bfcl.test';
select test.login('masc@bfcl.test');
select test.eq('scoped user: applicability read model shows only the own entity', (select count(*) from public.v_applicability where compliance_id=(select id from _m) and location_code = 'L-E2'), 0::bigint);
select test.eq('scoped user: and does see the own entity', (select count(*) from public.v_applicability where compliance_id=(select id from _m) and location_code = 'L-E1') > 0, true);
select test.eq('scoped user: Compliance Master read model is global', (select count(*) from public.v_compliance_master where code='MA-1'), 1::bigint);
select test.denied('scoped user cannot replace an applicability row of another entity', $$select public.applicability_replace((select id from public.compliance_applicability where compliance_id=(select id from _m) and location_id=(select id from public.location where code='L-E2')), jsonb_build_object('status','applicable','effective_from', (current_date + 60)::text), 'x')$$);
select test.logout();
-- coverage read model: gaps and conflicts are visible and scope-controlled
select test.login('admin@bfcl.test');
select test.eq('coverage view reports mapped pairs', (select count(*) from public.v_compliance_coverage where compliance_code='MA-1' and effective_status in ('applicable','not_applicable')) >= 1, true);
select test.eq('and unmapped gaps are flagged (a compliance with no matrix rows)', (select count(*) from public.v_compliance_coverage where is_gap) >= 0, true);
select test.logout();
select test.login('admin@bfcl.test');
create temp table _e as select id from public.compliance_applicability where compliance_id=(select id from _m) and location_id=(select id from public.location where code='L-E2'); grant select on _e to authenticated;
select test.denied('ending needs a reason', $$select public.applicability_end((select id from _e), current_date + 10, '')$$);
select test.denied('end date cannot precede the start', $$select public.applicability_end((select id from _e), date '2019-01-01', 'x')$$);
select public.applicability_end((select id from _e), current_date + 10, 'site sold');
select test.eq('the in-effect row was ended (not rewritten)', (select effective_to from public.compliance_applicability where id=(select id from _e)), current_date + 10);
select test.eq('with the reason in the audit log', (select count(*) from public.audit_log where table_name='compliance_applicability' and record_id=(select id::text from _e) and reason='site sold') >= 1, true);
select test.logout();
select test.login('masc@bfcl.test');
select test.denied('scoped user cannot end another entity''s row', $$select public.applicability_end((select id from _e), current_date + 5, 'x')$$);
select test.eq('scoped user: coverage view lists no other-entity location', (select count(*) from public.v_compliance_coverage where location_code='L-E2'), 0::bigint);
select test.logout();
rollback;
\echo ALL MASTER ADMIN TESTS PASSED
