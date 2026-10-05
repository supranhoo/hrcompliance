#!/usr/bin/env node
/* Self-test for scripts/validation/dev-storage-smoke.mjs against an in-process mock of Supabase Auth / PostgREST / Storage.
 * The mock models the intended 0040 behaviour (private bucket, owner-only, immutable objects). Each "broken" mode removes one protection and the smoke test MUST fail on exactly that check.
 * This proves the smoke test cannot pass vacuously. It does NOT replace the real DEV run (which exercises the real Supabase Storage + RLS).  Runs in CI (web job); no network, no secrets.
 */
import http from 'node:http';
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const USERS = { 'a@example.test': { pw: 'pa', tok: 'tokA', id: 'ua' }, 'b@example.test': { pw: 'pb', tok: 'tokB', id: 'ub' } };
const ANON = 'sb_publishable_mock';

function mock(mode) {
  const st = { att: null, obj: new Map(), done: false, active: true, calls: [] };
  const who = (req) => { const t = (req.headers.authorization || '').replace('Bearer ', ''); return Object.values(USERS).find((u) => u.tok === t) || null; };
  const srv = http.createServer(async (req, res) => {
    const chunks = []; for await (const c of req) chunks.push(c); const body = Buffer.concat(chunks);
    const url = new URL(req.url, 'http://x'), p = url.pathname, u = who(req);
    const send = (code, data, type) => { res.writeHead(code, { 'Content-Type': type || 'application/json' }); res.end(Buffer.isBuffer(data) ? data : data === undefined ? '' : JSON.stringify(data)); };
    const json = () => { try { return JSON.parse(body.toString() || '{}'); } catch { return {}; } };
    st.calls.push(req.method + ' ' + p);
    if (p === '/auth/v1/token') { const j = json(), x = USERS[j.email]; return x && x.pw === j.password ? send(200, { access_token: x.tok, refresh_token: 'r' + x.tok, user: { id: x.id } }) : send(400, { error: 'invalid_grant' }); }
    if (p === '/auth/v1/logout') return send(204);
    if (p === '/rest/v1/rpc/my_access') return u ? send(200, { user_id: u.id, roles: mode === 'b-not-viewer' && u.id === 'ub' ? ['SUPER_ADMIN'] : ['VIEWER'], scope_all: false, permissions: ['master.read'] }) : send(200, {});
    if (p === '/rest/v1/document_type') return u ? send(200, mode === 'no-png-type' ? [{ id: 'd1', code: 'PDF_ONLY', allowed_mime_types: ['application/pdf'], max_size_mb: 10 }] : [{ id: 'd1', code: 'PDF_ONLY', allowed_mime_types: ['application/pdf'], max_size_mb: 10 }, { id: 'd2', code: 'PHOTO', allowed_mime_types: ['image/png', 'image/jpeg'], max_size_mb: 5 }]) : send(401, {});
    if (p === '/rest/v1/rpc/attachment_begin_upload') { if (!u) return send(401, {}); const j = json(); if (j.p_document_type_id !== 'd2') return send(400, { message: 'content type not allowed' }); st.att = { attachment_id: randomUUID(), version_id: randomUUID(), storage_bucket: 'attachments', storage_key: randomUUID() + '/' + randomUUID(), owner: u.id }; return send(200, [st.att]); }
    if (p === '/rest/v1/rpc/attachment_complete_upload') { if (!u || !st.att || u.id !== st.att.owner || !st.obj.has(st.att.storage_key)) return send(400, { message: 'not authorised' }); st.done = true; return send(204); }
    if (p === '/rest/v1/rpc/attachment_authorize_download') return u && st.att && (u.id === st.att.owner || mode === 'leaky-b-rpc') ? send(200, {}) : send(400, { message: 'attachment not available' });
    if (p === '/rest/v1/rpc/attachment_deactivate') { if (!u || !st.att || u.id !== st.att.owner) return send(400, { message: 'not authorised' }); st.active = false; return send(204); }
    if (p === '/rest/v1/v_attachment') return u ? send(200, mode === 'leaky-b-view' && u.id === 'ub' ? [{ id: st.att?.attachment_id }] : u.id === 'ua' && st.att ? [{ id: st.att.attachment_id }] : []) : send(401, {});
    if (p === '/rest/v1/attachment_version') return mode === 'key-column-readable' ? send(200, [{ storage_key: st.att?.storage_key }]) : send(403, { code: '42501', message: 'permission denied' });
    const m = /^\/storage\/v1\/object\/(authenticated|public)?\/?attachments\/(.+)$/.exec(p);
    if (req.method === 'POST' && /^\/storage\/v1\/object\/list\/attachments$/.test(p)) return u ? send(200, mode === 'leaky-b-list' && u.id === 'ub' ? [{ name: 'x' }] : []) : send(401, {});
    if (m && req.method === 'POST') {
      const key = m[2]; if (!u || !st.att || key !== st.att.storage_key || u.id !== st.att.owner) return send(403, { message: 'new row violates row-level security policy' });
      if (st.obj.has(key) && mode !== 'overwrite-allowed') return send(400, { message: 'resource already exists' });
      st.obj.set(key, body); return send(200, { Key: 'attachments/' + key });
    }
    if (m && req.method === 'GET') {
      const key = m[2], kind = m[1] || 'authenticated', o = st.obj.get(key);
      if (kind === 'public') return mode === 'public-bucket' && o ? send(200, o, 'image/png') : send(400, { message: 'Bucket not found' });
      if (!o || !st.done) return send(404, { message: 'not found' });
      if (!u) return mode === 'anon-read' ? send(200, o, 'image/png') : send(400, { message: 'invalid jwt' });
      if (u.id !== st.att.owner && mode !== 'leaky-b-read') return send(404, { message: 'Object not found' });
      return send(200, mode === 'corrupt-download' ? Buffer.from('not the png') : o, 'image/png');
    }
    send(404, { message: 'no route ' + p });
  });
  return { srv, st };
}

function run(port, extra = {}) {
  return new Promise((resolve) => {
    const env = { PATH: process.env.PATH, SMOKE_TEST_MODE: '1', SUPABASE_URL: 'http://127.0.0.1:' + port, SUPABASE_PUBLISHABLE_KEY: ANON, SMOKE_USER_A_EMAIL: 'a@example.test', SMOKE_USER_A_PASSWORD: 'pa', SMOKE_USER_B_EMAIL: 'b@example.test', SMOKE_USER_B_PASSWORD: 'pb', ...extra };
    const c = spawn(process.execPath, ['scripts/validation/dev-storage-smoke.mjs'], { env }); let out = '';
    c.stdout.on('data', (d) => (out += d)); c.stderr.on('data', (d) => (out += d)); c.on('close', (code) => resolve({ code, out }));
  });
}

let failed = 0;
const expect = (label, ok, extra) => { console.log((ok ? 'ok   - ' : 'FAIL - ') + label); if (!ok) { failed++; if (extra) console.log(extra); } };

async function scenario(mode, label, wantCode, wantText, extra) {
  const { srv, st } = mock(mode); await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  const r = await run(srv.address().port, extra); srv.close();
  expect(label, r.code === wantCode && (!wantText || r.out.includes(wantText)), r.out);
  return { r, st };
}

const good = await scenario('good', 'healthy system: every check PASSES (exit 0)', 0, 'RESULT: PASS');
if (process.env.VERBOSE) console.log(good.r.out);
expect('  ... the synthetic attachment was deactivated and the object is the original PNG', good.st.active === false && good.st.obj.size === 1 && [...good.st.obj.values()][0].equals(PNG));
expect('  ... no token, password or key appears in the output', !/tokA|tokB|sb_publishable_mock|pa\b.*password/.test(good.r.out.replace(/::add-mask::tok[AB]|::add-mask::rtok[AB]/g, '')));
expect('  ... tokens are registered with ::add-mask:: before use', good.r.out.includes('::add-mask::tokA') && good.r.out.includes('::add-mask::tokB'));
await scenario('no-png-type', 'no image/png document type -> "SETUP REQUIRED: no image/png document type available"', 1, 'SETUP REQUIRED: no image/png document type available');
await scenario('b-not-viewer', 'user B with an elevated role is rejected as SETUP REQUIRED', 1, 'must have exactly the VIEWER role');
await scenario('leaky-b-read', 'BROKEN: user B can read the object -> FAIL on "B: read of the exact key is DENIED"', 1, 'FAIL - B: read of the exact key is DENIED');
await scenario('leaky-b-rpc', 'BROKEN: user B can authorise a download -> FAIL', 1, 'FAIL - B: authorize_download is DENIED');
await scenario('leaky-b-view', 'BROKEN: user B sees the attachment in the view -> FAIL', 1, 'FAIL - B: the attachment is not visible in the listing view');
await scenario('leaky-b-list', 'BROKEN: bucket listing enumerates objects -> FAIL', 1, 'FAIL - B: bucket listing shows none');
await scenario('anon-read', 'BROKEN: anonymous read works -> FAIL', 1, 'FAIL - anonymous: read of the authenticated URL is DENIED');
await scenario('public-bucket', 'BROKEN: public URL serves the object -> FAIL', 1, 'FAIL - public URL is unavailable');
await scenario('overwrite-allowed', 'BROKEN: objects can be overwritten -> FAIL', 1, 'FAIL - A: overwrite of the stored object is DENIED');
await scenario('key-column-readable', 'BROKEN: storage_key readable through the table API -> FAIL', 1, 'FAIL - A: the storage_key column is not readable');
await scenario('corrupt-download', 'BROKEN: downloaded bytes differ from the original -> FAIL on checksum', 1, 'FAIL - A: SHA-256 of the downloaded PNG equals the original');
await scenario('good', 'a wrong password for a synthetic user -> SETUP REQUIRED, nothing else runs', 1, 'SETUP REQUIRED: synthetic user A cannot sign in', { SMOKE_USER_A_PASSWORD: 'wrong' });
await scenario('good', 'a service-role style key is REFUSED before any request (exit 2)', 2, 'REFUSED', { SUPABASE_PUBLISHABLE_KEY: 'sb_secret_abcdef' });
const jwt = (role) => 'h.' + Buffer.from(JSON.stringify({ role })).toString('base64url') + '.s';
await scenario('good', 'a legacy service_role JWT is REFUSED (exit 2)', 2, 'REFUSED', { SUPABASE_PUBLISHABLE_KEY: jwt('service_role') });
await scenario('good', 'a missing secret is reported by NAME only (exit 2)', 2, 'missing configuration: SMOKE_USER_B_PASSWORD', { SMOKE_USER_B_PASSWORD: '' });
{ // outside test mode the URL must be the DEV project named in DEV_DB_USER
  const r = await new Promise((resolve) => { const c = spawn(process.execPath, ['scripts/validation/dev-storage-smoke.mjs'], { env: { PATH: process.env.PATH, SUPABASE_URL: 'https://abcdefghij.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_x', SMOKE_USER_A_EMAIL: 'a', SMOKE_USER_A_PASSWORD: 'p', SMOKE_USER_B_EMAIL: 'b', SMOKE_USER_B_PASSWORD: 'p', DEV_DB_USER: 'ci_verifier.zzzzzzzzzz' } }); let out = ''; c.stdout.on('data', (d) => (out += d)); c.on('close', (code) => resolve({ code, out })); });
  expect('a SUPABASE_URL that is not the project in DEV_DB_USER is REFUSED (exit 2, no request made)', r.code === 2 && r.out.includes('not the project named in DEV_DB_USER'), r.out);
}
if (failed) { console.log('SMOKE TEST SELF-TEST FAILED: ' + failed); process.exit(1); }
console.log('ALL STORAGE SMOKE SELF-TESTS PASSED');
