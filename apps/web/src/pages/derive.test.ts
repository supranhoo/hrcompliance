import { describe, expect, it } from 'vitest'
import { complianceDerive, exceptionDerive } from './Registers'

describe('drill-down -> server filters', () => {
  it('passes plain filters through and drops the search param', () => expect(complianceDerive({ due_state: 'overdue', q: 'CMP-1' })).toEqual({ filters: { due_state: 'overdue' } }))
  it('due_within becomes a server-side date range on open work only', () => {
    const d = complianceDerive({ due_within: '30' })
    expect(d.filters.status).toEqual(['open', 'in_progress']); expect(d.ranges?.due_date?.gte).toMatch(/^\d{4}-\d{2}-\d{2}$/); expect(d.ranges?.due_date?.lte).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    expect('due_within' in d.filters).toBe(false)
  })
  it('rejects a non-numeric due_within instead of building a bad range', () => expect(complianceDerive({ due_within: '30; drop' }).ranges).toBeUndefined())
  it('"open" exceptions means open + acknowledged', () => expect(exceptionDerive({ status: 'open', severity: 'critical' }).filters).toEqual({ severity: 'critical', status: ['open', 'acknowledged'] }))
  it('other exception statuses are exact', () => expect(exceptionDerive({ status: 'resolved' }).filters).toEqual({ status: 'resolved' }))
  it('target_breached implies unresolved', () => expect(exceptionDerive({ target_breached: 'true' }).filters).toEqual({ target_breached: true, status: ['open', 'acknowledged'] }))
})

import { timing } from './quickviews'
describe('quick-view timing text', () => {
  it('never shows a negative countdown', () => {
    expect(timing({ status: 'open', days_overdue: 0, days_to_due: 5 })).toBe('5 day(s) to go')
    expect(timing({ status: 'open', days_overdue: 0, days_to_due: 0 })).toBe('Due today')
    expect(timing({ status: 'in_progress', days_overdue: 3, days_to_due: -3 })).toBe('3 day(s) overdue')
    expect(timing({ status: 'completed', days_overdue: 0, days_to_due: -8 })).toBe('Completed')
    expect(timing({ status: 'not_applicable', days_overdue: 0, days_to_due: -8 })).toBe('Not applicable')
  })
})
