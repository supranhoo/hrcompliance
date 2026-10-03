-- Evidence requirement configuration: default validity, verification requirement, immutable published requirements, document type format checks. Rolled back.
\set ON_ERROR_STOP on
begin;
insert into public.document_type (code, name, allowed_mime_types, max_size_mb) values ('EC-CERT','Cert','{application/pdf}',5), ('EC-NOVER','No verification','{application/pdf}',5);
insert into public.compliance_master (code, name) values ('EC-1', 'Evidence config sample');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, evidence_required, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'medium', true, date '2020-01-01' from public.compliance_master where code='EC-1';
insert into public.compliance_rule_evidence (rule_version_id, document_type_id, is_mandatory, validity_months, requires_verification, help_text)
  select v.id, d.id, true, case d.code when 'EC-CERT' then 12 end, d.code <> 'EC-NOVER', 'Upload the signed copy' from public.compliance_rule_version v, public.document_type d where d.code in ('EC-CERT','EC-NOVER') and v.compliance_id=(select id from public.compliance_master where code='EC-1');
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='EC-1');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) select (select id from public.compliance_master where code='EC-1'), id, 'applicable', 'x', date '2020-01-01' from public.location where code='L-E1';
update public.compliance_master set is_active = (code='EC-1');
select app.generate_compliance_instances(date_trunc('month', current_date)::date, current_date + 40);
create temp table _i as select id from public.compliance_instance where compliance_id=(select id from public.compliance_master where code='EC-1') order by period_start limit 1; grant select on _i to authenticated;

insert into public.evidence (compliance_instance_id, document_type_id, storage_file_id, file_name, mime_type, size_bytes)
  select (select id from _i), id, 'f-cert', 'c.pdf', 'application/pdf', 100 from public.document_type where code='EC-CERT';
insert into public.evidence (compliance_instance_id, document_type_id, storage_file_id, file_name, mime_type, size_bytes)
  select (select id from _i), id, 'f-nover', 'n.pdf', 'application/pdf', 100 from public.document_type where code='EC-NOVER';
select test.eq('default validity is applied when no expiry is given (12 months from upload)', (select expiry_date from public.evidence where storage_file_id='f-cert'), (current_date + interval '12 months')::date);
select test.eq('and the evidence waits for review (verification required)', (select verification_status from public.evidence where storage_file_id='f-cert'), 'pending_review');
select test.eq('no validity configured -> no automatic expiry', (select expiry_date from public.evidence where storage_file_id='f-nover'), null::date);
select test.eq('verification NOT required -> recorded as verified on upload, with the reason', (select verification_status || ':' || (verified_at is not null)::text || ':' || (verified_by is null)::text from public.evidence where storage_file_id='f-nover'), 'verified:true:true');
select test.eq('the reason is explicit', (select verification_remarks from public.evidence where storage_file_id='f-nover') like 'Verification not required%', true);
-- an explicit expiry always wins
insert into public.evidence (compliance_instance_id, document_type_id, storage_file_id, file_name, mime_type, size_bytes, expiry_date, period_start)
  select (select id from _i), id, 'f-cert2', 'c2.pdf', 'application/pdf', 100, date '2030-01-01', date '1999-01-01' from public.document_type where code='EC-CERT';
select test.eq('an explicit expiry wins over the default validity', (select expiry_date from public.evidence where storage_file_id='f-cert2'), date '2030-01-01');
-- replacement keeps the chain and re-applies the configuration
select test.login('admin@bfcl.test');
create temp table _r as select public.evidence_replace((select id from public.evidence where storage_file_id='f-cert'), 'f-cert-v2', 'c_v2.pdf', 'application/pdf', 120, null, null, 'corrected scan') as id; grant select on _r to authenticated;
select test.eq('replacement is a new version with the default validity again', (select version::text || ':' || (expiry_date = (current_date + interval '12 months')::date)::text from public.evidence where id=(select id from _r)), '2:true');
select test.eq('and the old version is kept, no longer current', (select is_current from public.evidence where storage_file_id='f-cert'), false);
-- published requirements are immutable; drafts are cloned with the new settings
select test.denied('published requirement cannot be changed', $$update public.compliance_rule_evidence set validity_months = 24 where rule_version_id in (select id from public.compliance_rule_version where status='active' and compliance_id=(select id from public.compliance_master where code='EC-1'))$$);
create temp table _d as select public.compliance_rule_new_draft((select id from public.compliance_master where code='EC-1')) id; grant select on _d to authenticated;
select test.eq('a new draft clones validity / verification / help text', (select count(*) from public.compliance_rule_evidence where rule_version_id=(select id from _d) and help_text='Upload the signed copy' and ((validity_months=12) or (requires_verification = false))), 2::bigint);
update public.compliance_rule_evidence set validity_months = 24, requires_verification = false where rule_version_id=(select id from _d) and validity_months = 12;
select test.eq('the draft requirement is editable', (select validity_months from public.compliance_rule_evidence where rule_version_id=(select id from _d) and validity_months is not null), 24);
select test.denied('validity must be positive', $$update public.compliance_rule_evidence set validity_months = 0 where rule_version_id=(select id from _d)$$);
select test.denied('and bounded (50 years)', $$update public.compliance_rule_evidence set validity_months = 601 where rule_version_id=(select id from _d)$$);
select test.eq('the active version still carries the original configuration', (select validity_months from public.compliance_rule_evidence where document_type_id=(select id from public.document_type where code='EC-CERT') and rule_version_id=(select id from public.compliance_rule_version where status='active' and compliance_id=(select id from public.compliance_master where code='EC-1'))), 12);
-- document types
insert into public.document_type (code, name, allowed_mime_types, max_size_mb) values ('EC-OK','OK','{application/pdf,image/png,application/vnd.openxmlformats-officedocument.wordprocessingml.document}',10);
select test.denied('MIME types must look like MIME types', $$insert into public.document_type (code, name, allowed_mime_types) values ('EC-BAD','Bad','{pdf}')$$);
select test.denied('an empty MIME list is refused', $$insert into public.document_type (code, name, allowed_mime_types) values ('EC-BAD2','Bad','{}')$$);
select test.denied('size limit bounded', $$insert into public.document_type (code, name, max_size_mb) values ('EC-BAD3','Bad',500)$$);
select test.logout();
rollback;
\echo ALL EVIDENCE CONFIG TESTS PASSED
