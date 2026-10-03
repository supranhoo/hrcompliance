/** Drill-down contract: dashboard tiles link to registers as /path?due_state=overdue&due_within=30. Only whitelisted keys become filters. */
export function filtersFromSearch(search: string, allowed: readonly string[]): Record<string, string> {
  const q = new URLSearchParams(search)
  const out: Record<string, string> = {}
  for (const k of allowed) { const v = q.get(k); if (v && /^[A-Za-z0-9_.:-]{1,64}$/.test(v)) out[k] = v }
  return out
}
export function searchFromFilters(filters: Record<string, string | undefined>): string {
  const q = new URLSearchParams()
  for (const [k, v] of Object.entries(filters)) if (v) q.set(k, v)
  const s = q.toString()
  return s ? `?${s}` : ''
}
export const isoDate = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
/** { gte: today, lte: today + n } as ISO dates, for "next N days" drill-downs. */
export function nextDaysRange(n: number, today = new Date()) {
  const end = new Date(today.getFullYear(), today.getMonth(), today.getDate() + n)
  return { gte: isoDate(today), lte: isoDate(end) }
}
