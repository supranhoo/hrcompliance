import { describe, expect, it } from 'vitest'
import { defaultWindow, pctText, pctWidth, pivotPipeline, totalsOf, validateWindow, type PerfRow } from './reports'

const row = (o: Partial<PerfRow>): PerfRow => ({ group_key: 'k', group_label: 'K', total: 0, completed: 0, completed_on_time: 0, completed_late: 0, overdue_open: 0, upcoming_open: 0, due_to_date: 0, on_time_to_date: 0, completed_to_date: 0, on_time_pct: null, compliance_pct: null, ...o })
describe('report helpers', () => {
  it('default window is the last 12 months', () => { expect(defaultWindow(new Date('2026-10-04T10:00:00Z'))).toEqual({ from: '2025-10-04', to: '2026-10-04' }) })
  it('validates the window', () => {
    expect(validateWindow('', '2026-01-01')).toMatch(/both dates/); expect(validateWindow('2026-02-01', '2026-01-01')).toMatch(/after/); expect(validateWindow('2000-01-01', '2026-01-01')).toMatch(/10 years/); expect(validateWindow('2026-01-01', '2026-02-01')).toBeNull()
  })
  it('totals are recomputed from counts, not averaged', () => {
    const t = totalsOf([row({ total: 10, due_to_date: 10, on_time_to_date: 9, completed_to_date: 10 }), row({ total: 2, due_to_date: 2, on_time_to_date: 0, completed_to_date: 1 })])
    expect(t.total).toBe(12); expect(t.due_to_date).toBe(12); expect(t.on_time_pct).toBe(75); expect(t.compliance_pct).toBe(91.7)    // an average of 90% and 50% would wrongly give 70%
  })
  it('no obligations due yet gives no percentage', () => { expect(totalsOf([row({ total: 3, upcoming_open: 3 })]).on_time_pct).toBeNull() })
  it('formats percentages and bar widths safely', () => { expect(pctText(33.333)).toBe('33.3%'); expect(pctText(null)).toBe('—'); expect(pctWidth(150)).toBe('100%'); expect(pctWidth(-5)).toBe('0%'); expect(pctWidth(null)).toBe('0%') })
  it('pivots the licence pipeline with expired first and types as columns', () => {
    const p = pivotPipeline([{ bucket: '2026-12', licence_type_code: 'B', licence_type_name: 'Bee', licences: 2 }, { bucket: 'expired', licence_type_code: 'A', licence_type_name: 'Ay', licences: 1 }, { bucket: '2026-12', licence_type_code: 'A', licence_type_name: 'Ay', licences: 3 }])
    expect(p.types.map((t) => t.code)).toEqual(['A', 'B']); expect(p.lines.map((l) => l.bucket)).toEqual(['expired', '2026-12']); expect(p.lines[1]).toEqual({ bucket: '2026-12', counts: { A: 3, B: 2 }, total: 5 })
  })
})
