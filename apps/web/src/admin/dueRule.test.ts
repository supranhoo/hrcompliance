import { describe, expect, it } from 'vitest'
import { defaultRule, describeDueRule, ruleTypesFor, validateDueRule } from './dueRule'

describe('due rule language (mirrors app.due_rule_is_valid)', () => {
  it('rule types follow the frequency', () => {
    expect(ruleTypesFor('monthly')).toEqual(['day_of_month', 'days_after_period_end', 'fixed_date'])
    expect(ruleTypesFor('event_based')).toEqual(['days_after_event']); expect(ruleTypesFor('incident_based')).toEqual(['days_after_event'])
    expect(ruleTypesFor('one_time')).toEqual(['absolute_date']); expect(ruleTypesFor('nonsense')).toEqual([])
  })
  it('every default rule is valid for the frequencies that offer it', () => {
    for (const f of ['daily', 'weekly', 'monthly', 'quarterly', 'half_yearly', 'annual', 'one_time', 'event_based', 'incident_based', 'custom']) for (const t of ruleTypesFor(f)) {
      const r = defaultRule(t); expect(validateDueRule(t === 'absolute_date' ? { type: t, date: '2027-03-31' } : r, f)).toBeUndefined()
    }
  })
  it('rejects out-of-range values and a rule type that does not fit the frequency', () => {
    expect(validateDueRule({ type: 'day_of_month', day: 32, month_offset: 1 }, 'monthly')).toMatch(/1 and 31/)
    expect(validateDueRule({ type: 'day_of_month', day: 15, month_offset: 13 }, 'monthly')).toMatch(/0 and 12/)
    expect(validateDueRule({ type: 'days_after_period_end', days: 400 }, 'monthly')).toMatch(/366/)
    expect(validateDueRule({ type: 'fixed_date', month: 13, day: 1, year_offset: 0 }, 'annual')).toMatch(/Month/)
    expect(validateDueRule({ type: 'absolute_date', date: '31/12/2026' }, 'one_time')).toMatch(/valid date/)
    expect(validateDueRule({ type: 'days_after_event', days: 30 }, 'monthly')).toMatch(/cannot be used/)
    expect(validateDueRule(null, 'monthly')).toMatch(/Choose/)
  })
  it('describes rules in plain language', () => {
    expect(describeDueRule({ type: 'day_of_month', day: 15, month_offset: 1 })).toBe('15th of the month after the period ends')
    expect(describeDueRule({ type: 'day_of_month', day: 1, month_offset: 0 })).toBe('1st of the same month the period ends')
    expect(describeDueRule({ type: 'day_of_month', day: 22, month_offset: 2 })).toBe('22nd of 2 months after the period ends')
    expect(describeDueRule({ type: 'days_after_period_end', days: 1 })).toBe('1 day after the period ends')
    expect(describeDueRule({ type: 'fixed_date', month: 3, day: 31, year_offset: 1 })).toBe('31st March, the year after')
    expect(describeDueRule({ type: 'days_after_event', days: 30 })).toBe('30 days after the event'); expect(describeDueRule(null)).toBe('—')
  })
})
