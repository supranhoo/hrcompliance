# Generic attachment foundation (migration 0040)

**Status:** implemented in migration `20261003000040_attachment_foundation.sql`; deployed to DEV for verification; **not yet hash-locked** (lock only after the live check and the storage smoke test pass). Reusable by GRC, Liaison, Plant Visit/CAPA and Disciplinary. The compliance `evidence` model is untouched. **No GRC object, permission, workflow, UI, import or dashboard exists.**

## Model
| Object | Purpose |
|---|---|
| `attachment_target` | Registry of allowed parent object types: `parent_type`, module, `parent_table` (must exist, uuid `id`), `read_permission`, `write_permission`, `access_function` (`app.<fn>(uuid, text) returns boolean`, actions `read` / `write` / `restricted_read`), `is_enabled`. Validated by trigger; written by migrations only (no API write). **Empty at 0040.** |
| `attachment` | Identity: `attachment_no` (`ATT-YYYY-NNNNNN`), `link_status` `PENDING`/`LINKED`, parent type + id, document type, `confidentiality` (`standard`/`confidential`/`restricted`), owner (uploader), current version, active flag + deactivation reason, audit stamps |
| `attachment_version` | One row per file version: safe file name, MIME type, size, **SHA-256 (declared by the uploader, immutable)**, provider (`supabase_storage`/`google_drive`/`external_link`), bucket, **database-minted storage key**, `upload_status` `RESERVED`/`AVAILABLE`, current/superseded-by (+ reason), uploader/time |
| `attachment_access_log` | Append-only record of confidential/restricted download authorisations |
| `v_attachment` | Invoker-rights listing without storage key/bucket |
Parent link is **not** a free polymorphic id: the type must be registered and enabled, the parent row must exist (checked by a trigger on every write and by the resolver on every read), and the parent's own access function decides. Anything unknown, disabled, missing, or an error in the parent function **denies** (fails closed). A linked attachment cannot be re-parented or unlinked.

## Authorisation (derives from the parent)
- **LINKED:** `app.attachment_parent_access(type, id, action)` = registered + enabled + the registry permission + parent exists + the parent's access function. `restricted` attachments also need the parent's `restricted_read`; inactive attachments are visible only to parent writers.
- **PENDING (not yet linked):** visible and readable **only** to the uploader and `attachment.admin` (SUPER_ADMIN). Knowing the UUID or the path grants nothing. `attachment.admin` does **not** bypass a parent's authorisation after linking.
- Linking needs: ownership of the pending attachment, a completed upload, and **write** access to the parent.
- All writes go through SECURITY DEFINER functions; tables have no write grants/policies; guard triggers block direct changes even by superusers (file metadata immutable, one current version, supersession final, no deletes).

## Functions (the only write path)
`attachment_begin_upload` (validates document type, MIME, size, checksum; sanitises the name; per-user pending quota; mints the key) · `attachment_complete_upload` (verifies the stored object's size and content type against the declaration; makes the version available/current) · `attachment_link` · `attachment_new_version` (reason mandatory; supersedes the previous current version on completion) · `attachment_deactivate` (reason) · `attachment_set_confidentiality` (raise with write access; lower only with `attachment.admin`; reason) · `attachment_authorize_download` (the only way to obtain a storage key; logs confidential/restricted reads; same error for "missing" and "forbidden").

## Storage and upload/download mechanism
- **Private bucket `attachments`** (Supabase Storage; `public = false`, 25 MB cap; PDF/JPEG/PNG at bucket level, per-document-type rules in the database). No public bucket, **no permanent or bearer URLs**.
- **The browser never chooses a path.** `attachment_begin_upload` returns `<version id>/<random uuid>`; the file name is never part of the key.
- **Upload:** the client uploads with its **own JWT** to the reserved key (`upsert=false`). The storage policy `attachments_obj_insert` accepts it only if that exact key is a RESERVED version of the caller. Then the client calls `attachment_complete_upload`, which checks size and content type against what the database recorded.
- **Download/read:** the client calls `attachment_authorize_download` (authorisation + logging for confidential/restricted), then reads the object with its own JWT. The policy `attachments_obj_select` re-checks authorisation on **every request**; for confidential/restricted objects it also requires the fresh access-log row (120 s), so a direct storage call cannot skip the log. Signed URLs are intentionally **not** minted (their lifetime is chosen by the caller and they are bearer links).
- **Immutability:** there is no UPDATE or DELETE policy, so objects cannot be overwritten or removed through the API. Disposal/cleanup of abandoned uploads is a later, owner-approved process (**no cleanup job: `pg_cron` stays OFF**; a per-user quota limits abandoned pending uploads).
- **No service-role/secret in the browser.** Only the publishable key and the user's JWT are used. `app.storage_object_meta` reads storage metadata inside a SECURITY DEFINER function.
- **Provider abstraction:** `storage_provider` is a column (`supabase_storage` first); another provider can be added without changing the model. `external_link` versions skip the object check by design only if a module registers them (none do at 0040).
- **Honest limits:** the SHA-256 is the uploader's declaration (the database cannot re-hash the object); malware scanning is not included (the validation hook `app.attachment_validate_file` is where it plugs in); registry/storage-policy creation needs the migration role to have storage privileges (the migration warns loudly and the live check fails if that did not happen).

## Registering a module (future migrations)
Insert one `attachment_target` row (type, module, parent table, permissions, `app.<module>_attachment_access(uuid, text)`), where the access function applies that module's scope/confidentiality rules. Nothing else is needed.

## Tests (suite `65_attachment_foundation.sql`, 80+ assertions, run on PG16 and PG17 in CI)
anon denied everywhere · another user cannot see/authorise/upload/read a pending attachment · unsupported/disabled/missing/erroring parent fails closed · registry validation · confidential read needs a logged authorisation · restricted needs `restricted_read` · versions/supersession integrity · immutability (file name, size, checksum, key, uploader, identity, re-parenting, deletes) · checksum preserved · deactivation rules · storage: reserved keys only, no overwrite/delete, no enumeration, private bucket, no anon/public policy · file name/MIME/size/checksum validation · pending quota · audit · grants.

## Live verification (owner)
1. `supabase/tests/live_gate.sql` → 40 migrations, 53 tables, 19 views, 25 permissions, 13 numbering rules, audit 0, OVERALL PASS.
2. `supabase/dev-samples/live_attachment_check.sql` → every row PASS, OVERALL PASS (structure, RLS, grants, private bucket, storage policies, no public access, `pg_cron` OFF).
3. Storage smoke test with a synthetic 1×1 PNG: `scripts/validation/attachment-smoke-test.js` — STEP 1 as the uploader (SUPER_ADMIN), STEP 2 as a different user. Expected: all lines PASS (authorised upload → private object → authorised read → unauthorised read denied).
Only after all three pass is 0040 hash-locked.
