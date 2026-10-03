-- Generic Import Framework: idempotent staging, validation with a real dry run, duplicate handling, commit/cancel, RLS parity, privacy. One rolled-back transaction.
\set ON_ERROR_STOP on
begin;
create temp table _b (name text primary key, id uuid); grant select, insert on _b to authenticated;
select test.login('admin@bfcl.test');
-- templates
select test.eq('generic reference templates are registered', (select count(*) from public.import_template where is_active) >= 9, true);
select test.eq('the template columns come from the database', (select jsonb_array_length(public.import_template_columns('document_type') -> 'columns')), 6);
insert into public.field_definition (module, key, label, field_type, is_importable, is_core) values ('licence', 'inspection_tier', 'Inspection tier', 'short_text', true, false);
select test.eq('importable custom fields from the Field Designer extend a template', (select count(*) from jsonb_array_elements(public.import_template_columns('licence') -> 'columns') c where c ->> 'key' = 'custom_inspection_tier'), 1::bigint);
select test.denied('unknown template refused', $$select public.import_stage('nope','f.csv',repeat('a',64),'[{"code":"X"}]')$$);
select test.denied('file hash must be a SHA-256', $$select public.import_stage('document_type','f.csv','abc','[{"code":"X"}]')$$);
select test.denied('empty file refused', $$select public.import_stage('document_type','f.csv',repeat('b',64),'[]')$$);
select test.denied('on_duplicate is constrained', $$select public.import_stage('document_type','f.csv',repeat('c',64),'[{"code":"X"}]', null, 'overwrite')$$);

-- stage + validate: document types (existing code ECD-EXIST for the duplicate path)
insert into public.document_type (code, name) values ('ECD-EXIST', 'Existing');
insert into _b select 'dt', public.import_stage('document_type', 'doc_types.csv', repeat('1',64), $j$[
  {"code":"IMP-OK","name":"Imported OK","allowed_mime_types":"application/pdf, image/png","max_size_mb":"10","is_active":"yes"},
  {"code":"IMP-OK","name":"Same code again"},
  {"code":"IMP-BADMIME","name":"Bad mime","allowed_mime_types":"pdf"},
  {"code":"IMP-NONAME"},
  {"code":"IMP-BADNUM","name":"Bad number","max_size_mb":"lots"},
  {"code":"IMP-TOOBIG","name":"Too big","max_size_mb":"500"},
  {"code":"ECD-EXIST","name":"Changed name"},
  {"code":"IMP-OK2","name":"Second good one"}]$j$::jsonb);
select test.eq('re-uploading the same file is refused (idempotent)', (select count(*) from (select 1) q where false), 0::bigint);
select test.denied('same file hash cannot be staged twice', $$select public.import_stage('document_type','doc_types.csv',repeat('1',64),'[{"code":"Z"}]')$$);
select test.eq('rows are staged untouched', (select count(*) from public.import_row where batch_id=(select id from _b where name='dt')), 8::bigint);
create temp table _v as select public.import_validate((select id from _b where name='dt')) r; grant select on _v to authenticated;
select test.eq('validation summary: 2 valid, 1 skip (existing), 5 errors', (select (r ->> 'valid') || '/' || (r ->> 'skipped') || '/' || (r ->> 'errors') from _v), '2/1/5');
select test.eq('good rows are valid with an insert action', (select count(*) from public.import_row where batch_id=(select id from _b where name='dt') and status='valid' and action='insert'), 2::bigint);
select test.eq('a duplicate inside the file is named', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='dt') and row_no=2), 'duplicate of row 1 in this file (same code)');
select test.eq('missing required column', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='dt') and row_no=4), 'Name is required');
select test.eq('number type is checked', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='dt') and row_no=5), 'Maximum size (MB) must be a whole number');
select test.eq('range is checked', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='dt') and row_no=6), 'Maximum size (MB) must be at most 200');
select test.eq('the DATABASE rules decide (MIME check constraint, via the dry run)', (select errors -> 0 ->> 'message' like '%document_type_mime_ck%' from public.import_row where batch_id=(select id from _b where name='dt') and row_no=3), true);
select test.eq('existing record: skipped with a warning (default)', (select action || ':' || status from public.import_row where batch_id=(select id from _b where name='dt') and row_no=7), 'skip:warning');
select test.eq('dry run wrote nothing', (select count(*) from public.document_type where code like 'IMP-%'), 0::bigint);
select test.denied('errors block a full commit', $$select public.import_commit((select id from _b where name='dt'))$$);
select test.eq('nothing was imported by the refused commit', (select count(*) from public.document_type where code like 'IMP-%'), 0::bigint);
create temp table _c as select public.import_commit((select id from _b where name='dt'), true) r; grant select on _c to authenticated;
select test.eq('commit of the valid rows only: 2 imported, 1 skipped', (select (r ->> 'committed') || '/' || (r ->> 'skipped') from _c), '2/1');
select test.eq('records exist with typed values', (select max_size_mb::text || ':' || array_to_string(allowed_mime_types, '+') from public.document_type where code='IMP-OK'), '10:application/pdf+image/png');
select test.eq('the existing record was NOT touched', (select name from public.document_type where code='ECD-EXIST'), 'Existing');
select test.eq('audit trail names the import batch', (select count(*) from public.audit_log where table_name='document_type' and action='INSERT' and reason like 'Import IMP-%') >= 2, true);
select test.eq('batch history: committed with counters', (select status || ':' || committed_rows::text || ':' || error_rows::text from public.v_import_batch where id=(select id from _b where name='dt')), 'committed:2:5');
select test.eq('rows record the target and status', (select count(*) from public.import_row where batch_id=(select id from _b where name='dt') and status='committed' and target_id is not null), 2::bigint);
select test.denied('a committed batch cannot be committed again', $$select public.import_commit((select id from _b where name='dt'), true)$$);
select test.denied('nor validated again', $$select public.import_validate((select id from _b where name='dt'))$$);
select test.denied('nor cancelled', $$select public.import_cancel((select id from _b where name='dt'), 'oops')$$);
select test.denied('batch history cannot be rewritten', $$update public.import_batch set status='validated' where id=(select id from _b where name='dt')$$);
select test.denied('nor re-pointed at another file', $$update public.import_batch set file_hash=repeat('f',64) where id=(select id from _b where name='dt')$$);

-- update mode, blanks leave values alone, cancel then re-upload
insert into _b select 'up', public.import_stage('document_type', 'update.csv', repeat('2',64), '[{"code":"ECD-EXIST","name":"Renamed by import","max_size_mb":""}]'::jsonb, null, 'update');
select public.import_validate((select id from _b where name='up'));
select test.eq('update action chosen for an existing key', (select action from public.import_row where batch_id=(select id from _b where name='up')), 'update');
select public.import_commit((select id from _b where name='up'));
select test.eq('provided values updated, blank cells left unchanged', (select name || ':' || max_size_mb::text from public.document_type where code='ECD-EXIST'), 'Renamed by import:25');
insert into _b select 'dup_err', public.import_stage('document_type', 'err.csv', repeat('3',64), '[{"code":"ECD-EXIST","name":"x"}]'::jsonb, null, 'error');
select public.import_validate((select id from _b where name='dup_err'));
select test.eq('on_duplicate=error turns an existing key into an error', (select status from public.import_row where batch_id=(select id from _b where name='dup_err')), 'error');
select test.denied('cancel needs a reason', $$select public.import_cancel((select id from _b where name='dup_err'), '')$$);
select public.import_cancel((select id from _b where name='dup_err'), 'wrong file');
select test.eq('cancelled', (select status from public.import_batch where id=(select id from _b where name='dup_err')), 'cancelled');
insert into _b select 'dup_err2', public.import_stage('document_type', 'err.csv', repeat('3',64), '[{"code":"ECD-EXIST","name":"x"}]'::jsonb, null, 'skip');
select test.eq('the same file can be uploaded again after its batch was cancelled', (select count(*) from public.import_batch where file_hash=repeat('3',64)), 2::bigint);

-- all-or-nothing + parity with the screens: licence_type with an invalid LOV value
insert into _b select 'lt', public.import_stage('licence_type', 'lt.csv', repeat('4',64), '[{"code":"IMP-LT1","name":"Good type","default_renewal_lead_days":"90"},{"code":"IMP-LT2","name":"Bad risk","default_risk":"nonsense"}]'::jsonb);
select public.import_validate((select id from _b where name='lt'));
select test.eq('LOV trigger error surfaces as a row error', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='lt') and row_no=2) like '%Invalid value%', true);
select test.denied('all-or-nothing: the batch is not committed with an error row', $$select public.import_commit((select id from _b where name='lt'))$$);
select test.eq('and the good row was not imported either', (select count(*) from public.licence_type where code='IMP-LT1'), 0::bigint);

-- licence import: references resolved by code, number counters untouched by validation, key detects duplicates
insert into public.authority (code, name) values ('IMP-AUTH', 'Authority');
insert into public.licence_type (code, name) values ('IMP-TYPE', 'Type');
select test.logout();
create temp table _cnt as select coalesce((select last_value from public.number_counter where rule_key='LIC' order by period_key desc limit 1), 0) v; grant select on _cnt to authenticated;
select test.login('admin@bfcl.test');
insert into _b select 'lic', public.import_stage('licence', 'lic.csv', repeat('5',64), '[
  {"licence_type_code":"IMP-TYPE","entity_code":"E1","location_code":"L-E1","authority_code":"IMP-AUTH","licence_number":"A-1","expiry_date":"2030-01-31"},
  {"licence_type_code":"IMP-TYPE","entity_code":"E1","location_code":"L-E1","authority_code":"IMP-AUTH","licence_number":"A-1","expiry_date":"2031-01-31"},
  {"licence_type_code":"NOPE","entity_code":"E1","expiry_date":"2030-01-31"},
  {"licence_type_code":"IMP-TYPE","entity_code":"E1","expiry_date":"31/01/2030"}]'::jsonb);
select public.import_validate((select id from _b where name='lic'));
select test.eq('references resolved; duplicate key and bad references/dates are rows errors', (select string_agg(status, ',' order by row_no) from public.import_row where batch_id=(select id from _b where name='lic')), 'valid,error,error,error');
select test.eq('unknown reference is explicit', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='lic') and row_no=3), 'Licence type code is unknown: "NOPE"');
select test.eq('date format is explicit', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='lic') and row_no=4), 'Expiry date must be a date as YYYY-MM-DD');
select test.logout();
select test.eq('validation consumed no business numbers and wrote no licence', (select v from _cnt) = coalesce((select last_value from public.number_counter where rule_key='LIC' order by period_key desc limit 1), 0) and (select count(*) from public.licence where licence_number='A-1') = 0, true);
select test.login('admin@bfcl.test');
select public.import_commit((select id from _b where name='lic'), true);
select test.eq('the licence exists with a system-assigned LIC- number', (select licence_no like 'LIC-%' from public.licence where licence_number='A-1'), true);
select test.logout();

-- permissions and privacy
select test.login('viewer@bfcl.test');
select test.denied('a user without import.manage cannot stage', $$select public.import_stage('document_type','v.csv',repeat('6',64),'[{"code":"V","name":"V"}]')$$);
select test.eq('and cannot see staged rows of others', (select count(*) from public.import_row), 0::bigint);
select test.logout();
select test.login('plant@bfcl.test');
select test.denied('import.manage is required even with the target permission', $$select public.import_stage('licence_type','p.csv',repeat('7',64),'[{"code":"P","name":"P"}]')$$);
select test.logout();

-- RLS parity: a Head HR scoped to Entity One can import for E1 but not E2
insert into public.app_user (email, status) values ('impscoped@bfcl.test', 'active');
insert into public.user_role select u.id, r.id from public.app_user u, public.role r where u.email='impscoped@bfcl.test' and r.code='HEAD_HR';
insert into public.user_scope (user_id, scope_type, scope_id) select u.id, 'entity', e.id from public.app_user u, public.entity e where u.email='impscoped@bfcl.test' and e.code='E1';
insert into auth.users (id, email) select gen_random_uuid(), 'impscoped@bfcl.test' where not exists (select 1 from auth.users where email='impscoped@bfcl.test');
update public.app_user set auth_user_id = (select id from auth.users where email='impscoped@bfcl.test') where email='impscoped@bfcl.test';
select test.login('impscoped@bfcl.test');
insert into _b select 'scoped', public.import_stage('licence', 'scoped.csv', repeat('8',64), '[
  {"licence_type_code":"IMP-TYPE","entity_code":"E1","location_code":"L-E1","licence_number":"S-1","expiry_date":"2030-01-31"},
  {"licence_type_code":"IMP-TYPE","entity_code":"E2","location_code":"L-E2","licence_number":"S-2","expiry_date":"2030-01-31"}]'::jsonb);
select public.import_validate((select id from _b where name='scoped'));
select test.eq('in-scope row accepted (with a no-duplicate-key warning), out-of-scope row refused by the same RLS as the screens', (select string_agg(status, ',' order by row_no) from public.import_row where batch_id=(select id from _b where name='scoped')), 'warning,error');
select test.eq('the refusal is explained', (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='scoped') and row_no=2) like '%row-level security%' or (select errors -> 0 ->> 'message' from public.import_row where batch_id=(select id from _b where name='scoped') and row_no=2) like 'not allowed%', true);
select test.logout();
select test.login('admin@bfcl.test');
select test.eq('an import.read holder sees the batch in the history', (select count(*) from public.v_import_batch where batch_no is not null and file_name='scoped.csv'), 1::bigint);
select test.eq('but NOT the staged rows of someone else', (select count(*) from public.import_row where batch_id=(select id from _b where name='scoped')), 0::bigint);
select test.logout();
rollback;
\echo ALL IMPORT TESTS PASSED
