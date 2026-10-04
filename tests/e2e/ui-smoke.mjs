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
  if (p.endsWith('/rpc/management_dashboard')) return route.fulfill(json({ generated_at: new Date().toISOString(), period: { from: '2025-10-04', to: '2026-10-04' }, filters: { entity_id: null, location_id: null, department_id: null }, top_risk_level: 'critical', top_severity: 'critical',
    kpis: { total_applicable: 120, due_this_month: 14, overdue: 6, critical_open: 9, critical_overdue: 2, due_to_date: 100, completed_to_date: 88, on_time_to_date: 80, compliance_pct: 88, on_time_pct: 80, open_exceptions: 11, critical_exceptions: 3, licences_expiring: 5, licences_expired: 1 },
    licences: { expiring: 5, expired: 1, horizon_days: 90, department_filter_applies: false },
    trend: [{ month: '2026-08', due: 10, completed_on_time: 7, completed_late: 1, overdue_open: 2, upcoming_open: 0, due_to_date: 10, compliance_pct: 80 }, { month: '2026-09', due: 12, completed_on_time: 9, completed_late: 1, overdue_open: 1, upcoming_open: 1, due_to_date: 11, compliance_pct: 90.9 }],
    risk: [{ level: 'low', label: 'Low', sort_order: 10, open: 3, overdue: 0 }, { level: 'critical', label: 'Critical', sort_order: 40, open: 9, overdue: 2 }],
    by_location: [{ code: 'PUN', name: 'Pune', total: 40, open: 8, overdue: 4, due_to_date: 35, completed_to_date: 30, compliance_pct: 85.7 }], by_department: [{ id: null, name: '(no responsible department)', total: 10, open: 1, overdue: 0, due_to_date: 9, completed_to_date: 9, compliance_pct: 100 }],
    upcoming: [{ instance_no: 'CMP-1', compliance_code: 'PF', compliance_name: 'PF return', location_code: 'PUN', due_date: '2026-10-10', risk_level: 'high', due_state: 'due_soon' }],
    critical_exceptions: [{ id: 'x1', exception_no: 'EXC-9', category: 'overdue', severity: 'critical', description: 'Filing not made', age_days: 12, target_breached: true, location_code: 'PUN' }], exception_ageing: { '0-7': 2, '31-90': 1 }, definitions: {} }))
  if (p.endsWith('/rpc/compliance_dashboard')) return route.fulfill(json(fx('dashboard.json')))
  if (p.endsWith('/rpc/compliance_calendar')) return route.fulfill(json(fx('calendar.json').map((r, i) => ({ ...r, due_date: iso(new Date(today.getFullYear(), today.getMonth(), today.getDate() + i)) }))))
  if (p.endsWith('/lov_value')) return route.fulfill(json([{ code: 'high', label: 'High' }, { code: 'low', label: 'Low' }]))
  if (p.endsWith('/status_definition')) return route.fulfill(json([{ code: 'open', label: 'Open', category: 'open', color: 'blue' }, { code: 'completed', label: 'Completed', category: 'closed', color: 'green' }]))
  if (p.endsWith('/status_transition')) return route.fulfill(json([{ to_status: 'completed', requires_reason: false }]))
  const views = { v_compliance_instance: 'v_compliance_instance.json', v_exception: 'v_exception.json', v_licence_status: 'v_licence_status.json', v_evidence_requirement: 'v_evidence_requirement.json' }
  const view = Object.keys(views).find((v) => p.endsWith('/' + v))
  if (view) return route.fulfill(json([fx(views[view])], { 'content-range': '0-0/1' }))
  if (req.method() === 'POST' && p.endsWith('/compliance_master')) { posts.push({ path: p, body: req.postData() }); return route.fulfill({ ...json({ id: 'new-master' }), status: 201 }) }
  if (p.endsWith('/rpc/report_compliance_performance')) return route.fulfill(json([{ group_key: '2026-09', group_label: '2026-09', total: 4, completed: 3, completed_on_time: 2, completed_late: 1, overdue_open: 1, upcoming_open: 0, due_to_date: 4, on_time_to_date: 2, completed_to_date: 3, on_time_pct: 50, compliance_pct: 75 }]))
  if (p.endsWith('/rpc/report_licence_pipeline')) return route.fulfill(json([]))
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

// 1. dashboard: management view first (filters + KPIs from management_dashboard), original detailed view on its own tab
await page.goto(BASE + '/'); await page.getByRole('heading', { name: 'Executive Dashboard' }).waitFor(); await page.getByText('Total applicable').first().waitFor()
const kpiText = async (label) => (await page.getByRole('button', { name: new RegExp('^' + label) }).first().innerText())
check('management dashboard shows the six KPIs from the server', (await kpiText('Total applicable')).includes('120') && (await kpiText('Due this month')).includes('14') && (await kpiText('Overdue')).includes('6') && (await kpiText('Critical')).includes('9') && (await kpiText('Open exceptions')).includes('11') && (await kpiText('Licences expiring')).includes('5'))
check('management dashboard has entity / location / department / period filters', (await page.getByLabel('Entity', { exact: true }).count()) === 1 && (await page.getByLabel('Location', { exact: true }).count()) === 1 && (await page.getByLabel('Department', { exact: true }).count()) === 1 && (await page.getByLabel('Period', { exact: true }).count()) === 1)
check('management dashboard shows trend, risk distribution, performance, upcoming and critical exceptions', (await page.getByRole('img', { name: /Obligations by due month/ }).count()) === 1 && await page.getByText('Risk distribution').isVisible() && await page.getByText('By responsible department').isVisible() && await page.getByText('Critical exceptions').first().isVisible() && await page.getByText('PF return').isVisible())
check('management dashboard queried management_dashboard with the default 12-month period', requests.some((r) => r.includes('rpc/management_dashboard')))
await page.screenshot({ path: join(SHOTS, '1-dashboard.png'), fullPage: true })
await page.setViewportSize({ width: 390, height: 800 }); await wait(300)
check('management dashboard has no horizontal page scroll on a phone', await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1))
await page.screenshot({ path: join(SHOTS, '1-dashboard-mobile.png'), fullPage: true }); await page.setViewportSize({ width: 1280, height: 900 })
await page.getByRole('tab', { name: 'Detailed view' }).click(); await page.getByText(/Completed obligations as a share/).waitFor()
const d = fx('dashboard.json')
check('detailed view still renders server numbers', (await page.getByRole('button', { name: /^Overdue/ }).innerText()).includes(String(d.obligations.overdue)))
check('detailed view shows the compliance % definition', await page.getByText(/Completed obligations as a share/).isVisible())
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
  ['/admin/reference/document-type', 'Document Types', 'document_type'], ['/admin/lov', 'Lists (LOV)', 'lov_set'], ['/admin/statuses', 'Statuses & Transitions', 'status_definition'], ['/admin/alert-rules', 'Alert Rules', 'v_alert_rule'], ['/admin/imports', 'Imports', 'v_import_batch'], ['/admin/imports/new', 'New import', 'import_template'], ['/admin/users', 'Users', 'v_user_admin'], ['/admin/roles', 'Roles & Permissions', 'v_role_admin'], ['/admin/jobs', 'Job Monitor', 'v_job_status'], ['/admin/export-history', 'Export History', 'v_export_log'], ['/reports', 'Reports', 'report_compliance_performance']]
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
// 7. UX audit: every screen at desktop / tablet / phone width - no horizontal overflow, a heading, no script errors, and no serious/critical WCAG A/AA violations (axe-core)
const AXE = readFileSync(join(root, 'node_modules/axe-core/axe.min.js'), 'utf8')
const AUDIT_ROUTES = ['/', '/compliance', '/calendar', '/exceptions', '/licences', '/evidence', '/notifications', '/reports', '/admin/compliance-masters', '/admin/rule-versions', '/admin/applicability', '/admin/applicability/coverage', '/admin/licence-types',
  '/admin/reference/entity', '/admin/reference/location', '/admin/reference/law', '/admin/reference/authority', '/admin/reference/department', '/admin/reference/document-type', '/admin/reference/category', '/admin/alert-rules', '/admin/exception-config', '/admin/lov', '/admin/statuses',
  '/admin/settings', '/admin/imports', '/admin/imports/new', '/admin/users', '/admin/roles', '/admin/export-history', '/admin/jobs', '/admin/system-health']
const AUDIT_WIDTHS = [[1360, 860, 'desktop'], [768, 1024, 'tablet'], [390, 800, 'phone']]
const AUDIT_ROUTES_USED = process.env.AUDIT_ROUTES ? process.env.AUDIT_ROUTES.split(',') : AUDIT_ROUTES
const RUN_AUDIT = process.env.UX_AUDIT !== '0'     // on by default; UX_AUDIT=0 skips it for quick local runs
access = profile(fx('my_access.json').permissions)   // earlier checks switch to restricted profiles; the audit needs the full one
const auditErrors = errors.length; const overflowFindings = []; const axeFindings = []; const noHeading = []
for (const [w, h, label] of RUN_AUDIT ? AUDIT_WIDTHS : []) {
  await page.setViewportSize({ width: w, height: h })
  for (const r of AUDIT_ROUTES_USED) {
    const t0 = Date.now(); await page.goto(BASE + r, { waitUntil: 'domcontentloaded' }); await page.locator('h1').first().waitFor({ timeout: 4000 }).catch(() => {}); await wait(150)
    if (process.env.AUDIT_DUMP) console.log(`audit ${label} ${r} ${Date.now() - t0}ms`)
    if ((await page.locator('h1').count()) === 0) noHeading.push(`${label} ${r}`)
    const wide = await page.evaluate(() => { const m = document.querySelector('main'); const lim = m ? m.getBoundingClientRect().right : window.innerWidth; const inner = m && m.scrollWidth > m.clientWidth + 1; const wideEls = (document.documentElement.scrollWidth > window.innerWidth + 1 || inner) ? [...document.querySelectorAll('main *')].filter((e) => e.getBoundingClientRect().right > lim + 1 && !e.closest('[role=region]') && !e.closest('.overflow-x-auto') && !e.closest('.sr-only')).slice(0, 2).map((e) => e.tagName + '.' + String(e.className).slice(0, 50)).join(' | ') : ''; return wideEls || (inner ? 'main scrolls horizontally' : '') })
    if (wide) overflowFindings.push(`${label} ${r}: ${wide}`)
    if (label === 'desktop' || label === 'phone') {
      await page.evaluate(AXE)
      const v = await page.evaluate(async () => (await window.axe.run(document, { runOnly: ['wcag2a', 'wcag2aa'] })).violations.filter((x) => x.impact === 'critical' || x.impact === 'serious').map((x) => `${x.id}(${x.nodes.length}): ${x.nodes[0].target.join(' ').slice(0, 70)} <= ${(x.nodes[0].html || '').slice(0, 110)}`))
      for (const x of v) axeFindings.push(`${label} ${r}: ${x}`)
    }
  }
}
await page.setViewportSize({ width: 1360, height: 860 })
if (process.env.AUDIT_DUMP) { console.log('OVERFLOW', JSON.stringify(overflowFindings, null, 1)); console.log('AXE', JSON.stringify(axeFindings, null, 1)); console.log('NOH1', JSON.stringify(noHeading)) }
if (RUN_AUDIT) {
check(`UX audit: no horizontal overflow on ${AUDIT_ROUTES.length} screens at desktop, tablet and 390px phone width`, overflowFindings.length === 0, overflowFindings.slice(0, 4).join(' ;; '))
check('UX audit: every screen has a page heading', noHeading.length === 0, noHeading.slice(0, 4).join(', '))
check('UX audit: no serious or critical WCAG A/AA violations (axe-core) on desktop and phone', axeFindings.length === 0, axeFindings.slice(0, 4).join(' ;; '))
check('UX audit: no script errors while visiting every screen', errors.length === auditErrors, JSON.stringify(errors.slice(auditErrors, auditErrors + 3)))
}
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
