import { describe, expect, it } from 'vitest'
import { groupByDate, monthMatrix, rangeFor, shift, weekDays, worstState, type CalItem } from './calendar'
import { isoDate } from './urlFilters'

const it1 = (d: string, s = 'upcoming'): CalItem => ({ instance_id: d + s, instance_no: 'CMP-1', compliance_code: 'C', compliance_name: 'n', location_code: 'L', due_date: d, status: 'open', due_state: s, risk_level: 'high' })
describe('calendar helpers', () => {
  it('month grid is always 42 cells, Monday first, covers the month', () => {
    const g = monthMatrix(2026, 9)   // October 2026 starts on a Thursday
    expect(g).toHaveLength(42); expect(g[0].getDay()).toBe(1); expect(isoDate(g[0])).toBe('2026-09-28')
    expect(g.some((d) => isoDate(d) === '2026-10-01')).toBe(true); expect(g.some((d) => isoDate(d) === '2026-10-31')).toBe(true)
  })
  it('a month starting on Monday has no leading days', () => expect(isoDate(monthMatrix(2026, 5)[0])).toBe('2026-06-01'))
  it('handles leap day', () => expect(monthMatrix(2028, 1).some((d) => isoDate(d) === '2028-02-29')).toBe(true))
  it('week view is Monday-Sunday around the anchor', () => { const w = weekDays(new Date(2026, 9, 7)); expect(isoDate(w[0])).toBe('2026-10-05'); expect(isoDate(w[6])).toBe('2026-10-11') })
  it('Sunday anchors to the previous Monday', () => expect(isoDate(weekDays(new Date(2026, 9, 11))[0])).toBe('2026-10-05'))
  it('groups items by due date', () => { const m = groupByDate([it1('2026-10-05'), it1('2026-10-05', 'overdue'), it1('2026-10-06')]); expect(m.get('2026-10-05')).toHaveLength(2); expect(m.size).toBe(2) })
  it('fetch ranges match what is drawn', () => {
    expect(rangeFor('month', new Date(2026, 9, 15))).toEqual({ from: '2026-09-28', to: '2026-11-08' })
    expect(rangeFor('week', new Date(2026, 9, 7))).toEqual({ from: '2026-10-05', to: '2026-10-11' })
    expect(rangeFor('agenda', new Date(2026, 9, 3))).toEqual({ from: '2026-10-03', to: '2026-12-02' })
  })
  it('navigation shifts by the right unit', () => {
    expect(isoDate(shift('month', new Date(2026, 11, 15), 1))).toBe('2027-01-01')
    expect(isoDate(shift('week', new Date(2026, 9, 7), -1))).toBe('2026-09-30')
  })
  it('worst state wins', () => { expect(worstState([it1('d', 'completed'), it1('d', 'overdue')])).toBe('overdue'); expect(worstState([it1('d', 'completed')])).toBe('completed') })
})
