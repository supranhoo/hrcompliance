import { isoDate } from './urlFilters'

export type CalItem = { instance_id: string; instance_no: string; compliance_code: string; compliance_name: string; location_code: string; due_date: string; status: string; due_state: string; risk_level: string }

/** Monday-first 6x7 month matrix (always 42 cells so the grid never jumps height). */
export function monthMatrix(year: number, month0: number): Date[] {
  const first = new Date(year, month0, 1)
  const lead = (first.getDay() + 6) % 7
  return Array.from({ length: 42 }, (_, i) => new Date(year, month0, 1 - lead + i))
}
export function weekDays(anchor: Date): Date[] {
  const lead = (anchor.getDay() + 6) % 7
  return Array.from({ length: 7 }, (_, i) => new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() - lead + i))
}
export function groupByDate(items: CalItem[]): Map<string, CalItem[]> {
  const m = new Map<string, CalItem[]>()
  for (const it of items) { const a = m.get(it.due_date); if (a) a.push(it); else m.set(it.due_date, [it]) }
  return m
}
export const rangeFor = (view: 'month' | 'week' | 'agenda', anchor: Date): { from: string; to: string } => {
  if (view === 'month') { const g = monthMatrix(anchor.getFullYear(), anchor.getMonth()); return { from: isoDate(g[0]), to: isoDate(g[41]) } }
  if (view === 'week') { const w = weekDays(anchor); return { from: isoDate(w[0]), to: isoDate(w[6]) } }
  const end = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() + 60)
  return { from: isoDate(anchor), to: isoDate(end) }
}
export const shift = (view: 'month' | 'week' | 'agenda', anchor: Date, dir: -1 | 1): Date =>
  view === 'month' ? new Date(anchor.getFullYear(), anchor.getMonth() + dir, 1) : new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate() + dir * (view === 'week' ? 7 : 30))
/** Worst state in a day, for the compact month cell colour. */
export const worstState = (items: CalItem[]): string => (['overdue', 'due_soon', 'upcoming', 'completed', 'not_applicable'].find((s) => items.some((i) => i.due_state === s)) ?? 'upcoming')
