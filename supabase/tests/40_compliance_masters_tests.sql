-- Compliance master, due-rule language, LOV guards, rule-version immutability. Reuses helpers/fixtures from 10_*.sql.
\set ON_ERROR_STOP on

-- ---------- due-rule validator ----------
select test.eq('monthly day_of_month valid', app.due_rule_is_valid('{"type":"day_of_month","day":20,"month_offset":1}', 'monthly'), true);
select test.eq('day 32 rejected', app.due_rule_is_valid('{"type":"day_of_month","day":32,"month_offset":1}', 'monthly'), false);
select test.eq('unknown type rejected', app.due_rule_is_valid('{"type":"shell","cmd":"x"}', 'monthly'), false);
select test.eq('string day rejected', app.due_rule_is_valid('{"type":"day_of_month","day":"20; drop","month_offset":1}', 'monthly'), false);
select test.eq('event_based needs days_after_event', app.due_rule_is_valid('{"type":"day_of_month","day":5,"month_offset":0}', 'event_based'), false);
select test.eq('event_based days_after_event valid', app.due_rule_is_valid('{"type":"days_after_event","days":30}', 'event_based'), true);
select test.eq('periodic cannot use days_after_event', app.due_rule_is_valid('{"type":"days_after_event","days":30}', 'monthly'), false);
select test.eq('one_time needs absolute_date', app.due_rule_is_valid('{"type":"days_after_period_end","days":5}', 'one_time'), false);
select test.eq('one_time absolute_date valid', app.due_rule_is_valid('{"type":"absolute_date","date":"2027-03-31"}', 'one_time'), true);
select test.eq('non-object rejected', app.due_rule_is_valid('[1]', 'monthly'), false);

-- ---------- due-date computation ----------
select test.eq('monthly: Jan period, 20th of next month', app.compute_due_date('{"type":"day_of_month","day":20,"month_offset":1}', date '2026-01-01', date '2026-01-31'), date '2026-02-20');
select test.eq('day 31 clamps to Feb month end', app.compute_due_date('{"type":"day_of_month","day":31,"month_offset":1}', date '2026-01-01', date '2026-01-31'), date '2026-02-28');
select test.eq('day 31 clamps to leap Feb 29', app.compute_due_date('{"type":"day_of_month","day":31,"month_offset":1}', date '2028-01-01', date '2028-01-31'), date '2028-02-29');
select test.eq('same-month due (offset 0)', app.compute_due_date('{"type":"day_of_month","day":7,"month_offset":0}', date '2026-03-01', date '2026-03-31'), date '2026-03-07');
select test.eq('year-end rollover (Dec -> Jan)', app.compute_due_date('{"type":"day_of_month","day":15,"month_offset":1}', date '2026-12-01', date '2026-12-31'), date '2027-01-15');
select test.eq('days_after_period_end', app.compute_due_date('{"type":"days_after_period_end","days":45}', date '2026-01-01', date '2026-03-31'), date '2026-05-15');
select test.eq('fixed_date same year', app.compute_due_date('{"type":"fixed_date","month":6,"day":30,"year_offset":0}', date '2025-04-01', date '2026-03-31'), date '2026-06-30');
select test.eq('fixed_date next year', app.compute_due_date('{"type":"fixed_date","month":1,"day":31,"year_offset":1}', date '2026-01-01', date '2026-12-31'), date '2027-01-31');
select test.eq('fixed_date Feb 30 clamps', app.compute_due_date('{"type":"fixed_date","month":2,"day":30,"year_offset":0}', date '2026-01-01', date '2026-12-31'), date '2026-02-28');
select test.eq('absolute_date', app.compute_due_date('{"type":"absolute_date","date":"2027-03-31"}', date '2026-01-01', date '2026-01-01'), date '2027-03-31');
select test.eq('days_after_event', app.compute_due_date('{"type":"days_after_event","days":30}', date '2026-05-10', date '2026-05-10'), date '2026-06-09');
select test.denied('unsupported type refused at compute time', $$select app.compute_due_date('{"type":"x"}', current_date, current_date)$$);

-- ---------- access ----------
select test.login('viewer@bfcl.test');
select test.eq('viewer (compliance.read) can read masters', test.count('select * from public.compliance_master'), 0::bigint);
select test.denied('viewer cannot create category', $$insert into public.compliance_category(code,name) values ('LAB','Labour')$$);
select test.denied('viewer cannot create master', $$insert into public.compliance_master(code,name) values ('PF-RET','x')$$);
select test.logout();
select test.login('stranger@gmail.com');
select test.denied('unprovisioned cannot create master', $$insert into public.compliance_master(code,name) values ('PF-RET','x')$$);
select test.eq('unprovisioned sees nothing', test.count('select * from public.compliance_category'), 0::bigint);
select test.logout();

-- ---------- masters + LOV guards (as admin) ----------
select test.login('admin@bfcl.test');
insert into public.compliance_category (code, name) values ('CAT-A', 'Category A');
select test.denied('code format enforced', $$insert into public.compliance_master(code,name) values ('bad code','x')$$);
select test.denied('domain must be an active LOV value', $$insert into public.compliance_master(code,name,domain) values ('CM-1','One','labour')$$);
insert into public.lov_value (set_id, code, label) select id, 'labour', 'Labour' from public.lov_set where code='COMPLIANCE_DOMAIN';
insert into public.compliance_master (code, name, domain, category_id, section_reference, legal_source, last_reviewed_at)
  select 'CM-1', 'Sample monthly return', 'labour', c.id, 'as supplied by BFCL', 'BFCL-verified reference', date '2026-09-01' from public.compliance_category c where c.code='CAT-A';
update public.lov_value set is_active = false where code='labour';
update public.compliance_master set description = 'edited after the LOV value was retired' where code='CM-1';
select test.eq('retiring a LOV value does not block unrelated edits', (select description from public.compliance_master where code='CM-1'), 'edited after the LOV value was retired');
insert into public.lov_value (set_id, code, label, is_active) select id, 'safety', 'Safety', false from public.lov_set where code='COMPLIANCE_DOMAIN';
select test.denied('but changing to a retired LOV value is refused', $$update public.compliance_master set domain='safety' where code='CM-1'$$);
update public.lov_value set is_active = true where code='labour';

-- ---------- rule versions ----------
select test.denied('invalid compliance_type rejected', $$insert into public.compliance_rule_version(compliance_id,compliance_type,frequency,due_rule,risk_level,effective_from) select id,'made_up','monthly','{"type":"day_of_month","day":20,"month_offset":1}','high',date '2026-01-01' from public.compliance_master where code='CM-1'$$);
select test.denied('invalid risk rejected', $$insert into public.compliance_rule_version(compliance_id,compliance_type,frequency,due_rule,risk_level,effective_from) select id,'statutory','monthly','{"type":"day_of_month","day":20,"month_offset":1}','extreme',date '2026-01-01' from public.compliance_master where code='CM-1'$$);
select test.denied('invalid due_rule rejected by CHECK', $$insert into public.compliance_rule_version(compliance_id,compliance_type,frequency,due_rule,risk_level,effective_from) select id,'statutory','monthly','{"type":"js","code":"x"}','high',date '2026-01-01' from public.compliance_master where code='CM-1'$$);
select test.denied('versions must start as draft', $$insert into public.compliance_rule_version(compliance_id,status,compliance_type,frequency,due_rule,risk_level,effective_from) select id,'active','statutory','monthly','{"type":"day_of_month","day":20,"month_offset":1}','high',date '2026-01-01' from public.compliance_master where code='CM-1'$$);
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, criticality, evidence_required, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":20,"month_offset":1}', 'high', 'critical', true, date '2026-01-01' from public.compliance_master where code='CM-1';
select test.eq('first version numbered 1', (select version from public.compliance_rule_version), 1);
insert into public.document_type (code, name) values ('CHALLAN', 'Challan');
insert into public.compliance_rule_evidence (rule_version_id, document_type_id) select v.id, d.id from public.compliance_rule_version v, public.document_type d where d.code='CHALLAN';
select test.eq('draft evidence requirement stored', (select count(*) from public.compliance_rule_evidence), 1::bigint);
select test.denied('activation needs a reason', $$select public.compliance_activate_rule_version((select id from public.compliance_rule_version), '  ')$$);
select public.compliance_activate_rule_version((select id from public.compliance_rule_version where version=1), 'initial publication');
select test.eq('v1 active', (select status from public.compliance_rule_version where version=1), 'active');
select test.denied('published due_rule immutable', $$update public.compliance_rule_version set due_rule='{"type":"day_of_month","day":25,"month_offset":1}' where version=1$$);
select test.denied('published frequency immutable', $$update public.compliance_rule_version set frequency='quarterly' where version=1$$);
select test.denied('published evidence flag immutable', $$update public.compliance_rule_version set evidence_required=false where version=1$$);
select test.denied('published evidence requirements immutable (delete)', $$delete from public.compliance_rule_evidence$$);
insert into public.document_type (code, name) values ('PAYSLIP', 'Payslip');
select test.denied('published evidence requirements immutable (insert)', $$insert into public.compliance_rule_evidence(rule_version_id,document_type_id) select v.id,d.id from public.compliance_rule_version v, public.document_type d where d.code='PAYSLIP' and v.version=1$$);
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, criticality, evidence_required, effective_from)
  select compliance_id, 'statutory', 'monthly', '{"type":"day_of_month","day":25,"month_offset":1}', 'high', 'critical', true, date '2026-07-01' from public.compliance_rule_version where version=1;
select test.eq('second version numbered 2 (draft)', (select version || ':' || status from public.compliance_rule_version where version=2), '2:draft');
update public.compliance_rule_version set due_rule='{"type":"day_of_month","day":26,"month_offset":1}' where version=2;
select test.eq('draft is freely editable', (select due_rule ->> 'day' from public.compliance_rule_version where version=2), '26');
select public.compliance_activate_rule_version((select id from public.compliance_rule_version where version=2), 'policy change from July');
select test.eq('v1 retired automatically', (select status from public.compliance_rule_version where version=1), 'retired');
select test.eq('v1 effective_to = day before v2', (select effective_to from public.compliance_rule_version where version=1), date '2026-06-30');
select test.eq('v1 content preserved', (select due_rule ->> 'day' from public.compliance_rule_version where version=1), '20');
select test.denied('retired version cannot be reactivated', $$update public.compliance_rule_version set status='active' where version=1$$);
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, effective_from)
  select compliance_id, 'statutory', 'monthly', '{"type":"day_of_month","day":10,"month_offset":1}', 'low', date '2026-03-01' from public.compliance_rule_version where version=1;
select test.eq('third draft numbered 3', (select max(version) from public.compliance_rule_version), 3);
select test.denied('cannot activate a version that starts before the live one', $$select public.compliance_activate_rule_version((select id from public.compliance_rule_version where version=3), 'backdated')$$);
select test.denied('direct status flip cannot create a second active version', $$update public.compliance_rule_version set status='active' where version=3$$);
select test.denied('activated version cannot return to draft', $$update public.compliance_rule_version set status='draft' where version=2$$);
select test.logout();

select test.login('viewer@bfcl.test');
select test.denied('viewer cannot activate versions', $$select public.compliance_activate_rule_version((select id from public.compliance_rule_version where version=2), 'x')$$);
select test.eq('viewer can read masters/rules', test.count('select * from public.compliance_rule_version'), 3::bigint);
select test.logout();
select test.login('headhr@bfcl.test');
insert into public.compliance_master(code,name) values ('CM-2','By head HR');
select test.eq('head hr (compliance.manage) can create masters', test.count($$select 1 from public.compliance_master where code='CM-2'$$), 1::bigint);
select test.logout();

select test.eq('master/version changes audited', (select count(*) from public.audit_log where table_name in ('compliance_master','compliance_rule_version')) >= 6, true);
\echo ALL COMPLIANCE MASTER TESTS PASSED
