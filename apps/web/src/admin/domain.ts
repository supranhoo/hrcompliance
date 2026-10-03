import type { Option } from '../components/ui'

/** STRUCTURAL enumerations that mirror database CHECK constraints (not business-configurable lists; changing them needs a migration).
 *  Business lists - risk, criticality, compliance type, categories, statuses, document types, alert offsets - always come from the database. */
export const FREQUENCIES: Option[] = ['daily', 'weekly', 'monthly', 'quarterly', 'half_yearly', 'annual', 'one_time', 'event_based', 'incident_based', 'custom']
  .map((v) => ({ value: v, label: v.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()) }))
export const PERIODIC = new Set(['daily', 'weekly', 'monthly', 'quarterly', 'half_yearly', 'annual'])
export const ACTIVE_OPTIONS: Option[] = [{ value: 'true', label: 'Active' }, { value: 'false', label: 'Inactive' }]
export const APPLICABILITY_STATUS: Option[] = [{ value: 'applicable', label: 'Applicable' }, { value: 'not_applicable', label: 'Not applicable' }, { value: 'conditional', label: 'Conditional' }]
export const MONTHS: Option[] = Array.from({ length: 12 }, (_, i) => ({ value: String(i + 1), label: new Date(2000, i, 1).toLocaleString('en', { month: 'long' }) }))
export const CODE_PATTERN = /^[A-Z0-9][A-Z0-9_.-]{1,39}$/
export const CODE_MESSAGE = 'Use capital letters, digits, dot, dash or underscore (2–40 characters)'
/** Structural: mirrors CHECK constraints on public.licence / public.licence_event. */
export const LICENCE_LIFECYCLE: Option[] = [{ value: 'active', label: 'Active' }, { value: 'surrendered', label: 'Surrendered' }, { value: 'cancelled', label: 'Cancelled' }]
export const LICENCE_EVENT_TYPES: Option[] = ['application_submitted', 'query_raised', 'query_replied', 'inspection', 'issued', 'renewal_applied', 'renewed', 'amended', 'expired', 'surrendered', 'cancelled', 'note']
  .map((v) => ({ value: v, label: v.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()) }))
