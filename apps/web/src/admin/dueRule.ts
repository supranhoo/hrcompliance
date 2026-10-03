import { MONTHS, PERIODIC } from './domain'

/** The due-date language the database accepts (app.due_rule_is_valid / app.compute_due_date). Whitelisted JSON only - no expressions, no code.
 *  Everything here mirrors the database so the form can guide the user; the database check constraint remains the authority. */
export type DueRule =
  | { type: 'day_of_month'; day: number; month_offset: number }
  | { type: 'days_after_period_end'; days: number }
  | { type: 'fixed_date'; month: number; day: number; year_offset: number }
  | { type: 'absolute_date'; date: string }
  | { type: 'days_after_event'; days: number }
export type DueRuleType = DueRule['type']

export const RULE_TYPE_LABEL: Record<DueRuleType, string> = {
  day_of_month: 'Fixed day of a following month', days_after_period_end: 'Days after the period ends', fixed_date: 'Fixed calendar date',
  absolute_date: 'One specific date', days_after_event: 'Days after the event',
}
/** Which due-rule types make sense for a frequency (the database enforces the same pairing). */
export function ruleTypesFor(frequency: string): DueRuleType[] {
  if (PERIODIC.has(frequency)) return ['day_of_month', 'days_after_period_end', 'fixed_date']
  if (frequency === 'event_based' || frequency === 'incident_based') return ['days_after_event']
  if (frequency === 'one_time' || frequency === 'custom') return ['absolute_date']
  return []
}
export function defaultRule(type: DueRuleType): DueRule {
  switch (type) {
    case 'day_of_month': return { type, day: 15, month_offset: 1 }
    case 'days_after_period_end': return { type, days: 7 }
    case 'fixed_date': return { type, month: 3, day: 31, year_offset: 1 }
    case 'absolute_date': return { type, date: '' }
    case 'days_after_event': return { type, days: 30 }
  }
}
const int = (v: unknown) => typeof v === 'number' && Number.isInteger(v)
/** Returns an error message, or undefined when the rule is acceptable for the frequency. */
export function validateDueRule(r: DueRule | null | undefined, frequency: string): string | undefined {
  if (!r) return 'Choose how the due date is worked out'
  if (!ruleTypesFor(frequency).includes(r.type)) return `"${RULE_TYPE_LABEL[r.type]}" cannot be used with a ${frequency.replace(/_/g, ' ')} frequency`
  switch (r.type) {
    case 'day_of_month': if (!int(r.day) || r.day < 1 || r.day > 31) return 'Day must be between 1 and 31'; if (!int(r.month_offset) || r.month_offset < 0 || r.month_offset > 12) return 'Months after must be between 0 and 12'; return
    case 'days_after_period_end': if (!int(r.days) || r.days < 0 || r.days > 366) return 'Days must be between 0 and 366'; return
    case 'fixed_date': if (!int(r.month) || r.month < 1 || r.month > 12) return 'Month must be between 1 and 12'; if (!int(r.day) || r.day < 1 || r.day > 31) return 'Day must be between 1 and 31'; if (!int(r.year_offset) || r.year_offset < 0 || r.year_offset > 2) return 'Years after must be 0, 1 or 2'; return
    case 'absolute_date': return /^\d{4}-\d{2}-\d{2}$/.test(r.date) && !Number.isNaN(Date.parse(r.date)) ? undefined : 'Enter a valid date'
    case 'days_after_event': return int(r.days) && r.days >= 0 && r.days <= 3650 ? undefined : 'Days must be between 0 and 3650'
  }
}
const ord = (n: number) => { const t = n % 100; const sfx = t >= 11 && t <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' } as Record<number, string>)[n % 10] ?? 'th'; return `${n}${sfx}` }
/** Plain-language reading of a stored rule, shown wherever a rule version is listed. */
export function describeDueRule(r: unknown): string {
  const x = r as Partial<DueRule> | null
  if (!x || typeof x !== 'object') return '—'
  switch (x.type) {
    case 'day_of_month': return x.month_offset === 0 ? `${ord(x.day!)} of the same month the period ends` : `${ord(x.day!)} of ${x.month_offset === 1 ? 'the month after' : `${x.month_offset} months after`} the period ends`
    case 'days_after_period_end': return `${x.days} day${x.days === 1 ? '' : 's'} after the period ends`
    case 'fixed_date': return `${ord(x.day!)} ${MONTHS[x.month! - 1]?.label ?? '?'}, ${x.year_offset === 0 ? 'in the year the period ends' : x.year_offset === 1 ? 'the year after' : `${x.year_offset} years after`}`
    case 'absolute_date': return `on ${x.date}`
    case 'days_after_event': return `${x.days} day${x.days === 1 ? '' : 's'} after the event`
    default: return '—'
  }
}
