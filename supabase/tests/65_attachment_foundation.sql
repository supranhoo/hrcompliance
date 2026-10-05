-- Generic attachment foundation (migration 0040): parent-derived authorisation that fails closed, pending isolation, immutable versions, private storage policies. Rolled back.
\set ON_ERROR_STOP on
begin;
-- fixtures (superuser): a test document type, a test parent type registered in the attachment registry, and per-user access rows for the test parent
insert into public.document_type (code, name, allowed_mime_types, max_size_mb) values ('ATT-T', 'Attachment test', array['application/pdf','image/png'], 1);
create table public.test_att_parent (id uuid primary key default gen_random_uuid());
create table public.test_att_access (parent_id uuid, user_id uuid, actions text[]);
create function app.test_att_access(p_id uuid, p_action text) returns boolean language sql stable security definer set search_path = public as
  $$ select exists (select 1 from public.test_att_access t where t.parent_id = p_id and t.user_id = app.current_user_id() and p_action = any (t.actions)) $$;
create function app.test_att_boom(p_id uuid, p_action text) returns boolean language plpgsql as $$ begin raise exception 'boom'; end $$;
insert into public.attachment_target (parent_type, module, parent_table, read_permission, write_permission, access_function) values ('test_parent', 'admin', 'public.test_att_parent', 'compliance.read', 'master.write', 'app.test_att_access');
insert into public.test_att_parent (id) values ('00000000-0000-4000-8000-0000000000a1');
insert into public.test_att_access select '00000000-0000-4000-8000-0000000000a1', id, array['read','write','restricted_read'] from public.app_user where email = 'headhr@bfcl.test';
insert into public.test_att_access select '00000000-0000-4000-8000-0000000000a1', id, array['read'] from public.app_user where email = 'plant@bfcl.test';
select id as doc from public.document_type where code = 'ATT-T' \gset
\set sha aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
\set par 00000000-0000-4000-8000-0000000000a1

-- registry validation: only real tables/functions can be registered
select test.denied('registry refuses a parent table that does not exist', $$insert into public.attachment_target values ('bad_t','admin','public.no_such_table','compliance.read','master.write','app.test_att_access')$$);
select test.denied('registry refuses an access function that does not exist', $$insert into public.attachment_target (parent_type, module, parent_table, read_permission, write_permission, access_function) values ('bad_f','admin','public.test_att_parent','compliance.read','master.write','app.no_such_fn')$$);

-- anonymous: no access of any kind
set role anon;
select test.denied('anon cannot read attachments', $$select count(*) from public.attachment$$);
select test.denied('anon cannot read versions', $$select count(*) from public.attachment_version$$);
select test.denied('anon cannot read the listing view', $$select count(*) from public.v_attachment$$);
select test.denied('anon cannot begin an upload', format($$select * from public.attachment_begin_upload(%L, 'a.pdf', 'application/pdf', 1000, %L)$$, :'doc', :'sha'));
select test.denied('anon cannot read the registry', $$select count(*) from public.attachment_target$$);
reset role;

-- uploader reserves an attachment (PENDING) and receives a database-minted key
select test.login('headhr@bfcl.test');
select attachment_id as a1, version_id as v1, storage_key as k1 from public.attachment_begin_upload(:'doc', 'report.pdf', 'application/pdf', 1000, :'sha') \gset
select test.eq('the key is minted by the database as <version id>/<random>', (:'k1' like (:'v1' || '/%')), true);
select test.eq('the key does not contain the file name', position('report' in :'k1'), 0);
select test.denied('storage_key / bucket are not readable through the API (no object enumeration)', $$select storage_key from public.attachment_version$$);
select test.eq('uploader sees own pending attachment in the listing', (select count(*) from public.v_attachment where id = :'a1'), 1::bigint);
select test.eq('listing exposes checksum as declared', (select checksum_sha256 from public.v_attachment where id = :'a1'), repeat('a', 64));
select test.denied('direct insert into attachment is refused', format($$insert into public.attachment(document_type_id, owner_user_id) values (%L, app.current_user_id())$$, :'doc'));
select test.denied('direct update of a version is refused', $$update public.attachment_version set file_name = 'x'$$);
select test.logout();

-- another user cannot see, download, upload to, or read the pending attachment
select test.login('plant@bfcl.test');
select test.eq('another user does not see someone else''s pending attachment', (select count(*) from public.v_attachment where id = :'a1'), 0::bigint);
select test.eq('...nor its version rows', (select count(*) from public.attachment_version where attachment_id = :'a1'), 0::bigint);
select test.denied('...cannot authorise a download by UUID', format($$select * from public.attachment_authorize_download(%L)$$, :'v1'));
select test.denied('...cannot upload to the reserved key', format($$insert into storage.objects(bucket_id, name, metadata) values ('attachments', %L, '{"size":1000,"mimetype":"application/pdf"}')$$, :'k1'));
select test.denied('...cannot complete someone else''s upload', format($$select public.attachment_complete_upload(%L)$$, :'v1'));
select test.logout();

-- storage: the reserved key accepts the uploader only; random keys are refused
select test.login('headhr@bfcl.test');
select test.denied('uploader cannot upload to a key that was never reserved', $$insert into storage.objects(bucket_id, name, metadata) values ('attachments', 'abc/def', '{"size":1000,"mimetype":"application/pdf"}')$$);
select test.denied('completion before the object exists is refused', format($$select public.attachment_complete_upload(%L)$$, :'v1'));
insert into storage.objects(bucket_id, name, metadata) values ('attachments', :'k1', '{"size":1000,"mimetype":"application/pdf"}');
select public.attachment_complete_upload(:'v1');
select test.eq('completion makes the version available and current', (select is_current and upload_status = 'AVAILABLE' from public.attachment_version where id = :'v1'), true);
select public.attachment_complete_upload(:'v1');
select test.eq('completion is idempotent (second call changes nothing)', (select count(*) from public.attachment_version where attachment_id = :'a1' and is_current and upload_status = 'AVAILABLE'), 1::bigint);
select test.logout();

-- size/type declaration is verified against the stored object
select test.login('headhr@bfcl.test');
select attachment_id as a2, version_id as v2, storage_key as k2 from public.attachment_begin_upload(:'doc', 'x.pdf', 'application/pdf', 1000, :'sha') \gset
insert into storage.objects(bucket_id, name, metadata) values ('attachments', :'k2', '{"size":5,"mimetype":"application/pdf"}');
select test.denied('stored size must match the declared size', format($$select public.attachment_complete_upload(%L)$$, :'v2'));
select attachment_id as a2b, version_id as v2b, storage_key as k2b from public.attachment_begin_upload(:'doc', 'y.pdf', 'application/pdf', 1000, :'sha') \gset
insert into storage.objects(bucket_id, name, metadata) values ('attachments', :'k2b', '{"size":1000,"mimetype":"image/png"}');
select test.denied('stored content type must match the declared type', format($$select public.attachment_complete_upload(%L)$$, :'v2b'));
select test.logout();

-- pending visibility: uploader and attachment.admin only; storage follows
select test.login('plant@bfcl.test');
select test.eq('storage hides a pending object from other users', (select count(*) from storage.objects where name = :'k1'), 0::bigint);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('storage shows the pending object to its uploader', (select count(*) from storage.objects where name = :'k1'), 1::bigint);
select test.logout();
select test.login('admin@bfcl.test');
select test.eq('attachment.admin can see a pending attachment', (select count(*) from public.v_attachment where id = :'a1'), 1::bigint);
select test.eq('...and read its object', (select count(*) from storage.objects where name = :'k1'), 1::bigint);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('an unrelated user sees nothing pending', (select count(*) from public.v_attachment), 0::bigint);
select test.logout();

-- linking: registered parent + write access + existing parent
select test.login('plant@bfcl.test');
select test.denied('a non-owner cannot link', format($$select public.attachment_link(%L, 'test_parent', %L)$$, :'a1', :'par'));
select test.logout();
select test.login('headhr@bfcl.test');
select test.denied('unsupported parent type is rejected', format($$select public.attachment_link(%L, 'no_such_type', %L)$$, :'a1', :'par'));
select test.denied('a registered type with a missing parent object is rejected', format($$select public.attachment_link(%L, 'test_parent', '00000000-0000-4000-8000-00000000ffff')$$, :'a1'));
select test.denied('a pending attachment cannot be linked before the upload completes', format($$select public.attachment_link(%L, 'test_parent', %L)$$, :'a2b', :'par'));
select public.attachment_link(:'a1', 'test_parent', :'par');
select test.eq('linked', (select link_status from public.v_attachment where id = :'a1'), 'LINKED');
select test.denied('a linked attachment cannot be linked again (no re-parenting)', format($$select public.attachment_link(%L, 'test_parent', %L)$$, :'a1', :'par'));
select test.logout();
select test.login('plant@bfcl.test');
select test.eq('a user with parent READ access sees the linked attachment', (select count(*) from public.v_attachment where id = :'a1'), 1::bigint);
select test.eq('...and may read the object (standard confidentiality)', (select count(*) from storage.objects where name = :'k1'), 1::bigint);
select test.logout();
select test.login('viewer@bfcl.test');
select test.eq('a user without parent access sees nothing', (select count(*) from public.v_attachment where id = :'a1'), 0::bigint);
select test.eq('...nor the object', (select count(*) from storage.objects where name = :'k1'), 0::bigint);
select test.denied('...nor authorise a download', format($$select * from public.attachment_authorize_download(%L)$$, :'v1'));
select test.logout();
select test.login('admin@bfcl.test');
select test.eq('attachment.admin does NOT bypass parent authorisation for linked attachments', (select count(*) from public.v_attachment where id = :'a1'), 0::bigint);
select test.logout();

-- fail-closed registry: disabled type, erroring parent function, missing permission
update public.attachment_target set is_enabled = false where parent_type = 'test_parent';
select test.login('plant@bfcl.test');
select test.eq('a disabled parent type denies access', (select count(*) from public.v_attachment where id = :'a1'), 0::bigint);
select test.logout();
update public.attachment_target set is_enabled = true, access_function = 'app.test_att_boom' where parent_type = 'test_parent';
select test.login('plant@bfcl.test');
select test.eq('an erroring parent function denies access', (select count(*) from public.v_attachment where id = :'a1'), 0::bigint);
select test.logout();
update public.attachment_target set access_function = 'app.test_att_access' where parent_type = 'test_parent';
select test.login('plant@bfcl.test');
select test.eq('access returns once the registry is healthy again', (select count(*) from public.v_attachment where id = :'a1'), 1::bigint);
select test.logout();
set session_replication_role = default;
select set_config('app.attachment_rpc', 'on', false);
select test.denied('database refuses a link to an unregistered parent type even for a writer of the table', format($$insert into public.attachment(link_status, parent_type, parent_id, linked_at, document_type_id, owner_user_id) select 'LINKED', 'zzz', %L, now(), %L, id from public.app_user limit 1$$, :'par', :'doc'));
select test.denied('database refuses a link to a non-existent parent object', format($$insert into public.attachment(link_status, parent_type, parent_id, linked_at, document_type_id, owner_user_id) select 'LINKED', 'test_parent', '00000000-0000-4000-8000-00000000ffff', now(), %L, id from public.app_user limit 1$$, :'doc'));
select test.denied('a linked attachment cannot be re-parented by any writer', format($$update public.attachment set parent_id = '00000000-0000-4000-8000-00000000ffff' where id = %L$$, :'a1'));
select set_config('app.attachment_rpc', 'off', false);

-- confidential / restricted
select test.login('headhr@bfcl.test');
select attachment_id as a3, version_id as v3, storage_key as k3 from public.attachment_begin_upload(:'doc', 'c.pdf', 'application/pdf', 1000, :'sha', 'confidential') \gset
insert into storage.objects(bucket_id, name, metadata) values ('attachments', :'k3', '{"size":1000,"mimetype":"application/pdf"}');
select public.attachment_complete_upload(:'v3'); select public.attachment_link(:'a3', 'test_parent', :'par');
select attachment_id as a4, version_id as v4, storage_key as k4 from public.attachment_begin_upload(:'doc', 'r.pdf', 'application/pdf', 1000, :'sha', 'restricted') \gset
insert into storage.objects(bucket_id, name, metadata) values ('attachments', :'k4', '{"size":1000,"mimetype":"application/pdf"}');
select public.attachment_complete_upload(:'v4'); select public.attachment_link(:'a4', 'test_parent', :'par');
select test.logout();
select test.login('plant@bfcl.test');
select test.eq('confidential metadata is visible to parent readers', (select count(*) from public.v_attachment where id = :'a3'), 1::bigint);
select test.eq('confidential object cannot be read directly without a logged authorisation', (select count(*) from storage.objects where name = :'k3'), 0::bigint);
select * from public.attachment_authorize_download(:'v3');
select test.eq('authorisation wrote an access-log row', (select count(*) from public.attachment_access_log where version_id = :'v3'), 1::bigint);
select test.eq('after authorisation the object is readable', (select count(*) from storage.objects where name = :'k3'), 1::bigint);
select test.eq('restricted attachment is invisible without restricted_read on the parent', (select count(*) from public.v_attachment where id = :'a4'), 0::bigint);
select test.denied('...and cannot be authorised', format($$select * from public.attachment_authorize_download(%L)$$, :'v4'));
select test.denied('access-log rows cannot be edited', $$update public.attachment_access_log set action = 'download'$$);
select test.denied('access-log rows cannot be deleted', $$delete from public.attachment_access_log$$);
select test.logout();
select test.login('headhr@bfcl.test');
select test.eq('restricted attachment is visible with restricted_read', (select count(*) from public.v_attachment where id = :'a4'), 1::bigint);
select * from public.attachment_authorize_download(:'v4');
select test.eq('restricted read is logged', (select count(*) from public.attachment_access_log where version_id = :'v4'), 1::bigint);
select test.denied('confidentiality cannot be lowered without attachment.admin', format($$select public.attachment_set_confidentiality(%L, 'standard', 'why')$$, :'a4'));
select public.attachment_set_confidentiality(:'a1', 'confidential', 'contains personal data');
select test.eq('confidentiality can be raised with a reason', (select confidentiality from public.v_attachment where id = :'a1'), 'confidential');
select test.denied('a reason is required', format($$select public.attachment_set_confidentiality(%L, 'restricted', '')$$, :'a1'));
select test.logout();

-- versions and supersession
select test.login('plant@bfcl.test');
select test.denied('a read-only user cannot add a version', format($$select * from public.attachment_new_version(%L, 'v2.pdf', 'application/pdf', 2000, %L, 'fix')$$, :'a1', :'sha'));
select test.logout();
select test.login('headhr@bfcl.test');
select test.denied('a new version needs a reason', format($$select * from public.attachment_new_version(%L, 'v2.pdf', 'application/pdf', 2000, %L, '  ')$$, :'a1', :'sha'));
select version_id as v1b, storage_key as k1b from public.attachment_new_version(:'a1', 'v2.pdf', 'application/pdf', 2000, :'sha', 'corrected scan') \gset
select test.denied('only one reserved upload per attachment at a time', format($$select * from public.attachment_new_version(%L, 'v3.pdf', 'application/pdf', 2000, %L, 'again')$$, :'a1', :'sha'));
insert into storage.objects(bucket_id, name, metadata) values ('attachments', :'k1b', '{"size":2000,"mimetype":"application/pdf"}');
select public.attachment_complete_upload(:'v1b');
select test.eq('new version is current and numbered 2', (select version_no from public.v_attachment where id = :'a1'), 2);
select test.eq('previous version is superseded and no longer current', (select not is_current and superseded_by = :'v1b'::uuid from public.attachment_version where id = :'v1'), true);
select test.eq('exactly one current version', (select count(*) from public.attachment_version where attachment_id = :'a1' and is_current), 1::bigint);
select test.eq('replace reason is kept on the new version', (select replace_reason from public.attachment_version where id = :'v1b'), 'corrected scan');
select test.eq('history stays readable: the old version can still be authorised', (select count(*) from public.attachment_authorize_download(:'v1')), 1::bigint);
select test.logout();

-- immutability (as the table owner / superuser: triggers apply to everyone)
select test.denied('version metadata cannot be rewritten without the controlled functions', $$update public.attachment_version set file_name = 'x.pdf'$$);
select test.denied('versions cannot be deleted', $$delete from public.attachment_version$$);
select test.denied('attachments cannot be deleted', $$delete from public.attachment$$);
select set_config('app.attachment_rpc', 'on', false);
select test.denied('even through the flag, file name is immutable', format($$update public.attachment_version set file_name = 'x.pdf' where id = %L$$, :'v1'));
select test.denied('...size is immutable', format($$update public.attachment_version set size_bytes = 1 where id = %L$$, :'v1'));
select test.denied('...checksum is immutable', format($$update public.attachment_version set checksum_sha256 = repeat('b', 64) where id = %L$$, :'v1'));
select test.denied('...storage key is immutable', format($$update public.attachment_version set storage_key = 'zzz/zzz' where id = %L$$, :'v1'));
select test.denied('...uploader is immutable', format($$update public.attachment_version set uploaded_by = (select id from public.app_user where email = 'viewer@bfcl.test') where id = %L$$, :'v1'));
select test.denied('a version cannot be superseded by an earlier version', format($$update public.attachment_version set superseded_by = %L where id = %L$$, :'v1', :'v1b'));
select test.denied('nor by itself', format($$update public.attachment_version set superseded_by = id where id = %L$$, :'v1b'));
select test.denied('two current versions of one attachment are impossible', format($$update public.attachment_version set is_current = true where id = %L$$, :'v1'));
select test.denied('an available version cannot return to reserved', format($$update public.attachment_version set upload_status = 'RESERVED' where id = %L$$, :'v1'));
select test.denied('attachment identity (document type) is immutable', format($$update public.attachment set document_type_id = (select id from public.document_type where code <> 'ATT-T' limit 1) where id = %L$$, :'a1'));
select set_config('app.attachment_rpc', 'off', false);
select test.eq('checksum metadata is preserved exactly as declared', (select checksum_sha256 from public.attachment_version where id = :'v1'), repeat('a', 64));

-- deactivation
select test.login('plant@bfcl.test');
select test.denied('a read-only user cannot deactivate', format($$select public.attachment_deactivate(%L, 'x')$$, :'a3'));
select test.logout();
select test.login('headhr@bfcl.test');
select test.denied('deactivation needs a reason', format($$select public.attachment_deactivate(%L, ' ')$$, :'a3'));
select public.attachment_deactivate(:'a3', 'uploaded in error');
select test.eq('writers still see an inactive attachment', (select count(*) from public.v_attachment where id = :'a3' and not is_active), 1::bigint);
select test.logout();
select test.login('plant@bfcl.test');
select test.eq('readers no longer see an inactive attachment', (select count(*) from public.v_attachment where id = :'a3'), 0::bigint);
select test.logout();

-- storage cannot be bypassed or enumerated
select test.login('plant@bfcl.test');
select test.eq('listing the bucket shows only readable objects (no enumeration of others)', (select count(*) from storage.objects where bucket_id = 'attachments' and name like '%/%' and name <> all (array[:'k1', :'k1b'])), 0::bigint);
select test.denied('a guessed key cannot be written', $$insert into storage.objects(bucket_id, name, metadata) values ('attachments', '00000000-0000-4000-8000-000000000001/00000000-0000-4000-8000-000000000002', '{"size":1,"mimetype":"application/pdf"}')$$);
select test.logout();
select test.login('headhr@bfcl.test');
update storage.objects set metadata = '{"size":1,"mimetype":"application/pdf"}' where name = :'k1';
select test.eq('stored objects cannot be overwritten through the API (no update policy)', (select (metadata ->> 'size')::int from storage.objects where name = :'k1'), 1000);
delete from storage.objects where name = :'k1';
select test.eq('stored objects cannot be deleted through the API (no delete policy)', (select count(*) from storage.objects where name = :'k1'), 1::bigint);
select test.logout();
select test.eq('the bucket is private', (select not public from storage.buckets where id = 'attachments'), true);
select test.eq('no storage policy for the attachments bucket applies to anon/public', (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'attachments_obj_%' and (roles && array['anon'::name, 'public'::name])), 0::bigint);
select test.eq('storage policies exist only for insert and select', (select string_agg(cmd, ',' order by cmd) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'attachments_obj_%'), 'INSERT,SELECT');

-- upload declaration validation (type, size, name, checksum, document type)
select test.login('headhr@bfcl.test');
select test.denied('content type not allowed for the document type', format($$select * from public.attachment_begin_upload(%L, 'a.exe', 'application/x-msdownload', 100, %L)$$, :'doc', :'sha'));
select test.denied('size above the document-type limit', format($$select * from public.attachment_begin_upload(%L, 'a.pdf', 'application/pdf', 2000000, %L)$$, :'doc', :'sha'));
select test.denied('zero size', format($$select * from public.attachment_begin_upload(%L, 'a.pdf', 'application/pdf', 0, %L)$$, :'doc', :'sha'));
select test.denied('malformed checksum', format($$select * from public.attachment_begin_upload(%L, 'a.pdf', 'application/pdf', 100, 'XYZ')$$, :'doc'));
select test.denied('unknown document type', format($$select * from public.attachment_begin_upload(%L, 'a.pdf', 'application/pdf', 100, %L)$$, gen_random_uuid(), :'sha'));
select test.denied('a blank file name', format($$select * from public.attachment_begin_upload(%L, '   ', 'application/pdf', 100, %L)$$, :'doc', :'sha'));
select attachment_id as a5 from public.attachment_begin_upload(:'doc', E'../../etc/pass\x01wd.pdf', 'application/pdf', 100, :'sha') \gset
select test.eq('path separators and control characters never survive in the stored file name', (select file_name !~ '[/\\[:cntrl:]]' and left(file_name, 1) <> '.' from public.v_attachment where id = :'a5'), true);
select test.eq('...and the cleaned name is what the table check enforces', (select app.safe_filename(file_name) = file_name from public.v_attachment where id = :'a5'), true);
select test.logout();

-- pending quota
update public.system_config set value = '1' where key = 'attachment.max_pending_per_user';
select test.login('viewer@bfcl.test');
select test.eq('document-type listing is irrelevant here; first pending upload is allowed', (select count(*) from public.attachment_begin_upload(:'doc', 'q1.pdf', 'application/pdf', 100, :'sha')), 1::bigint);
select test.denied('pending quota is enforced', format($$select * from public.attachment_begin_upload(%L, 'q2.pdf', 'application/pdf', 100, %L)$$, :'doc', :'sha'));
select test.logout();

-- audit and grants
select test.eq('attachment and version changes are audited', (select count(distinct table_name) from public.audit_log where table_name in ('attachment', 'attachment_version')), 2::bigint);
select test.eq('no attachment function is executable by anon', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'attachment_%' and has_function_privilege('anon', p.oid, 'execute')), 0::bigint);
select test.eq('the app-schema authorisation functions are not executable by anon', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname in ('attachment_parent_access', 'attachment_access', 'attachment_object_ok') and has_function_privilege('anon', p.oid, 'execute')), 0::bigint);
rollback;
\echo ALL ATTACHMENT FOUNDATION TESTS PASSED
