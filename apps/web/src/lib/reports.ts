export type Dimension = 'location' | 'department' | 'category' | 'risk' | 'domain' | 'owner' | 'month'
/** Whitelist mirrored by the database function; labels are display text only. */
export const DIMENSIONS: Array<{ value: Dimension; label: string }> = [
  { value: 'month', label: 'Month (by due date)' }, { value: 'location', label: 'Location' }, { value: 'department', label: 'Responsible department' },
  { value: 'category', label: 'Category' }, { value: 'risk', label: 'Risk level' }, { value: 'domain', label: 'Domain' }, { value: 'owner', label: 'Owner' },
]
export type PerfRow = { group_key: string; group_label: string; total: number; completed: number; completed_on_time: number; completed_late: number; overdue_open: number; upcoming_open: number; due_to_date: number; on_time_to_date: number; completed_to_date: number; on_time_pct: number | null; compliance_pct: number | null }

const iso = (d: Date) => d.toISOString().slice(0, 10)
/** Default report window: the last 12 months up to today. */
export function defaultWindow(today = new Date()): { from: string; to: string } {
  const f = new Date(Date.UTC(today.getUTCFullYear() - 1, today.getUTCMonth(), today.getUTCDate())); return { from: iso(f), to: iso(today) }
}
export function validateWindow(from: string, to: string): string | null {
  if (!from || !to) return 'Choose both dates'
  if (from > to) return 'The start date is after the end date'
  if ((Date.parse(to) - Date.parse(from)) / 86_400_000 > 3660) return 'Choose a period of at most 10 years'
  return null
}
/** Totals row. Percentages are recomputed from the summed counts, never averaged. */
export function totalsOf(rows: PerfRow[]): PerfRow {
  const s = (k: keyof PerfRow) => rows.reduce((a, r) => a + (Number(r[k]) || 0), 0)
  const due = s('due_to_date'); const pct = (n: number) => (due > 0 ? Math.round((1000 * n) / due) / 10 : null)
  return { group_key: 'total', group_label: 'Total', total: s('total'), completed: s('completed'), completed_on_time: s('completed_on_time'), completed_late: s('completed_late'), overdue_open: s('overdue_open'), upcoming_open: s('upcoming_open'),
    due_to_date: due, on_time_to_date: s('on_time_to_date'), completed_to_date: s('completed_to_date'), on_time_pct: pct(s('on_time_to_date')), compliance_pct: pct(s('completed_to_date')) }
}
export const pctText = (v: number | null | undefined) => (v === null || v === undefined ? '—' : `${v.toFixed(1)}%`)
/** Bar width for a percentage cell (presentation only). */
export const pctWidth = (v: number | null | undefined) => `${Math.max(0, Math.min(100, v ?? 0))}%`
export type PipelineRow = { bucket: string; licence_type_code: string; licence_type_name: string; licences: number }
/** Pivot: one row per bucket (expired first, then months), counts per licence type. */
export function pivotPipeline(rows: PipelineRow[]): { types: Array<{ code: string; name: string }>; lines: Array<{ bucket: string; counts: Record<string, number>; total: number }> } {
  const types = [...new Map(rows.map((r) => [r.licence_type_code, r.licence_type_name])).entries()].map(([code, name]) => ({ code, name })).sort((a, b) => a.code.localeCompare(b.code))
  const buckets = [...new Set(rows.map((r) => r.bucket))].sort((a, b) => (a === 'expired' ? -1 : b === 'expired' ? 1 : a.localeCompare(b)))
  return { types, lines: buckets.map((b) => { const counts: Record<string, number> = {}; let total = 0; for (const r of rows.filter((x) => x.bucket === b)) { counts[r.licence_type_code] = Number(r.licences); total += Number(r.licences) } return { bucket: b, counts, total } }) }
}
