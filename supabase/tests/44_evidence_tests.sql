-- Evidence: derived scope, file validation, immutability, versioned replacement, verification permission, derived requirement state.
\set ON_ERROR_STOP on
-- ---------- fixtures (superuser) ----------
insert into public.document_type (code, name) values ('EV-DOC', 'Evidence doc');
insert into public.document_type (code, name, max_size_mb) values ('EV-SMALL', 'Small doc', 1);
insert into public.compliance_master (code, name) values ('EV-1', 'Evidence sample monthly');
insert into public.compliance_rule_version (compliance_id, compliance_type, frequency, due_rule, risk_level, evidence_required, effective_from)
  select id, 'statutory', 'monthly', '{"type":"day_of_month","day":15,"month_offset":1}', 'high', true, date '2026-01-01' from public.compliance_master where code='EV-1';
insert into public.compliance_rule_evidence (rule_version_id, document_type_id) select v.id, d.id from public.compliance_rule_version v join public.compliance_master m on m.id=v.compliance_id, public.document_type d where m.code='EV-1' and d.code='EV-DOC';
update public.compliance_rule_version set status='active' where compliance_id=(select id from public.compliance_master where code='EV-1');
insert into public.compliance_applicability (compliance_id, location_id, status, reason, effective_from) select (select id from public.compliance_master where code='EV-1'), id, 'applicable', 'sample', date '2026-01-01' from public.location where code='L-E1';
select app.generate_compliance_instances(date '2026-09-01', date '2026-10-31');
update public.compliance_master set is_active=false where code='EV-1';   -- later generator runs ignore it; instances remain
create temp table _ev_i as select id, period_start from public.compliance_instance where compliance_id=(select id from public.compliance_master where code='EV-1') order by period_start;
create temp table _ev_dt as select code, id from public.document_type where code in ('EV-DOC','EV-SMALL');
create temp table _ev_lic as select id from public.licence where licence_number='NO-OLD';        -- Entity Two licence (cancelled; still a valid parent)
create temp table _ev_lic1 as select id from public.licence where licence_number='NO-1';          -- Entity One licence
grant select on _ev_i, _ev_dt, _ev_lic, _ev_lic1 to authenticated;
create or replace function test.inst(n int) returns uuid language sql stable as $$ select id from (select id, row_number() over (order by period_start) rn from _ev_i) x where rn = n $$;
create or replace function test.dt(c text) returns uuid language sql stable as $$ select id from _ev_dt where code = c $$;
grant execute on all functions in schema test to authenticated, anon;
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='plant@bfcl.test' and r.code='PLANT_HR' on conflict do nothing;
select test.eq('two EV-1 instances generated (Sep, Oct)', (select count(*) from _ev_i), 2::bigint);

-- ---------- requirement state before any upload ----------
select test.login('headhr@bfcl.test');
select test.eq('mandatory document starts as MISSING', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(1)), 'missing');
select test.eq('only instances whose rule requires evidence appear', (select count(distinct compliance_instance_id) from public.v_evidence_requirement), 2::bigint);
select test.logout();

-- ---------- upload (scoped, non-verifying user) ----------
select test.login('plant@bfcl.test');
insert into public.evidence (compliance_instance_id, document_type_id, storage_file_id, file_name, mime_type, size_bytes, checksum_sha256, verification_status, expiry_date)
  values (test.inst(1), test.dt('EV-DOC'), 'drive-file-001', 'challan_sep.pdf', 'application/pdf', 120000, repeat('a', 64), 'verified', null);
select test.eq('evidence numbered EVD-yyyy-nnnnnn', (select evidence_no ~ '^EVD-[0-9]{4}-[0-9]{6}$' from public.evidence), true);
select test.eq('uploader cannot self-verify on insert (forced to pending)', (select verification_status from public.evidence), 'pending_review');
select test.eq('scope derived from the parent instance', (select (e.entity_id = i.entity_id and e.location_id = i.location_id)::text from public.evidence e join public.compliance_instance i on i.id = e.compliance_instance_id), 'true');
select test.eq('period defaulted from the instance', (select period_start from public.evidence), (select period_start from _ev_i order by period_start limit 1));
select test.eq('version 1 and current', (select version || ':' || is_current from public.evidence), '1:true');
select test.eq('uploader recorded', (select uploaded_by is not null from public.evidence), true);
select test.eq('requirement now pending_review', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(1)), 'pending_review');
-- validation
select test.denied('disallowed MIME type', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (test.inst(2), test.dt('EV-DOC'),'f2','a.exe','application/x-msdownload',100)$$);
select test.denied('file larger than the document type limit', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (test.inst(2), test.dt('EV-SMALL'),'f3','big.pdf','application/pdf',2097152)$$);
select test.denied('zero-byte file', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (test.inst(2), test.dt('EV-DOC'),'f4','e.pdf','application/pdf',0)$$);
select test.denied('empty storage id', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (test.inst(2), test.dt('EV-DOC'),'  ','e.pdf','application/pdf',10)$$);
select test.denied('bad checksum format', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes,checksum_sha256) values (test.inst(2), test.dt('EV-DOC'),'f5','e.pdf','application/pdf',10,'zzz')$$);
select test.denied('no parent (clear message)', $$insert into public.evidence(document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (test.dt('EV-DOC'),'f6','e.pdf','application/pdf',10)$$);
select test.denied('two parents', $$insert into public.evidence(compliance_instance_id,licence_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) select test.inst(2),(select id from _ev_lic1),test.dt('EV-DOC'),'f7','e.pdf','application/pdf',10$$);
select test.denied('unknown parent', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (gen_random_uuid(), test.dt('EV-DOC'),'f8','e.pdf','application/pdf',10)$$);
select test.denied('second CURRENT upload for same parent/type/period is refused (must replace)', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (test.inst(1), test.dt('EV-DOC'),'drive-file-dup','dup.pdf','application/pdf',100)$$);
select test.denied('cannot forge a version chain on insert', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes,supersedes_id,replace_reason) select test.inst(2), test.dt('EV-DOC'),'f9','e.pdf','application/pdf',10,id,'x' from public.evidence$$);
select test.denied('cannot attach evidence to another entity''s licence (scope derived from parent)', $$insert into public.evidence(licence_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) select id, test.dt('EV-DOC'),'f10','e.pdf','application/pdf',10 from _ev_lic$$);
insert into public.evidence(licence_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes,expiry_date) select id, test.dt('EV-DOC'),'drive-lic-1','licence_copy.pdf','application/pdf',5000, current_date + 200 from _ev_lic1;
select test.eq('evidence can attach to a licence in scope', test.count($$select 1 from public.evidence where licence_id is not null$$), 1::bigint);
-- verification permission
select test.denied('uploader without evidence.verify cannot verify', $$update public.evidence set verification_status='verified' where compliance_instance_id = test.inst(1)$$);
-- immutability
select test.denied('file id immutable', $$update public.evidence set storage_file_id='swapped' where compliance_instance_id = test.inst(1)$$);
select test.denied('file name immutable', $$update public.evidence set file_name='other.pdf' where compliance_instance_id = test.inst(1)$$);
select test.denied('checksum immutable', $$update public.evidence set checksum_sha256=repeat('b',64) where compliance_instance_id = test.inst(1)$$);
select test.denied('cannot flip is_current directly', $$update public.evidence set is_current=false where compliance_instance_id = test.inst(1)$$);
select test.denied('no delete privilege', 'delete from public.evidence');
select test.logout();

-- ---------- verification by an authorised user ----------
select test.login('headhr@bfcl.test');
update public.evidence set verification_status='verified', verification_remarks='matches challan' where compliance_instance_id = test.inst(1);
select test.eq('verified stamps verifier and time', (select (verified_by is not null and verified_at is not null)::text from public.evidence where compliance_instance_id = test.inst(1)), 'true');
select test.eq('requirement now verified', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(1)), 'verified');
select test.denied('rejection needs remarks', $$update public.evidence set verification_status='rejected', verification_remarks=null where compliance_instance_id = test.inst(1)$$);
update public.evidence set verification_status='rejected', verification_remarks='unreadable scan' where compliance_instance_id = test.inst(1);
select test.eq('requirement shows rejected', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(1)), 'rejected');
update public.evidence set verification_status='verified', verification_remarks='re-checked' where compliance_instance_id = test.inst(1);
select test.logout();

-- ---------- replacement keeps history ----------
select test.login('plant@bfcl.test');
select test.denied('replace needs a reason', $$select public.evidence_replace((select id from public.evidence where compliance_instance_id = test.inst(1)), 'drive-file-002','challan_sep_v2.pdf','application/pdf',130000,null,null,'  ')$$);
select test.denied('replace validates file type', $$select public.evidence_replace((select id from public.evidence where compliance_instance_id = test.inst(1)), 'drive-file-x','x.exe','application/x-msdownload',10,null,null,'wrong file')$$);
select public.evidence_replace((select id from public.evidence where compliance_instance_id = test.inst(1)), 'drive-file-002','challan_sep_v2.pdf','application/pdf',130000,repeat('c',64),null,'clearer scan uploaded');
select test.eq('two versions retained', (select count(*) from public.evidence where compliance_instance_id = test.inst(1)), 2::bigint);
select test.eq('exactly one current', (select count(*) from public.evidence where compliance_instance_id = test.inst(1) and is_current), 1::bigint);
select test.eq('new version is v2 and supersedes v1', (select e.version || ':' || (e.supersedes_id = o.id)::text from public.evidence e join public.evidence o on o.id = e.supersedes_id where e.is_current and e.compliance_instance_id = test.inst(1)), '2:true');
select test.eq('previous file reference preserved', (select storage_file_id from public.evidence where version = 1 and compliance_instance_id = test.inst(1)), 'drive-file-001');
select test.eq('replace reason stored', (select replace_reason from public.evidence where version = 2), 'clearer scan uploaded');
select test.eq('replacement starts as pending_review (not inherited)', (select verification_status from public.evidence where version = 2), 'pending_review');
select test.eq('requirement reflects the new current version', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(1)), 'pending_review');
select test.denied('only the current version can be replaced', $$select public.evidence_replace((select id from public.evidence where version = 1 and compliance_instance_id = test.inst(1)), 'f','a.pdf','application/pdf',10,null,null,'again')$$);
select test.logout();

-- ---------- expiry (derived) ----------
select test.login('headhr@bfcl.test');
update public.evidence set verification_status='verified', expiry_date = current_date - 1 where is_current and compliance_instance_id = test.inst(1);
select test.eq('past expiry date -> expired', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(1)), 'expired');
update public.evidence set expiry_date = current_date + 30 where is_current and compliance_instance_id = test.inst(1);
select test.eq('future expiry -> verified', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(1)), 'verified');
select test.eq('second instance still MISSING', (select evidence_state from public.v_evidence_requirement where compliance_instance_id = test.inst(2)), 'missing');
select test.logout();

-- ---------- scope / access ----------
insert into public.evidence(licence_id,entity_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) select id, (select id from public.entity where code='E2'), (select id from _ev_dt where code='EV-DOC'),'drive-e2','e2.pdf','application/pdf',10 from _ev_lic;
select test.login('plant@bfcl.test');
select test.eq('scoped user does not see other-entity evidence', test.count($$select 1 from public.evidence where storage_file_id='drive-e2'$$), 0::bigint);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('viewer without scope sees no evidence', test.count('select * from public.evidence'), 0::bigint);
select test.denied('viewer cannot add evidence', $$insert into public.evidence(compliance_instance_id,document_type_id,storage_file_id,file_name,mime_type,size_bytes) values (test.inst(2), test.dt('EV-DOC'),'fv','a.pdf','application/pdf',10)$$);
select test.denied('viewer cannot replace evidence', $$select public.evidence_replace((select id from public.evidence limit 1),'f','a.pdf','application/pdf',10,null,null,'x')$$);
select test.logout();
select test.login('stranger@gmail.com');
select test.eq('unprovisioned sees no evidence', test.count('select * from public.evidence'), 0::bigint);
select test.eq('unprovisioned sees no requirement rows', test.count('select * from public.v_evidence_requirement'), 0::bigint);
select test.logout();
select test.eq('evidence activity audited (inserts + verification + retire)', (select count(*) from public.audit_log where table_name='evidence') >= 8, true);
\echo ALL EVIDENCE TESTS PASSED
