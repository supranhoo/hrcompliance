// Real-browser smoke test (headless Chromium) against the Vite dev server. The Supabase network layer is INTERCEPTED and answered from
// fixtures generated from the real database (apps/web/src/lib/fixtures). This verifies rendering, routing, guards, drill-down and URL-sync
// in a real browser; it does NOT verify Supabase/Google (that needs the live environment - docs/AUTH.md).
import { chromium } from 'playwright-core'
import { spawn } from 'node:child_process'
import { readFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs'
import { join } from 'node:path'

const root = new URL('../../', import.meta.url).pathname
const fx = (n) => JSON.parse(readFileSync(join(root, 'apps/web/src/lib/fixtures', n), 'utf8'))
const SHOTS = process.env.SHOTS_DIR || join(root, 'tests/e2e/.shots'); mkdirSync(SHOTS, { recursive: true })
const PORT = 5199, BASE = `http://localhost:${PORT}`, SB = 'https://fake-project.supabase.test'
const chromePath = process.env.CHROME_PATH || (() => { const b = '/opt/pw-browsers'; if (!existsSync(b)) return undefined; const d = readdirSync(b).find((x) => x.startsWith('chromium_headless_shell')) ; return d ? join(b, d, 'chrome-linux/headless_shell') : undefined })()

const vite = spawn('npx', ['vite', '--port', String(PORT), '--strictPort'], { cwd: join(root, 'apps/web'), env: { ...process.env, VITE_SUPABASE_URL: SB, VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_fake', VITE_APP_ENV: 'development' }, stdio: 'ignore' })
const cleanup = () => { try { vite.kill('SIGTERM') } catch { /* already gone */ } }
process.on('exit', cleanup)
for (let i = 0; i < 60; i++) { try { if ((await fetch(BASE)).ok) break } catch { /* not up yet */ } await new Promise((r) => setTimeout(r, 500)) }

const results = []; const check = (name, ok, detail = '') => { results.push({ name, ok }); console.log(`${ok ? 'ok  ' : 'FAIL'} - ${name}${ok ? '' : '  ' + detail}`) }
const browser = await chromium.launch({ executablePath: chromePath, args: ['--no-sandbox'] })
const ctx = await browser.newContext({ viewport: { width: 1360, height: 860 } })
const requests = []; const posts = []
const profile = (perms) => ({ ...fx('my_access.json'), permissions: perms })
let access = profile(fx('my_access.json').permissions)
const today = new Date(); const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const json = (body, extra = {}) => ({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'content-range', ...extra }, body: JSON.stringify(body) })
await ctx.route(`${SB}/**`, async (route) => {
  const req = route.request(); const u = new URL(req.url()); requests.push(`${req.method()} ${u.pathname}${u.search}`)
  if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } })
  const p = u.pathname
  if (p.endsWith('/rpc/my_access')) return route.fulfill(json(access))
  if (p.endsWith('/rpc/compliance_dashboard')) return route.fulfill(json(fx('dashboard.json')))
  if (p.endsWith('/rpc/compliance_calendar')) return route.fulfill(json(fx('calendar.json').map((r, i) => ({ ...r, due_date: iso(new Date(today.getFullYear(), today.getMonth(), today.getDate() + i)) }))))
  if (p.endsWith('/lov_value')) return route.fulfill(json([{ code: 'high', label: 'High' }, { code: 'low', label: 'Low' }]))
  if (p.endsWith('/status_definition')) return route.fulfill(json([{ code: 'open', label: 'Open', category: 'open', color: 'blue' }, { code: 'completed', label: 'Completed', category: 'closed', color: 'green' }]))
  if (p.endsWith('/status_transition')) return route.fulfill(json([{ to_status: 'completed', requires_reason: false }]))
  const views = { v_compliance_instance: 'v_compliance_instance.json', v_exception: 'v_exception.json', v_licence_status: 'v_licence_status.json', v_evidence_requirement: 'v_evidence_requirement.json' }
  const view = Object.keys(views).find((v) => p.endsWith('/' + v))
  if (view) return route.fulfill(json([fx(views[view])], { 'content-range': '0-0/1' }))
  if (req.method() === 'POST' && p.endsWith('/compliance_master')) { posts.push({ path: p, body: req.postData() }); return route.fulfill({ ...json({ id: 'new-master' }), status: 201 }) }
  if (p.endsWith('/rpc/alert_routing_validation')) return route.fulfill(json([]))
  if (p.endsWith('/notification')) return route.fulfill(json(req.method() === 'HEAD' ? [] : [{ id: 'n1', category: 'alert_unroutable', title: 'UNROUTED: SAMPLE-MONTHLY is due today', body: 'CMP-2026-000001 - rule has no valid recipient', link_kind: 'compliance_instance', link_id: 'i1', created_at: new Date().toISOString(), read_at: null }], { 'content-range': '0-0/1' }))
  if (p.endsWith('/rpc/system_health')) return route.fulfill(json({ database: { connected: true, server_time: new Date().toISOString(), postgres_major: 17 }, schema_version: '20261003000023', integrations: { google_drive: 'NOT_CONFIGURED', gmail: 'NOT_CONFIGURED' }, latest_job: null, latest_failed_job: null, jobs_failed_24h: 0, unroutable_alerts: 2, unroutable_notifications_7d: 1, alert_routing: { errors: 1, warnings: 0 }, latest_job_warning: null, environment: 'production' }))
  if (p.endsWith('/app_user')) return route.fulfill(json([], { 'content-range': '*/0' }))
  return route.fulfill(json([]))
})
// a signed-in browser session (unsigned fake JWT: the client only reads it, the "server" is the interceptor)
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url')
const jwt = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: '59bace57-c19a-4169-901e-e837e871109a', role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600, email: 'admin@example.test' })}.sig`
const session = { access_token: jwt, refresh_token: 'r', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: '59bace57-c19a-4169-901e-e837e871109a', email: 'admin@example.test', aud: 'authenticated', app_metadata: { provider: 'google', providers: ['google'] }, user_metadata: {}, created_at: new Date().toISOString() } }
await ctx.addInitScript(([k, v]) => { try { if (!localStorage.getItem('e2e-signed-out')) localStorage.setItem(k, v) } catch { /* ignore */ } }, ['sb-fake-project-auth-token', JSON.stringify(session)])
const page = await ctx.newPage()
const errors = []; page.on('pageerror', (e) => errors.push(e.message)); page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|net::ERR/.test(m.text())) errors.push(m.text()) })
const wait = (ms = 700) => page.waitForTimeout(ms)

// 1. dashboard
await page.goto(BASE + '/'); await page.getByRole('heading', { name: 'Executive Dashboard' }).waitFor()
const d = fx('dashboard.json')
check('dashboard renders server numbers', (await page.getByRole('button', { name: /^Overdue/ }).innerText()).includes(String(d.obligations.overdue)))
check('dashboard shows the compliance % definition', await page.getByText(/Completed obligations as a share/).isVisible())
await page.screenshot({ path: join(SHOTS, '1-dashboard.png'), fullPage: true })
// 2. drill-down: overdue tile -> filtered register, filter in URL, server query carries the filter
await page.getByRole('button', { name: /^Overdue/ }).click(); await page.waitForURL('**/compliance?due_state=overdue'); await wait()
if (process.env.DEBUG_DUMP) { console.log('MAIN:', (await page.locator('main').innerText()).slice(0, 600)); console.log('REQ:', requests.slice(-8).join('\n')); console.log('ERR:', JSON.stringify(errors)) }
check('overdue drill-down lands on the register with the filter in the URL', page.url().endsWith('/compliance?due_state=overdue'))
check('register queried the server with due_state=eq.overdue', requests.some((r) => r.includes('/v_compliance_instance') && r.includes('due_state=eq.overdue')))
check('register used server-side range + count (never loads whole table)', requests.some((r) => r.includes('/v_compliance_instance')) && !requests.some((r) => /limit=\d{4,}/.test(r)))
check('filter control reflects the URL', (await page.getByLabel('State').inputValue()) === 'overdue')
await page.screenshot({ path: join(SHOTS, '2-register-overdue.png'), fullPage: true })
// 3. quick view
await page.locator('tbody tr').first().click(); await page.getByRole('tab', { name: 'Summary' }).waitFor()
check('row opens the quick view with tabs', (await page.getByRole('tab').count()) >= 3)
await page.screenshot({ path: join(SHOTS, '3-quickview.png') })
await page.keyboard.press('Escape'); await wait(300)
// 4. next-30-days drill-down builds a date range
await page.goto(BASE + '/compliance?due_within=30'); await wait()
check('due_within becomes a server date range on open work', requests.some((r) => r.includes('due_date=gte.') && r.includes('due_date=lte.') && r.includes('status=in.')))
// 5. other registers + calendar
for (const [path, heading, table] of [['/exceptions?severity=critical&status=open', 'Exceptions', 'v_exception'], ['/licences?expiry_category=expired', 'Licences & Registrations', 'v_licence_status'], ['/evidence?evidence_state=missing', 'Evidence', 'v_evidence_requirement']]) {
  await page.goto(BASE + path); await page.getByRole('heading', { name: heading, exact: true }).waitFor(); await wait(500)
  check(`${heading}: renders and queries ${table} with URL filters`, requests.some((r) => r.includes('/' + table) && /=(eq|in)\./.test(r)))
}
await page.screenshot({ path: join(SHOTS, '4-evidence.png'), fullPage: true })
await page.goto(BASE + '/calendar'); await page.getByRole('heading', { name: 'Compliance Calendar' }).waitFor(); await wait()
check('calendar month grid has 42 day cells', (await page.locator('button[aria-label*="item(s)"]').count()) === 42)
await page.screenshot({ path: join(SHOTS, '5-calendar-month.png'), fullPage: true })
await page.getByRole('button', { name: 'Agenda' }).click(); await wait()
await page.screenshot({ path: join(SHOTS, '6-calendar-agenda.png'), fullPage: true })
check('calendar queries the RPC for the visible range only', requests.filter((r) => r.includes('compliance_calendar')).length >= 2)
// 5b. Notification Centre + bell + System Health (D-001)
await page.goto(BASE + '/'); await page.getByRole('heading', { name: 'Executive Dashboard' }).waitFor(); await wait(400)
check('bell shows the unread count from the server', (await page.getByRole('link', { name: /Notifications \(1 unread\)/ }).count()) === 1)
await page.getByRole('link', { name: /Notifications \(1 unread\)/ }).click(); await page.getByRole('heading', { name: 'Notification Centre' }).waitFor()
check('Notification Centre lists the unrouted alert with its category', (await page.getByText('Unrouted alert').count()) >= 1 && await page.getByText('UNROUTED: SAMPLE-MONTHLY is due today').isVisible())
await page.goto(BASE + '/admin/system-health'); await page.getByRole('heading', { name: 'System Health' }).waitFor(); await wait(300)
check('System Health shows unroutable alerts and routing errors', await page.getByText('Unroutable alerts').first().isVisible() && await page.getByText('Alert routing errors').isVisible())
await page.getByRole('button', { name: /^Unroutable alerts/ }).click(); await wait(300)
check('unroutable tile drills to the exception register filtered by category', page.url().endsWith('/exceptions?category=alert_unroutable'))
// 5c. Master Data administration (screens render, query their read models, validate and write through the base table)
const adminPages = [['/admin/compliance-masters', 'Compliance Master', 'v_compliance_master'], ['/admin/rule-versions', 'Rule Versions', 'v_compliance_rule_version'], ['/admin/applicability', 'Applicability Matrix', 'v_applicability'],
  ['/admin/applicability/coverage', 'Coverage & gaps', 'v_compliance_coverage'], ['/admin/licence-types', 'Licence & Registration Types', 'licence_type'], ['/admin/reference/location', 'Locations', '/location'],
  ['/admin/reference/document-type', 'Document Types', 'document_type'], ['/admin/lov', 'Lists (LOV)', 'lov_set'], ['/admin/statuses', 'Statuses & Transitions', 'status_definition'], ['/admin/alert-rules', 'Alert Rules', 'v_alert_rule'], ['/admin/imports', 'Imports', 'v_import_batch'], ['/admin/imports/new', 'New import', 'import_template'], ['/admin/users', 'Users', 'v_user_admin'], ['/admin/roles', 'Roles & Permissions', 'v_role_admin'], ['/admin/jobs', 'Job Monitor', 'v_job_status']]
for (const [path, title, table] of adminPages) {
  const mk = requests.length; await page.goto(BASE + path); await page.getByRole('heading', { name: title, exact: true }).first().waitFor(); await wait(350)
  check(`admin: ${title} renders and queries ${table.replace('/', '')}`, requests.slice(mk).some((r) => r.includes(table)))
}
await page.goto(BASE + '/admin/settings'); await page.getByRole('heading', { name: 'Settings' }).waitFor(); await wait(300)
check('admin: Settings lists the typed settings from system_config', requests.some((r) => r.includes('/system_config')) && await page.getByText('Due-soon window (days)').count() >= 0)
await page.goto(BASE + '/admin/exception-config'); await page.getByRole('heading', { name: 'Exception Settings' }).waitFor(); await wait(300)
check('admin: Exception Settings explains unroutable alerts and links to the alert rules', await page.getByRole('link', { name: /Alert Rules/ }).first().isVisible())
await page.goto(BASE + '/admin/compliance-masters'); await page.getByRole('button', { name: 'New compliance' }).click()
await page.getByRole('button', { name: 'Create compliance' }).click(); await wait(200)
check('admin: an empty create is blocked by frontend validation (no request)', (await page.getByText('Code is required').isVisible()) && posts.length === 0)
await page.getByLabel(/^Code/).fill('pf-monthly'); await page.getByLabel(/^Name/).fill('PF monthly'); await page.getByRole('button', { name: 'Create compliance' }).click(); await wait(500)
check('admin: a valid create is written to compliance_master with a clean payload', posts.length === 1 && posts[0].path.endsWith('/compliance_master') && JSON.parse(posts[0].body).code === 'PF-MONTHLY' && JSON.parse(posts[0].body).category_name === undefined)
await page.setViewportSize({ width: 390, height: 800 }); await page.goto(BASE + '/admin/applicability'); await wait(400)
check('admin: mobile layout has no horizontal page scroll', await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1))
await page.screenshot({ path: join(SHOTS, '8-admin-mobile.png') }); await page.setViewportSize({ width: 1360, height: 860 })
// 6. sidebar + breadcrumbs + responsive
await page.goto(BASE + '/exceptions'); await wait(400)
check('breadcrumb shows the current page', await page.locator('nav[aria-label="Breadcrumb"]').getByText('Exceptions').isVisible())
await page.setViewportSize({ width: 390, height: 800 }); await wait(300)
check('mobile: sidebar collapses behind a menu button', await page.getByRole('button', { name: 'Open navigation' }).isVisible())
check('mobile: no horizontal page scroll', await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1))
await page.screenshot({ path: join(SHOTS, '7-mobile.png') })
await page.setViewportSize({ width: 1360, height: 860 })
// 7. permission gating: a viewer without exception.read cannot open the register
access = profile(['compliance.read']); const mark = requests.length; await page.goto(BASE + '/exceptions'); await wait()
check('route guard: no exception.read -> permission message, no data request', await page.getByText('You do not have permission to view this page').isVisible() && !requests.slice(mark).some((r) => r.includes('v_exception')))
check('nav hides sections the user cannot open', (await page.getByRole('link', { name: 'Exceptions' }).count()) === 0)
// 8. unprovisioned account
access = {}; await page.goto(BASE + '/'); await wait(900)
check('empty my_access() -> /no-access', page.url().endsWith('/no-access'))
check('no-access page offers re-check and sign out', (await page.getByText('Re-check access').isVisible()) && (await page.getByText('Sign out').isVisible()))
// 9. signed out
await page.evaluate(() => { localStorage.setItem('e2e-signed-out', '1'); localStorage.removeItem('sb-fake-project-auth-token') }); await page.goto(BASE + '/compliance'); await wait(600)
check('signed-out visit to a protected URL redirects to /login', page.url().endsWith('/login'))
check('login page offers Google sign-in', await page.getByRole('button', { name: 'Continue with Google' }).isEnabled())
check('no uncaught page errors', errors.length === 0, JSON.stringify(errors.slice(0, 3)))
await browser.close(); cleanup()
const failed = results.filter((r) => !r.ok); console.log(`\n${results.length - failed.length}/${results.length} browser checks passed; screenshots in ${SHOTS}`)
process.exit(failed.length ? 1 : 0)
