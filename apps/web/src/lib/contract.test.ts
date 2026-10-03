import { describe, expect, it } from 'vitest'
import { dashboardSchema, drill, fmtPct } from './dashboard'
import { CONTRACT } from '../pages/Registers'
import dashboard from './fixtures/dashboard.json'
import calendar from './fixtures/calendar.json'
import vCompliance from './fixtures/v_compliance_instance.json'
import vException from './fixtures/v_exception.json'
import vLicence from './fixtures/v_licence_status.json'
import vEvidence from './fixtures/v_evidence_requirement.json'

// These fixtures are produced by scripts/validation/gen-fixtures.sh from the REAL migrations + data, as an authenticated user.
const views = { compliance: vCompliance, exceptions: vException, licences: vLicence, evidence: vEvidence } as Record<keyof typeof CONTRACT, Record<string, unknown>>

describe('frontend <-> database contract (real PostgreSQL output)', () => {
  it('dashboard RPC payload satisfies the zod schema', () => {
    const d = dashboardSchema.parse(dashboard)
    expect(d.has_data).toBe(true)
    expect(d.obligations.total).toBeGreaterThan(0)
  })
  it('every drill-down link targets a known register route with whitelisted filter keys', () => {
    const routes = { '/compliance': ['due_state', 'status', 'risk_level', 'location_code', 'due_within', 'q'], '/exceptions': ['severity', 'status', 'age_bucket', 'target_breached', 'q'], '/licences': ['expiry_category', 'renewal_status', 'renewal_window_open', 'q'], '/evidence': ['evidence_state', 'q'] } as Record<string, string[]>
    const links = Object.values(drill).map((v) => (typeof v === 'function' ? v('x') : v))
    for (const l of links) {
      const u = new URL(l, 'http://x'); expect(Object.keys(routes)).toContain(u.pathname)
      for (const k of u.searchParams.keys()) expect(routes[u.pathname]).toContain(k)
    }
    expect(links.length).toBeGreaterThanOrEqual(17)
  })
  for (const key of Object.keys(CONTRACT) as Array<keyof typeof CONTRACT>) {
    const c = CONTRACT[key]
    it(`${c.table}: every selected / searched / filtered / sorted column exists in the real view`, () => {
      const cols = Object.keys(views[key])
      for (const col of [...c.select.split(','), ...c.search, ...c.filters, c.sort]) expect(cols, `${c.table}.${col}`).toContain(col)
    })
  }
  it('calendar RPC rows carry every field the calendar reads', () => {
    expect(calendar.length).toBeGreaterThan(0)
    for (const k of ['instance_id', 'instance_no', 'compliance_code', 'compliance_name', 'location_code', 'due_date', 'status', 'due_state', 'risk_level']) expect(Object.keys(calendar[0])).toContain(k)
  })
  it('percent formatting never invents a 0%', () => { expect(fmtPct(null)).toBe('—'); expect(fmtPct(0)).toBe('0%'); expect(fmtPct(87.5)).toBe('87.5%') })
  it('malformed payload is rejected, not rendered', () => { expect(() => dashboardSchema.parse({ ...dashboard, obligations: { total: 'x' } })).toThrow() })
})
