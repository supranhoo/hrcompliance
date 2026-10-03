-- Removes ONLY the synthetic sample rows (codes starting with SAMPLE). Run as postgres. Audit history is retained by design.
begin;
-- published rule evidence is immutable for every normal path; this owner-only dev cleanup lifts that guard inside this transaction only
alter table public.compliance_rule_evidence disable trigger rule_evidence_guard;
delete from public.notification where link_id in (select id from public.compliance_instance where compliance_id in (select id from public.compliance_master where code like 'SAMPLE%'))
   or link_id in (select id from public.licence where licence_number like 'SAMPLE%');
delete from public.exception_action where exception_id in (select id from public.exception where entity_id in (select id from public.entity where code like 'SAMPLE%'));
delete from public.exception where entity_id in (select id from public.entity where code like 'SAMPLE%');
delete from public.evidence where entity_id in (select id from public.entity where code like 'SAMPLE%');
delete from public.compliance_instance where compliance_id in (select id from public.compliance_master where code like 'SAMPLE%');
delete from public.compliance_applicability where compliance_id in (select id from public.compliance_master where code like 'SAMPLE%');
delete from public.compliance_rule_evidence where rule_version_id in (select id from public.compliance_rule_version where compliance_id in (select id from public.compliance_master where code like 'SAMPLE%'));
delete from public.compliance_rule_version where compliance_id in (select id from public.compliance_master where code like 'SAMPLE%');
delete from public.compliance_master where code like 'SAMPLE%';
delete from public.compliance_category where code like 'SAMPLE%';
delete from public.licence_event where licence_id in (select id from public.licence where licence_number like 'SAMPLE%');
delete from public.licence where licence_number like 'SAMPLE%';
delete from public.licence_type where code like 'SAMPLE%';
delete from public.document_type where code like 'SAMPLE%';
delete from public.location where code like 'SAMPLE%';
delete from public.entity where code like 'SAMPLE%';
alter table public.compliance_rule_evidence enable trigger rule_evidence_guard;
commit;
