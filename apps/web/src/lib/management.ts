import { z } from 'zod'

const n = z.number()
const pct = z.number().nullable()
/** Mirrors public.management_dashboard() (migration 0038). Parsing rejects malformed payloads instead of rendering guesses. */
export const managementSchema = z.object({
  generated_at: z.string(),
  period: z.object({ from: z.string(), to: z.string() }),
  filters: z.object({ entity_id: z.string().nullable(), location_id: z.string().nullable(), department_id: z.string().nullable() }),
  top_risk_level: z.string().nullable(), top_severity: z.string().nullable(),
  kpis: z.object({
    total_applicable: n, due_this_month: n, overdue: n, critical_open: n, critical_overdue: n, due_to_date: n, completed_to_date: n, on_time_to_date: n,
    compliance_pct: pct, on_time_pct: pct, open_exceptions: n, critical_exceptions: n, licences_expiring: n, licences_expired: n,
  }),
  licences: z.object({ expiring: n, expired: n, horizon_days: n, department_filter_applies: z.boolean() }),
  trend: z.array(z.object({ month: z.string(), due: n, completed_on_time: n, completed_late: n, overdue_open: n, upcoming_open: n, due_to_date: n, compliance_pct: pct })),
  risk: z.array(z.object({ level: z.string(), label: z.string(), sort_order: n, open: n, overdue: n })),
  by_location: z.array(z.object({ code: z.string(), name: z.string().nullable(), total: n, open: n, overdue: n, due_to_date: n, completed_to_date: n, compliance_pct: pct })),
  by_department: z.array(z.object({ id: z.string().nullable(), name: z.string(), total: n, open: n, overdue: n, due_to_date: n, completed_to_date: n, compliance_pct: pct })),
  upcoming: z.array(z.object({ instance_no: z.string(), compliance_code: z.string(), compliance_name: z.string(), location_code: z.string(), due_date: z.string(), risk_level: z.string(), due_state: z.string() })),
  critical_exceptions: z.array(z.object({ id: z.string(), exception_no: z.string(), category: z.string(), severity: z.string(), description: z.string().nullable(), age_days: n, target_breached: z.boolean(), location_code: z.string().nullable() })),
  exception_ageing: z.record(z.string(), n),
  definitions: z.record(z.string(), z.string()),
})
export type Management = z.infer<typeof managementSchema>

export type PeriodPreset = '3m' | '6m' | '12m' | 'ytd' | 'custom'
export const PERIOD_PRESETS: Array<{ value: PeriodPreset; label: string }> = [
  { value: '3m', label: 'Last 3 months' }, { value: '6m', label: 'Last 6 months' }, { value: '12m', label: 'Last 12 months' }, { value: 'ytd', label: 'Year to date' }, { value: 'custom', label: 'Custom dates' },
]
const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
/** Calendar-based windows ending today. “Year to date” is the calendar year; no financial-year rule is assumed. */
export function periodFor(preset: PeriodPreset, today = new Date()): { from: string; to: string } {
  const back = (months: number) => iso(new Date(today.getFullYear(), today.getMonth() - months, today.getDate()))
  switch (preset) {
    case '3m': return { from: back(3), to: iso(today) }
    case '6m': return { from: back(6), to: iso(today) }
    case 'ytd': return { from: `${today.getFullYear()}-01-01`, to: iso(today) }
    default: return { from: back(12), to: iso(today) }
  }
}

export type DashFilters = { entity: string; location: string; department: string; preset: PeriodPreset; from: string; to: string }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const DATE = /^\d{4}-\d{2}-\d{2}$/
/** Filters live in the URL so a dashboard view can be shared and bookmarked; anything malformed is ignored. */
export function filtersFromParams(p: URLSearchParams, today = new Date()): DashFilters {
  const id = (k: string) => { const v = p.get(k) ?? ''; return UUID.test(v) ? v : '' }
  const presetRaw = p.get('period') as PeriodPreset | null
  const preset: PeriodPreset = presetRaw && PERIOD_PRESETS.some((x) => x.value === presetRaw) ? presetRaw : '12m'
  const custom = preset === 'custom' && DATE.test(p.get('from') ?? '') && DATE.test(p.get('to') ?? '')
  const w = custom ? { from: p.get('from')!, to: p.get('to')! } : periodFor(preset === 'custom' ? '12m' : preset, today)
  return { entity: id('entity'), location: id('location'), department: id('department'), preset: custom ? 'custom' : preset === 'custom' ? '12m' : preset, ...w }
}
export function paramsFromFilters(f: DashFilters): URLSearchParams {
  const q = new URLSearchParams()
  if (f.entity) q.set('entity', f.entity); if (f.location) q.set('location', f.location); if (f.department) q.set('department', f.department)
  if (f.preset !== '12m') q.set('period', f.preset)
  if (f.preset === 'custom') { q.set('from', f.from); q.set('to', f.to) }
  return q
}
export function validateDashPeriod(from: string, to: string): string | null {
  if (!DATE.test(from) || !DATE.test(to)) return 'Choose both dates'
  if (from > to) return 'The start date is after the end date'
  if ((Date.parse(to) - Date.parse(from)) / 86_400_000 > 3660) return 'Choose a period of at most 10 years'
  return null
}

/** Drill-downs into the existing registers, carrying the dashboard's entity / location / department filters where the register supports them. */
export function drillTo(base: string, f: Pick<DashFilters, 'entity' | 'location' | 'department'>, extra: Record<string, string> = {}, opts: { department?: boolean; location?: boolean } = {}): string {
  const q = new URLSearchParams(extra)
  if (f.entity) q.set('entity_id', f.entity)
  if (f.location && opts.location !== false) q.set('location_id', f.location)
  if (f.department && opts.department !== false) q.set(base === '/compliance' ? 'owner_department_id' : 'department_id', f.department)
  const s = q.toString(); return s ? `${base}?${s}` : base
}
export const pctOf = (num: number, den: number): number | null => (den > 0 ? Math.round((1000 * num) / den) / 10 : null)
