#!/usr/bin/env node
// Verifies that a DEPLOYED site (e.g. the Cloudflare Pages URL) returns exactly the headers declared in apps/web/public/_headers.
// Usage: node scripts/validation/verify-live-headers.mjs https://<your-pages-host>      (read-only: GET requests only; no credentials involved)
import { fileURLToPath } from 'node:url'
import { headersFor, loadRules } from './headers-lib.mjs'

const HEADERS_FILE = fileURLToPath(new URL('../../apps/web/public/_headers', import.meta.url))
// What the production-readiness decision requires at minimum (checked by name even if someone edits _headers):
const REQUIRED = ['content-security-policy', 'x-frame-options', 'referrer-policy', 'x-content-type-options', 'permissions-policy', 'strict-transport-security']

export async function verify(base, { file = HEADERS_FILE, fetchImpl = fetch } = {}) {
  const rules = loadRules(file); const failures = []; const notes = []
  const get = async (path) => { const r = await fetchImpl(new URL(path, base), { redirect: 'manual', headers: { 'user-agent': 'bfcl-header-check' } }); return { status: r.status, headers: r.headers, text: path === '/' ? await r.text() : '' } }
  const fail = (m) => failures.push(m)
  const compare = (label, res, path) => {
    for (const [name, want] of headersFor(rules, path)) {
      const got = res.headers.get(name)
      if (got === null) fail(`${label}: missing header ${name}`)
      else if (got.replace(/\s+/g, ' ').trim() !== want.replace(/\s+/g, ' ').trim()) fail(`${label}: ${name} differs\n      want: ${want}\n       got: ${got}`)
    }
  }
  const home = await get('/'); if (home.status !== 200) fail(`/ returned HTTP ${home.status}`)
  compare('/', home, '/')
  for (const n of REQUIRED) if (!home.headers.get(n)) fail(`/: required security header ${n} is not present`)
  const csp = home.headers.get('content-security-policy') ?? ''
  if (/unsafe-eval/.test(csp) || /script-src[^;]*'unsafe-inline'/.test(csp) || /script-src[^;]*\*/.test(csp)) fail('/: CSP allows eval, inline script or a wildcard script source')
  if (!/frame-ancestors 'none'/.test(csp) && home.headers.get('x-frame-options')?.toUpperCase() !== 'DENY') fail('/: page can be framed')
  const spa = await get('/compliance'); if (spa.status !== 200) fail(`SPA route /compliance returned HTTP ${spa.status} (expected the app shell)`); compare('/compliance (SPA route)', spa, '/compliance')
  const asset = (home.text.match(/\/assets\/[A-Za-z0-9._-]+\.(?:js|css)/g) ?? [])[0]
  if (!asset) fail('/: no hashed /assets/ file referenced from the HTML shell')
  else {
    const a = await get(asset); if (a.status !== 200) fail(`${asset} returned HTTP ${a.status}`)
    compare(asset, a, asset); notes.push(`asset checked: ${asset}  cache-control: ${a.headers.get('cache-control')}`)
    if (!/immutable/.test(a.headers.get('cache-control') ?? '') || !/max-age=31536000/.test(a.headers.get('cache-control') ?? '')) fail(`${asset}: hashed asset is not cached as immutable for a year`)
  }
  notes.push(`/ cache-control: ${home.headers.get('cache-control')}`)
  return { failures, notes }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const base = process.argv[2]
  if (!base || !/^https?:\/\//.test(base)) { console.error('usage: verify-live-headers.mjs https://<host>'); process.exit(2) }
  const { failures, notes } = await verify(base)
  for (const n of notes) console.log('info -', n)
  if (failures.length) { for (const f of failures) console.log('FAIL -', f); console.log(`\n${failures.length} header problem(s) at ${base}`); process.exit(1) }
  console.log(`ok   - ${base} returns the headers declared in apps/web/public/_headers (CSP, framing, referrer, nosniff, permissions, HSTS, asset caching)`)
}
