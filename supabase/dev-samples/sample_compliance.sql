-- SYNTHETIC SAMPLE DATA FOR DEVELOPMENT ONLY. Not BFCL data. Not legal content. See README.md in this folder.
-- Idempotent. Run as postgres in the SQL editor of the DEVELOPMENT project.
insert into public.entity (code, name, industry) values ('SAMPLE-ENT', 'SAMPLE Entity (synthetic)', 'Sample industry') on conflict (code) do nothing;
insert into public.location (entity_id, code, name, state, establishment_type, employee_headcount, contractor_headcount)
select e.id, v.code, v.name, 'Sample State', v.est, v.emp, v.con from public.entity e join (values
  ('SAMPLE-LOC-A', 'SAMPLE Plant A', 'Factory', 120, 40), ('SAMPLE-LOC-B', 'SAMPLE Office B', 'Office', 15, 0)) v(code, name, est, emp, con) on true
where e.code = 'SAMPLE-ENT' on conflict (code) do nothing;
insert into public.document_type (code, name) values ('SAMPLE-DOC', 'SAMPLE Supporting document') on conflict (code) do nothing;
insert into public.compliance_category (code, name) values ('SAMPLE-CAT', 'SAMPLE category') on conflict (code) do nothing;

insert into public.compliance_master (code, name, description, category_id, section_reference, legal_source)
select v.code, v.name, 'Synthetic sample obligation - not a legal requirement', c.id, 'n/a (synthetic)', 'n/a (synthetic)'
from public.compliance_category c join (values ('SAMPLE-MONTHLY', 'SAMPLE monthly return'), ('SAMPLE-QUARTERLY', 'SAMPLE quarterly statement')) v(code, name) on true
where c.code = 'SAMPLE-CAT' on conflict (code) do nothing;

-- rule versions: created as drafts, evidence attached while draft, then published
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, criticality, evidence_required, effective_from)
select m.id, 'internal', v.freq, v.rule::jsonb, v.risk, v.crit, v.ev, date_trunc('year', current_date - interval '1 year')::date
from public.compliance_master m join (values
  ('SAMPLE-MONTHLY', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'high', 'critical', true),
  ('SAMPLE-QUARTERLY', 'quarterly', '{"type":"days_after_period_end","days":30}', 'medium', 'important', false)) v(code, freq, rule, risk, crit, ev) on v.code = m.code
where not exists (select 1 from public.compliance_rule_version r where r.compliance_id = m.id);
insert into public.compliance_rule_evidence (rule_version_id, document_type_id)
select r.id, d.id from public.compliance_rule_version r join public.compliance_master m on m.id = r.compliance_id, public.document_type d
where m.code = 'SAMPLE-MONTHLY' and d.code = 'SAMPLE-DOC' and r.status = 'draft' on conflict do nothing;
update public.compliance_rule_version r set status = 'active', change_reason = 'synthetic sample'
from public.compliance_master m where m.id = r.compliance_id and m.code like 'SAMPLE-%' and r.status = 'draft';

-- applicability: monthly applies to the whole entity; quarterly only where headcount >= 50 (office B is therefore not applicable)
insert into public.compliance_applicability (compliance_id, entity_id, status, reason, source_reference, effective_from)
select m.id, e.id, 'applicable', 'synthetic sample', 'n/a', date_trunc('year', current_date - interval '1 year')::date
from public.compliance_master m, public.entity e where m.code = 'SAMPLE-MONTHLY' and e.code = 'SAMPLE-ENT'
  and not exists (select 1 from public.compliance_applicability a where a.compliance_id = m.id);
insert into public.compliance_applicability (compliance_id, entity_id, status, condition, reason, effective_from)
select m.id, e.id, 'conditional', '{"op":"gte","field":"location.employee_headcount","value":50}', 'synthetic sample: 50+ employees', date_trunc('year', current_date - interval '1 year')::date
from public.compliance_master m, public.entity e where m.code = 'SAMPLE-QUARTERLY' and e.code = 'SAMPLE-ENT'
  and not exists (select 1 from public.compliance_applicability a where a.compliance_id = m.id);

-- licences: expired, expiring soon, valid
insert into public.licence_type (code, name, default_risk) values ('SAMPLE-LT', 'SAMPLE registration', 'high') on conflict (code) do nothing;
insert into public.licence (licence_type_id, entity_id, location_id, licence_number, issue_date, expiry_date, risk_level, renewal_lead_days)
select t.id, l.entity_id, l.id, v.num, current_date - 700, current_date + v.days, 'high', 45
from public.licence_type t, public.location l, (values ('SAMPLE-LIC-EXPIRED', -12), ('SAMPLE-LIC-SOON', 20), ('SAMPLE-LIC-VALID', 400)) v(num, days)
where t.code = 'SAMPLE-LT' and l.code = 'SAMPLE-LOC-A'
  and not exists (select 1 from public.licence x where x.licence_number = v.num);

-- run the engines once (the nightly jobs do this in normal operation)
select app.generate_compliance_instances(date_trunc('month', current_date - interval '3 months')::date, current_date + 60) as generated;
select app.detect_exceptions() as exceptions;
select app.generate_alerts() as alerts;
