-- LIVE CHECK for migration 0040 (generic attachment foundation). READ-ONLY: one SELECT, changes nothing, safe in any environment.
-- Supabase SQL Editor: new empty tab, paste this ENTIRE file, Run once. Last line is "-- END OF FILE".
-- EXPECTED: every row PASS (INFO rows are information), last row OVERALL PASS. Also run supabase/tests/live_gate.sql FIRST (expects 40 migrations, 53 tables, 19 views, 25 permissions, 13 numbering rules, audit 0).
-- This script proves the STRUCTURE and the private-storage configuration. Isolation between users and the upload/read round trip are proven by scripts/validation/attachment-smoke-test.js (see docs/ATTACHMENTS.md).
-- "Frozen migrations 0001-0039 unchanged" is enforced by the SHA-256 hash-lock in CI (check-frozen-migrations.sh); here the migration history is checked for 40 contiguous versions.
with
tbl(t) as (values ('attachment_target'), ('attachment'), ('attachment_version'), ('attachment_access_log')),
fn(f) as (values ('attachment_begin_upload'), ('attachment_new_version'), ('attachment_complete_upload'), ('attachment_link'), ('attachment_deactivate'), ('attachment_set_confidentiality'), ('attachment_authorize_download')),
c(n, check_name, ok, info) as (values
 (1, '0040 is recorded and the history is 40 contiguous versions',
     (select count(*) = 40 and min(version) = '20261003000001' and max(version) = '20261003000040' from supabase_migrations.schema_migrations where version like '2026100300%'), null::text),
 (2, 'attachment tables exist (target, attachment, version, access log)', (select count(*) = 4 from tbl where to_regclass('public.' || t) is not null), null),
 (3, 'row level security is ENABLED and FORCED on all four',
     (select count(*) = 4 and bool_and(c.relrowsecurity and c.relforcerowsecurity) from tbl join pg_class c on c.oid = to_regclass('public.' || tbl.t)), null),
 (4, 'anon has no privilege on any attachment table, view or function',
     not exists (select 1 from information_schema.role_table_grants g where g.grantee = 'anon' and g.table_schema = 'public' and (g.table_name like 'attachment%' or g.table_name = 'v_attachment'))
     and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'attachment_%' and has_function_privilege('anon', p.oid, 'execute')), null),
 (5, 'authenticated cannot INSERT / UPDATE / DELETE / TRUNCATE any attachment table (writes only via the functions)',
     not exists (select 1 from information_schema.role_table_grants g where g.grantee = 'authenticated' and g.table_schema = 'public' and g.table_name like 'attachment%' and g.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')), null),
 (6, 'storage_key and storage_bucket are NOT readable by authenticated (no object enumeration); version_no is',
     not has_column_privilege('authenticated', 'public.attachment_version', 'storage_key', 'select') and not has_column_privilege('authenticated', 'public.attachment_version', 'storage_bucket', 'select')
     and has_column_privilege('authenticated', 'public.attachment_version', 'version_no', 'select'), null),
 (7, 'the 7 attachment functions exist, are SECURITY DEFINER with a fixed search_path, and are executable by authenticated',
     (select count(*) = 7 and bool_and(p.prosecdef and p.proconfig is not null and has_function_privilege('authenticated', p.oid, 'execute')) from fn join pg_proc p on p.proname = fn.f and p.pronamespace = 'public'::regnamespace), null),
 (8, 'integrity guards are installed and enabled (attachment, version, access-log append-only)',
     (select count(*) = 4 from pg_trigger t where not t.tgisinternal and t.tgenabled = 'O' and t.tgname in ('attachment_guard', 'attachment_version_guard', 'attachment_access_log_no_mutation', 'attachment_access_log_no_truncate')), null),
 (9, 'authorisation resolvers exist and are not executable by anon',
     (select count(*) = 3 and bool_and(not has_function_privilege('anon', p.oid, 'execute')) from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname in ('attachment_parent_access', 'attachment_access', 'attachment_object_ok')), null),
 (10, 'attachment.admin exists and is held by SUPER_ADMIN only',
     (select string_agg(r.code, ',' order by r.code) = 'SUPER_ADMIN' from public.role_permission rp join public.role r on r.id = rp.role_id where rp.permission_code = 'attachment.admin'), null),
 (11, 'INFO: registered parent types (expected 0 at 0040 - each later module registers its own)', null, (select count(*)::text from public.attachment_target)),
 (12, 'storage bucket "attachments" exists and is PRIVATE with a 25 MB limit',
     (select count(*) = 1 and bool_and(not b.public) and bool_and(b.file_size_limit = 26214400) from storage.buckets b where b.id = 'attachments'), null),
 (13, 'storage policies attachments_obj_insert and attachments_obj_select exist for authenticated only',
     (select count(*) = 2 and bool_and(p.roles = array['authenticated']::name[]) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects' and p.policyname in ('attachments_obj_insert', 'attachments_obj_select')), null),
 (14, 'NO update or delete policy exists for the attachments bucket (objects are immutable through the API)',
     not exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects' and p.cmd in ('UPDATE', 'DELETE', 'ALL') and (coalesce(p.qual, '') || coalesce(p.with_check, '')) like '%attachments%'), null),
 (15, 'NO storage policy for anon/public touches the attachments bucket (no public access)',
     not exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects' and (p.roles && array['anon', 'public']::name[]) and (coalesce(p.qual, '') || coalesce(p.with_check, '')) like '%attachments%'), null),
 (16, 'INFO: every policy on storage.objects (review for anything unexpected)', null, (select coalesce(string_agg(p.policyname || ' [' || p.cmd || ' to ' || array_to_string(p.roles, '+') || ']', '; ' order by p.policyname), '(none)') from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects')),
 (17, 'pg_cron is OFF: ' || case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'extension installed - confirm no jobs are scheduled' else 'extension not installed' end, not exists (select 1 from pg_extension where extname = 'pg_cron'), null),
 (18, 'INFO: pending attachments / access-log rows', null, (select (select count(*) from public.attachment where link_status = 'PENDING') || ' pending / ' || (select count(*) from public.attachment_access_log) || ' log rows'))
)
select n, check_name, case when info is not null then 'INFO' when coalesce(ok, false) then 'PASS' else 'FAIL' end as result, info from c
union all
select 99, 'OVERALL', case when bool_and(info is not null or coalesce(ok, false)) then 'PASS' else 'FAIL' end, null from c
order by 1;
-- END OF FILE
