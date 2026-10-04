import { describe, expect, it } from 'vitest'
import { drillTo, filtersFromParams, paramsFromFilters, periodFor, pctOf, validateDashPeriod } from './management'

const U1 = '11111111-1111-1111-1111-111111111111'; const U2 = '22222222-2222-2222-2222-222222222222'
const today = new Date(2026, 9, 4)
describe('management dashboard filters', () => {
  it('period presets are calendar windows ending today', () => {
    expect(periodFor('3m', today)).toEqual({ from: '2026-07-04', to: '2026-10-04' }); expect(periodFor('12m', today)).toEqual({ from: '2025-10-04', to: '2026-10-04' }); expect(periodFor('ytd', today)).toEqual({ from: '2026-01-01', to: '2026-10-04' })
  })
  it('reads filters from the URL, ignoring malformed values', () => {
    const f = filtersFromParams(new URLSearchParams(`entity=${U1}&location=not-a-uuid&department=${U2}&period=6m`), today)
    expect(f).toMatchObject({ entity: U1, location: '', department: U2, preset: '6m', from: '2026-04-04', to: '2026-10-04' })
    expect(filtersFromParams(new URLSearchParams('period=evil'), today).preset).toBe('12m')
  })
  it('custom dates are only honoured when both are valid', () => {
    expect(filtersFromParams(new URLSearchParams('period=custom&from=2026-01-01&to=2026-02-01'), today)).toMatchObject({ preset: 'custom', from: '2026-01-01', to: '2026-02-01' })
    expect(filtersFromParams(new URLSearchParams('period=custom&from=2026-01-01'), today).preset).toBe('12m')
  })
  it('round-trips through the URL and omits defaults', () => {
    const f = filtersFromParams(new URLSearchParams(`entity=${U1}&period=custom&from=2026-01-01&to=2026-02-01`), today)
    expect(filtersFromParams(paramsFromFilters(f), today)).toEqual(f); expect(paramsFromFilters(filtersFromParams(new URLSearchParams(), today)).toString()).toBe('')
  })
  it('validates a custom period', () => { expect(validateDashPeriod('2026-02-01', '2026-01-01')).toMatch(/after/); expect(validateDashPeriod('2000-01-01', '2026-01-01')).toMatch(/10 years/); expect(validateDashPeriod('x', 'y')).toMatch(/both dates/); expect(validateDashPeriod('2026-01-01', '2026-02-01')).toBeNull() })
  it('drill links carry the filters the target register understands', () => {
    const f = { entity: U1, location: U2, department: 'd1' }
    expect(drillTo('/compliance', f, { due_state: 'overdue' })).toBe(`/compliance?due_state=overdue&entity_id=${U1}&location_id=${U2}&owner_department_id=d1`)
    expect(drillTo('/exceptions', f, { status: 'open' })).toBe(`/exceptions?status=open&entity_id=${U1}&location_id=${U2}&department_id=d1`)
    expect(drillTo('/licences', f, { expiry_category: 'expired' }, { department: false })).toBe(`/licences?expiry_category=expired&entity_id=${U1}&location_id=${U2}`)
    expect(drillTo('/compliance', { entity: '', location: '', department: '' })).toBe('/compliance')
  })
  it('percentages need a denominator', () => { expect(pctOf(3, 4)).toBe(75); expect(pctOf(1, 3)).toBe(33.3); expect(pctOf(1, 0)).toBeNull() })
})
