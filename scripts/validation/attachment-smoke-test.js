/* MANUAL FALLBACK ONLY - superseded by the automated workflow "Verify DEV storage smoke test" (scripts/validation/dev-storage-smoke.mjs, docs/LIVE_VERIFICATION_AUTOMATION.md).
 * DEV storage smoke test for the generic attachment foundation (migration 0040).
 * Proves, with a SYNTHETIC 1x1 PNG only (no personal or confidential data):  authorised upload -> private object -> authorised read -> unauthorised read DENIED.
 * It runs in the browser console of the already signed-in DEV app (https://hrcompliance.pages.dev) and uses YOUR OWN session token against Supabase; nothing is sent anywhere else.
 * Only paste the contents of this file from the repository. The URL and the publishable (anon) key are public by design; the service-role key must NEVER be used here.
 *
 * STEP 1 (signed in as the uploader, e.g. SUPER_ADMIN):      attachmentSmoke.step1({ url, key })       -> prints PASS/FAIL lines and the VERSION_ID / KEY for step 2
 * STEP 2 (a DIFFERENT user in another browser profile, e.g.   attachmentSmoke.step2({ url, key, versionId, objectKey })
 *         HEAD_HR without attachment.admin)                    -> must show every read DENIED
 * The test leaves one deactivated synthetic attachment and one tiny object in the private bucket (objects cannot be deleted through the API by design; there is no cleanup job).
 */
(function () {
  const PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
  const bytes = () => Uint8Array.from(atob(PNG_B64), (c) => c.charCodeAt(0));
  const hex = async (u8) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', u8))).map((b) => b.toString(16).padStart(2, '0')).join('');
  const results = [];
  const check = (label, ok, detail) => { results.push({ check: label, result: ok ? 'PASS' : 'FAIL', detail: detail || '' }); console.log((ok ? 'PASS' : 'FAIL') + ' - ' + label + (detail ? '  (' + detail + ')' : '')); return ok; };
  function token(cfg) {
    if (cfg.token) return cfg.token;
    const k = Object.keys(localStorage).find((x) => /^sb-.*-auth-token$/.test(x));
    if (!k) throw new Error('no Supabase session found in this browser: sign in to the app first');
    const v = JSON.parse(localStorage.getItem(k)); return v.access_token || (v.currentSession && v.currentSession.access_token);
  }
  const hdr = (cfg, t, extra) => Object.assign({ apikey: cfg.key }, t ? { Authorization: 'Bearer ' + t } : {}, extra || {});
  const rpc = (cfg, t, name, body) => fetch(cfg.url + '/rest/v1/rpc/' + name, { method: 'POST', headers: hdr(cfg, t, { 'Content-Type': 'application/json' }), body: JSON.stringify(body) });
  const read = (cfg, t, key) => fetch(cfg.url + '/storage/v1/object/authenticated/attachments/' + key, { headers: hdr(cfg, t) });

  async function step1(cfg) {
    const t = token(cfg), data = bytes(), sha = await hex(data);
    // a document type that allows PNG (or any type)
    let r = await fetch(cfg.url + '/rest/v1/document_type?select=id,code,allowed_mime_types,max_size_mb&is_active=eq.true', { headers: hdr(cfg, t) });
    const types = r.ok ? await r.json() : [];
    const dt = types.find((d) => !d.allowed_mime_types || d.allowed_mime_types.map((m) => m.toLowerCase()).includes('image/png'));
    if (!check('a document type that allows image/png exists (create one in Master Data if not)', !!dt, dt ? dt.code : 'status ' + r.status)) return results;
    // 1. reserve (database mints the key)
    r = await rpc(cfg, t, 'attachment_begin_upload', { p_document_type_id: dt.id, p_file_name: 'smoke-test.png', p_mime_type: 'image/png', p_size_bytes: data.length, p_sha256: sha, p_confidentiality: 'standard' });
    const row = r.ok ? (await r.json())[0] : null;
    if (!check('begin_upload returns an attachment, a version and a database-minted key', !!(row && row.storage_key), 'status ' + r.status)) return results;
    const { attachment_id: attId, version_id: verId, storage_key: key } = row;
    check('the key is not derived from the file name', !key.includes('smoke'));
    // 2. unauthorised upload to a key that was never reserved must fail
    r = await fetch(cfg.url + '/storage/v1/object/attachments/not-reserved/' + crypto.randomUUID(), { method: 'POST', headers: hdr(cfg, t, { 'Content-Type': 'image/png', 'x-upsert': 'false' }), body: data });
    check('upload to a key that was never reserved is DENIED', !r.ok, 'status ' + r.status);
    // 3. authorised upload to the reserved key
    r = await fetch(cfg.url + '/storage/v1/object/attachments/' + key, { method: 'POST', headers: hdr(cfg, t, { 'Content-Type': 'image/png', 'x-upsert': 'false' }), body: data });
    check('authorised upload to the reserved key succeeds', r.ok, 'status ' + r.status);
    // 4. overwrite must fail (no update policy)
    r = await fetch(cfg.url + '/storage/v1/object/attachments/' + key, { method: 'PUT', headers: hdr(cfg, t, { 'Content-Type': 'image/png' }), body: data });
    check('overwriting the stored object is DENIED', !r.ok, 'status ' + r.status);
    // 5. database verifies the stored object against the declaration
    r = await rpc(cfg, t, 'attachment_complete_upload', { p_version_id: verId });
    check('complete_upload verifies size and content type and makes the version available', r.ok, 'status ' + r.status);
    // 6. authorised read with the caller's own JWT (no signed URL)
    r = await read(cfg, t, key);
    const got = r.ok ? new Uint8Array(await r.arrayBuffer()) : null;
    check('authorised read returns the object', !!got, 'status ' + r.status);
    check('the downloaded bytes match the declared SHA-256', !!got && (await hex(got)) === sha);
    // 7. the object is private
    r = await fetch(cfg.url + '/storage/v1/object/public/attachments/' + key);
    check('the PUBLIC URL does not serve the object (bucket is private)', !r.ok, 'status ' + r.status);
    r = await read(cfg, null, key);
    check('an anonymous read of the authenticated URL is DENIED', !r.ok, 'status ' + r.status);
    // 8. authorised download path (logged for confidential) and the listing view hides the key
    r = await rpc(cfg, t, 'attachment_authorize_download', { p_version_id: verId });
    check('authorize_download works for the uploader of a pending attachment', r.ok, 'status ' + r.status);
    r = await fetch(cfg.url + '/rest/v1/attachment_version?select=storage_key&id=eq.' + verId, { headers: hdr(cfg, t) });
    check('the storage key cannot be read through the table API', !r.ok, 'status ' + r.status);
    // 9. tidy up the metadata (the tiny object cannot be removed through the API by design)
    r = await rpc(cfg, t, 'attachment_deactivate', { p_attachment_id: attId, p_reason: 'DEV smoke test (synthetic file)' });
    check('the synthetic attachment is deactivated', r.ok, 'status ' + r.status);
    console.log('\nGive these two values to STEP 2 (run as a DIFFERENT user):\n  versionId = ' + verId + '\n  objectKey = ' + key);
    console.table(results);
    return results;
  }

  async function step2(cfg) {
    const t = token(cfg);
    let r = await rpc(cfg, t, 'attachment_authorize_download', { p_version_id: cfg.versionId });
    check('another user cannot authorise a download of that version', !r.ok, 'status ' + r.status);
    r = await read(cfg, t, cfg.objectKey);
    check('another user cannot read the object even with the exact key', !r.ok, 'status ' + r.status);
    r = await fetch(cfg.url + '/storage/v1/object/list/attachments', { method: 'POST', headers: hdr(cfg, t, { 'Content-Type': 'application/json' }), body: JSON.stringify({ prefix: '', limit: 100 }) });
    const items = r.ok ? await r.json() : [];
    check('listing the bucket shows no objects of other users (no enumeration)', Array.isArray(items) && items.length === 0, items.length + ' entries');
    r = await fetch(cfg.url + '/rest/v1/v_attachment?select=id', { headers: hdr(cfg, t) });
    const rows = r.ok ? await r.json() : [];
    check('the attachment listing view shows nothing of the uploader', Array.isArray(rows) && rows.length === 0, rows.length + ' rows');
    console.table(results);
    return results;
  }
  globalThis.attachmentSmoke = { step1, step2 };
})();
