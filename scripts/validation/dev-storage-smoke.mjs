#!/usr/bin/env node
/* DEV storage smoke test for the generic attachment foundation (migration 0040), fully automated.
 *
 * Proves, with a SYNTHETIC 1x1 PNG and two dedicated SYNTHETIC test logins (no BFCL person, no confidential data):
 *     User A: reserve -> upload -> complete -> read OK (checksum equals the original)
 *     then DENIED: User B, an anonymous caller, the public URL; and overwrite / key-column read attempts.
 *
 * Uses ONLY the project URL, the PUBLISHABLE (anon) key and the two synthetic logins. No service-role / secret key, no database password, no admin API.
 * Refuses to run if the key looks like a service-role / secret key. Never prints a token, a password or a key.
 *
 * Environment: SUPABASE_URL  SUPABASE_PUBLISHABLE_KEY  SMOKE_USER_A_EMAIL  SMOKE_USER_A_PASSWORD  SMOKE_USER_B_EMAIL  SMOKE_USER_B_PASSWORD  DEV_DB_USER (ci_verifier.<project-ref>, a public variable)
 * Side effects on DEV (by design): one attachment row (deactivated at the end) + one ~70-byte private object that stays, because the 0040 storage policies allow no delete/update.
 * Exit status: 0 = every check PASS; 1 = any FAIL or "SETUP REQUIRED"; 2 = missing/unsafe configuration.
 */
import { createHash } from 'node:crypto';
import { appendFileSync } from 'node:fs';

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const sha = (b) => createHash('sha256').update(b).digest('hex');
const SHA = sha(PNG);
const e = process.env;
const results = [];
let aborted = false;

function config() {
  const need = ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SMOKE_USER_A_EMAIL', 'SMOKE_USER_A_PASSWORD', 'SMOKE_USER_B_EMAIL', 'SMOKE_USER_B_PASSWORD'];
  const missing = need.filter((k) => !e[k]);
  if (missing.length) return { error: 'missing configuration: ' + missing.join(', ') + ' (names only; see docs/LIVE_VERIFICATION_AUTOMATION.md)' };
  let u;
  try { u = new URL(e.SUPABASE_URL); } catch { return { error: 'SUPABASE_URL is not a valid URL' }; }
  const local = e.SMOKE_TEST_MODE === '1' && (u.hostname === '127.0.0.1' || u.hostname === 'localhost');
  if (!local && (u.protocol !== 'https:' || !/^[a-z0-9]+\.supabase\.co$/.test(u.hostname))) return { error: 'SUPABASE_URL must be https://<project-ref>.supabase.co' };
  const key = e.SUPABASE_PUBLISHABLE_KEY;
  if (/^sb_secret_/i.test(key)) return { error: 'REFUSED: SUPABASE_PUBLISHABLE_KEY holds a secret (service-role style) key. Only the publishable/anon key may be used.' };
  if (key.split('.').length === 3) {                                  // legacy JWT keys: refuse role=service_role
    try { const role = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role; if (role && role !== 'anon') return { error: 'REFUSED: the API key carries role "' + role + '"; only the anon/publishable key may be used.' }; } catch { return { error: 'SUPABASE_PUBLISHABLE_KEY is not a valid key' }; }
  } else if (!/^sb_publishable_/i.test(key) && !local) return { error: 'SUPABASE_PUBLISHABLE_KEY must be an sb_publishable_... key (or the legacy anon JWT)' };
  if (!local) {                                                       // tie the target to the project the read-only DB workflow proved to be "development"
    const m = /^ci_verifier\.([a-z0-9]+)$/.exec(e.DEV_DB_USER || '');
    if (!m) return { error: 'DEV_DB_USER (ci_verifier.<project-ref>) is required to confirm the target project' };
    if (u.hostname !== m[1] + '.supabase.co') return { error: 'REFUSED: SUPABASE_URL is not the project named in DEV_DB_USER; the smoke test runs against the DEV project only.' };
  }
  return { url: u.origin, key, aEmail: e.SMOKE_USER_A_EMAIL, aPw: e.SMOKE_USER_A_PASSWORD, bEmail: e.SMOKE_USER_B_EMAIL, bPw: e.SMOKE_USER_B_PASSWORD };
}

function check(name, ok, detail) {
  results.push({ name, ok: !!ok, detail: detail || '' });
  console.log((ok ? 'PASS' : 'FAIL') + ' - ' + name + (detail ? '  (' + detail + ')' : ''));
  return !!ok;
}
function setup(msg) { check('SETUP REQUIRED: ' + msg, false); aborted = true; return false; }

async function http(cfg, method, path, { token, anon = true, headers = {}, body, json } = {}) {
  const h = { ...headers };
  if (anon) h.apikey = cfg.key;
  if (token) h.Authorization = 'Bearer ' + token;
  if (json !== undefined) { h['Content-Type'] = 'application/json'; body = JSON.stringify(json); }
  let res;
  try { res = await fetch(cfg.url + path, { method, headers: h, body }); } catch (err) { return { status: 0, ok: false, buf: Buffer.alloc(0), text: '', err: String(err.cause?.code || err.message) }; }
  const buf = Buffer.from(await res.arrayBuffer());
  return { status: res.status, ok: res.ok, buf, text: buf.toString('utf8') };
}
const rpc = (cfg, token, name, args) => http(cfg, 'POST', '/rest/v1/rpc/' + name, { token, json: args });
const parse = (r) => { try { return JSON.parse(r.text); } catch { return null; } };
const objPost = (key) => '/storage/v1/object/attachments/' + key;
const objUrl = (kind, key) => '/storage/v1/object/' + kind + '/attachments/' + key;     // key = "<uuid>/<uuid>": slashes stay as path separators

async function signIn(cfg, email, password, label) {
  const r = await http(cfg, 'POST', '/auth/v1/token?grant_type=password', { json: { email, password } });
  const j = parse(r);
  if (!r.ok || !j?.access_token) { setup('synthetic user ' + label + ' cannot sign in (status ' + r.status + '). Create it in Supabase Authentication with a confirmed email, enable Email + password sign-in, and check the password secret.'); return null; }
  console.log('::add-mask::' + j.access_token); if (j.refresh_token) console.log('::add-mask::' + j.refresh_token);
  return { token: j.access_token, id: j.user?.id };
}
async function access(cfg, who, label) {
  const r = await rpc(cfg, who.token, 'my_access', {});
  const j = parse(r);
  if (!r.ok || !j || !j.user_id) { setup('synthetic user ' + label + ' is not an active app user. Add its email in the app (Users) with the VIEWER role, then re-run.'); return null; }
  const roles = (j.roles || []).join(',');
  if (roles !== 'VIEWER' || j.scope_all === true || (j.permissions || []).includes('attachment.admin')) { setup('synthetic user ' + label + ' must have exactly the VIEWER role, no all-scope and no attachment.admin (has: ' + (roles || 'none') + ').'); return null; }
  check('user ' + label + ' is an active synthetic app user with exactly the VIEWER role, no elevated rights', true);
  return j;
}

export async function main() {
  const cfg = config();
  if (cfg.error) { console.log('CONFIG - ' + cfg.error); process.exitCode = 2; return; }
  let att = null, A = null, B = null;
  try {
    A = await signIn(cfg, cfg.aEmail, cfg.aPw, 'A'); if (!A) return;
    B = await signIn(cfg, cfg.bEmail, cfg.bPw, 'B'); if (!B) return;
    if (A.id && A.id === B.id) { setup('user A and user B must be two different synthetic users'); return; }
    check('both synthetic users sign in with the publishable key (no service-role key involved)', true);
    if (!(await access(cfg, A, 'A')) || !(await access(cfg, B, 'B'))) return;

    // an existing document type that accepts image/png (nothing is created here)
    let r = await http(cfg, 'GET', '/rest/v1/document_type?select=id,code,allowed_mime_types,max_size_mb&is_active=eq.true&order=code', { token: A.token });
    const types = r.ok ? parse(r) || [] : [];
    const accepts = (d) => Array.isArray(d.allowed_mime_types) && d.allowed_mime_types.some((m) => String(m).toLowerCase() === 'image/png');
    const open = (d) => !d.allowed_mime_types || d.allowed_mime_types.length === 0;
    const dt = types.find((d) => accepts(d) && (d.max_size_mb == null || d.max_size_mb >= 1)) || types.find((d) => open(d) && (d.max_size_mb == null || d.max_size_mb >= 1));
    if (!dt) { setup('no image/png document type available'); return; }
    check('an active document type that accepts image/png exists', true, 'code ' + dt.code);

    // 1. reserve (the database mints the storage key)
    r = await rpc(cfg, A.token, 'attachment_begin_upload', { p_document_type_id: dt.id, p_file_name: 'ci-smoke-synthetic.png', p_mime_type: 'image/png', p_size_bytes: PNG.length, p_sha256: SHA, p_confidentiality: 'standard' });
    const row = r.ok ? (parse(r) || [])[0] : null;
    if (!check('A: reserve - the database mints an attachment, a version and a storage key', row && row.storage_key && row.version_id, 'status ' + r.status)) return;
    att = row;
    check('A: the minted key does not contain the file name', !String(row.storage_key).includes('smoke'));
    // 2. upload to the reserved key
    r = await http(cfg, 'POST', objPost(row.storage_key), { token: A.token, headers: { 'Content-Type': 'image/png', 'x-upsert': 'false' }, body: PNG });
    if (!check('A: upload to the reserved key succeeds', r.ok, 'status ' + r.status)) return;
    // 3. complete (the database verifies size and content type of the stored object)
    r = await rpc(cfg, A.token, 'attachment_complete_upload', { p_version_id: row.version_id });
    if (!check('A: complete - stored size and content type verified, version available', r.ok, 'status ' + r.status)) return;
    // 4. authorised read + checksum
    r = await http(cfg, 'GET', objUrl('authenticated', row.storage_key), { token: A.token });
    const got = r.ok && r.buf.length > 0;
    if (!check('A: authorised read returns the object', got, 'status ' + r.status)) return;
    check('A: SHA-256 of the downloaded PNG equals the original', sha(r.buf) === SHA && r.buf.equals(PNG));

    // 5. denials. Each is only meaningful because (a) the exact same URL was just served to A and (b) B and anon are real, working callers.
    const probe = await http(cfg, 'GET', '/rest/v1/document_type?select=id&limit=1', { token: B.token });
    if (!check('B is a working authenticated caller (so the denials below are authorisation, not a broken request)', probe.ok, 'status ' + probe.status)) return;
    r = await http(cfg, 'GET', objUrl('authenticated', row.storage_key), { token: B.token });
    check('B: read of the exact key is DENIED', !r.ok && !r.buf.equals(PNG), 'status ' + r.status);
    r = await rpc(cfg, B.token, 'attachment_authorize_download', { p_version_id: row.version_id });
    check('B: authorize_download is DENIED', !r.ok, 'status ' + r.status);
    r = await http(cfg, 'POST', objPost(row.storage_key), { token: B.token, headers: { 'Content-Type': 'image/png', 'x-upsert': 'true' }, body: Buffer.from('tamper') });
    check('B: upload / overwrite of the key is DENIED', !r.ok, 'status ' + r.status);
    r = await http(cfg, 'GET', '/rest/v1/v_attachment?select=id&id=eq.' + row.attachment_id, { token: B.token });
    check('B: the attachment is not visible in the listing view', r.ok && (parse(r) || []).length === 0, 'status ' + r.status + ', rows ' + ((parse(r) || []).length ?? '?'));
    r = await http(cfg, 'POST', '/storage/v1/object/list/attachments', { token: B.token, json: { prefix: '', limit: 100, offset: 0 } });
    check('B: bucket listing shows none of the objects (no enumeration)', !r.ok || (parse(r) || []).length === 0, 'status ' + r.status);
    r = await http(cfg, 'GET', objUrl('authenticated', row.storage_key), {});
    check('anonymous: read of the authenticated URL is DENIED', !r.ok && !r.buf.equals(PNG), 'status ' + r.status);
    r = await http(cfg, 'GET', objUrl('authenticated', row.storage_key), { token: cfg.key });
    check('anonymous (publishable key as bearer): read is DENIED', !r.ok && !r.buf.equals(PNG), 'status ' + r.status);
    r = await http(cfg, 'GET', objUrl('public', row.storage_key), { anon: false });
    check('public URL is unavailable (bucket is private)', !r.ok && !r.buf.equals(PNG), 'status ' + r.status);
    // 6. the owner cannot tamper with the object or read the key column either
    r = await http(cfg, 'POST', objPost(row.storage_key), { token: A.token, headers: { 'Content-Type': 'image/png', 'x-upsert': 'true' }, body: Buffer.from('tamper') });
    check('A: overwrite of the stored object is DENIED (objects are immutable)', !r.ok, 'status ' + r.status);
    r = await http(cfg, 'GET', '/rest/v1/attachment_version?select=storage_key&id=eq.' + row.version_id, { token: A.token });
    check('A: the storage_key column is not readable through the table API', !r.ok, 'status ' + r.status);
    r = await http(cfg, 'GET', objUrl('authenticated', row.storage_key), { token: A.token });
    check('A: the object is unchanged after the tamper attempts (checksum still equals the original)', r.ok && sha(r.buf) === SHA, 'status ' + r.status);
  } finally {
    if (att && A) { const r = await rpc(cfg, A.token, 'attachment_deactivate', { p_attachment_id: att.attachment_id, p_reason: 'DEV automated smoke test (synthetic file)' }); check('A: the synthetic attachment is deactivated', r.ok, 'status ' + r.status); }
    for (const u of [A, B]) if (u) await http(cfg, 'POST', '/auth/v1/logout', { token: u.token });
    const fails = results.filter((x) => !x.ok), verdict = fails.length === 0 && !aborted ? 'PASS' : 'FAIL';
    console.log((verdict === 'PASS' ? 'RESULT: PASS' : 'RESULT: FAIL') + ' - ' + results.filter((x) => x.ok).length + ' PASS, ' + fails.length + ' FAIL');
    if (e.GITHUB_STEP_SUMMARY) {
      const md = ['## DEV storage smoke test: ' + (verdict === 'PASS' ? '✅ PASS' : '❌ FAIL'), '', '| result | check |', '|---|---|', ...results.map((x) => '| ' + (x.ok ? 'PASS' : '**FAIL**') + ' | ' + x.name + (x.detail ? ' (' + x.detail + ')' : '') + ' |'), '',
        'Synthetic 1x1 PNG and synthetic users only. One deactivated attachment row and one tiny private object remain on DEV by design (no delete policy).', ''].join('\n');
      appendFileSync(e.GITHUB_STEP_SUMMARY, md);
    }
    if (verdict !== 'PASS' && !process.exitCode) process.exitCode = 1;
  }
}
if (import.meta.url === 'file://' + process.argv[1]) main();
