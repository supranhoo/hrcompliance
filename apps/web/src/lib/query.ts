import type { SupabaseClient } from '@supabase/supabase-js'

export type SortSpec = { id: string; desc: boolean }
export type FilterValue = string | number | boolean | null | Array<string | number>
export type PageQuery = {
  page: number            // 0-based
  pageSize: number
  sort?: SortSpec | null
  search?: string
  searchColumns?: string[]
  filters?: Record<string, FilterValue>
  /** Inclusive ranges, e.g. { due_date: { gte: '2026-10-01', lte: '2026-10-31' } } */
  ranges?: Record<string, { gte?: string; lte?: string }>
}
export type Page<T> = { rows: T[]; total: number }

const IDENT = /^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?$/
const assertIdent = (s: string) => { if (!IDENT.test(s)) throw new Error(`Invalid column identifier: ${s}`) }
/** PostgREST `or=` / ilike values: strip characters that carry syntax meaning so user text can never alter the filter. */
export const sanitizeSearch = (s: string) => s.replace(/[%*,()\\:"']/g, ' ').replace(/\s+/g, ' ').trim()

/**
 * Server-side page fetch. Never loads a full table: range() + exact count + filters/search/sort are all executed by PostgREST.
 * Column names are validated against an identifier pattern; values are passed as typed parameters.
 */
export async function fetchPage<T>(client: SupabaseClient, table: string, select: string, q: PageQuery): Promise<Page<T>> {
  assertIdent(table)
  const size = Math.min(Math.max(q.pageSize, 1), 200)
  let req = client.from(table).select(select, { count: 'exact' })
  for (const [col, val] of Object.entries(q.filters ?? {})) {
    assertIdent(col)
    if (val === '' || val === undefined) continue
    if (val === null) req = req.is(col, null)
    else if (Array.isArray(val)) { if (val.length) req = req.in(col, val) }
    else req = req.eq(col, val)
  }
  for (const [col, r] of Object.entries(q.ranges ?? {})) {
    assertIdent(col)
    if (r.gte) req = req.gte(col, r.gte)
    if (r.lte) req = req.lte(col, r.lte)
  }
  const term = sanitizeSearch(q.search ?? '')
  if (term && q.searchColumns?.length) {
    q.searchColumns.forEach(assertIdent)
    req = req.or(q.searchColumns.map((c) => `${c}.ilike.%${term}%`).join(','))
  }
  if (q.sort) { assertIdent(q.sort.id); req = req.order(q.sort.id, { ascending: !q.sort.desc, nullsFirst: false }) }
  const from = q.page * size
  const { data, error, count } = await req.range(from, from + size - 1)
  if (error) throw error
  return { rows: (data ?? []) as T[], total: count ?? 0 }
}
