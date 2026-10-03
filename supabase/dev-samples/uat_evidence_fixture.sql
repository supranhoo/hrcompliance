-- EVIDENCE-STATE FIXTURE (DEVELOPMENT ONLY, synthetic). Run after uat_engine_demo.sql, as postgres, in the SQL editor.
-- Real evidence needs Google Drive (not connected) and takes weeks to expire, so this attaches SYNTHETIC evidence rows (file ids start with SAMPLE-DRIVE-) to four
-- SAMPLE-MONTHLY obligations so every evidence state can be seen in the UI: pending review, verified, rejected, expired - alongside the 'missing' ones the engines already show.
-- It writes through the normal tables/triggers (as the table owner, where the verification-permission check does not apply). Idempotent. Removed by remove_samples.sql.
begin;
do $g$ begin
  if coalesce((select value #>> '{}' from public.system_config where key = 'environment.name'), '') <> 'development' then
    raise exception 'REFUSED: this database is not labelled development (system_config environment.name).';
  end if;
end $g$;
-- the SAME four obligations every run (earliest due), so re-running changes nothing
create temp table _targets as
  select i.id, row_number() over (order by i.due_date, i.instance_no) rn
    from public.compliance_instance i join public.compliance_master m on m.id = i.compliance_id join public.location l on l.id = i.location_id
   where m.code = 'SAMPLE-MONTHLY' and l.code = 'SAMPLE-LOC-A' and i.status <> 'not_applicable'
   order by i.due_date, i.instance_no limit 4;
insert into public.evidence (compliance_instance_id, document_type_id, storage_file_id, file_name, mime_type, size_bytes, expiry_date)
select t.id, d.id, 'SAMPLE-DRIVE-' || t.rn, 'SAMPLE_document_' || t.rn || '.pdf', 'application/pdf', 100000 + t.rn, case when t.rn = 4 then current_date - 5 end
  from _targets t, public.document_type d where d.code = 'SAMPLE-DOC'
   and not exists (select 1 from public.evidence e where e.compliance_instance_id = t.id and e.document_type_id = d.id and e.is_current);
update public.evidence e set verification_status = 'verified', verification_remarks = 'SAMPLE: checked' from _targets t where e.compliance_instance_id = t.id and t.rn in (2, 4);
update public.evidence e set verification_status = 'rejected', verification_remarks = 'SAMPLE: scan unreadable' from _targets t where e.compliance_instance_id = t.id and t.rn = 3;
select app.detect_exceptions() as exceptions_after_fixture;
commit;
select evidence_state, count(*) as requirements from public.v_evidence_requirement group by 1 order by 1;
