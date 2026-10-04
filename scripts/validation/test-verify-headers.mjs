// Proves the live-header check bites: a local server emulating Cloudflare Pages `_headers` handling must PASS with the real file and FAIL when
// the CSP is weakened, a header is dropped, or the asset cache rule is missing. Needs a build (apps/web/dist).
import { createServer } from 'node:http'
import { readFileSync, existsSync, statSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join, extname } from 'node:path'
import { headersFor, parseHeadersFile } from './headers-lib.mjs'
import { verify } from './verify-live-headers.mjs'

const root = fileURLToPath(new URL('../../', import.meta.url)); const dist = join(root, 'apps/web/dist'); const real = readFileSync(join(root, 'apps/web/public/_headers'), 'utf8')
if (!existsSync(join(dist, 'index.html'))) { console.error('build first: npm run build'); process.exit(2) }
const types = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html' }
function serve(headersText) {
  const rules = parseHeadersFile(headersText)
  return new Promise((resolve) => { const s = createServer((req, res) => {
    const path = new URL(req.url, 'http://x').pathname; let file = join(dist, path === '/' ? 'index.html' : path)
    if (!existsSync(file) || statSync(file).isDirectory()) file = join(dist, 'index.html')          // SPA fallback (_redirects: /* /index.html 200)
    const h = Object.fromEntries(headersFor(rules, path)); res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream', ...h }); res.end(readFileSync(file))
  }).listen(0, () => resolve({ url: `http://localhost:${s.address().port}`, close: () => s.close() })) })
}
const cases = [
  ['the real _headers file passes', real, true],
  ['weakened CSP (unsafe-inline scripts) fails', real.replace("script-src 'self'", "script-src 'self' 'unsafe-inline'"), false],
  ['CSP with eval fails', real.replace("script-src 'self'", "script-src 'self' 'unsafe-eval'"), false],
  ['missing X-Frame-Options and frame-ancestors fails', real.replace(/^\s*X-Frame-Options:.*$/m, '').replace(" frame-ancestors 'none';", ''), false],
  ['missing referrer policy fails', real.replace(/^\s*Referrer-Policy:.*$/m, ''), false],
  ['missing nosniff fails', real.replace(/^\s*X-Content-Type-Options:.*$/m, ''), false],
  ['missing asset caching rule fails', real.replace(/\/assets\/\*\n\s*Cache-Control:.*\n/, ''), false],
]
let bad = 0
for (const [name, text, shouldPass] of cases) {
  const srv = await serve(text); const { failures } = await verify(srv.url); srv.close()
  const ok = shouldPass ? failures.length === 0 : failures.length > 0
  console.log(`${ok ? 'ok  ' : 'FAIL'} - ${name}${ok ? '' : ': ' + JSON.stringify(failures)}`); if (!ok) bad++
}
process.exit(bad ? 1 : 0)
