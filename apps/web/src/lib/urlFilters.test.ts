import { describe, expect, it } from 'vitest'
import { filtersFromSearch, isoDate, nextDaysRange, searchFromFilters } from './urlFilters'

describe('drill-down URL filters', () => {
  it('keeps only whitelisted keys', () => expect(filtersFromSearch('?due_state=overdue&evil=1&status=open', ['due_state', 'status'])).toEqual({ due_state: 'overdue', status: 'open' }))
  it('drops values with unexpected characters (no injection into filters)', () => expect(filtersFromSearch('?due_state=a%3Bdrop', ['due_state'])).toEqual({}))
  it('ignores empty values', () => expect(filtersFromSearch('?due_state=', ['due_state'])).toEqual({}))
  it('round-trips', () => expect(searchFromFilters({ a: 'x', b: undefined, c: 'y z' })).toBe('?a=x&c=y+z'))
  it('empty -> empty string', () => expect(searchFromFilters({})).toBe(''))
  it('formats ISO dates without timezone drift', () => expect(isoDate(new Date(2026, 0, 5))).toBe('2026-01-05'))
  it('next-N-days range spans month boundaries', () => expect(nextDaysRange(30, new Date(2026, 0, 15))).toEqual({ gte: '2026-01-15', lte: '2026-02-14' }))
  it('next-N-days handles leap years', () => expect(nextDaysRange(30, new Date(2028, 1, 1))).toEqual({ gte: '2028-02-01', lte: '2028-03-02' }))
})
