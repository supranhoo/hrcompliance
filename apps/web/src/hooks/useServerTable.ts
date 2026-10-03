import { useState } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { fetchPage, type FilterValue, type PageQuery } from '../lib/query'

type Opts = {
  searchColumns?: string[]; pageSize?: number; sort?: PageQuery['sort']
  /** Owned by the caller (URL): changing them resets to page 1. */
  filters?: Record<string, FilterValue>; ranges?: PageQuery['ranges']; initialSearch?: string
}

/** Server-driven table state. Paging/sort/search live here; filters come from the caller (the URL) so drill-down links are shareable. */
export function useServerTable<T>(table: string, select: string, opts: Opts = {}) {
  const filterKey = JSON.stringify([opts.filters ?? {}, opts.ranges ?? {}])
  const [state, setState] = useState<{ page: number; pageSize: number; sort: PageQuery['sort']; search: string; forKey: string }>({
    page: 0, pageSize: opts.pageSize ?? 25, sort: opts.sort ?? null, search: opts.initialSearch ?? '', forKey: filterKey,
  })
  const page = state.forKey === filterKey ? state.page : 0          // filters changed -> back to page 1
  const query: PageQuery = { page, pageSize: state.pageSize, sort: state.sort, search: state.search, searchColumns: opts.searchColumns, filters: opts.filters, ranges: opts.ranges }
  const setQuery = (q: PageQuery) => setState({ page: q.page, pageSize: q.pageSize, sort: q.sort ?? null, search: q.search ?? '', forKey: filterKey })
  const result = useQuery({
    queryKey: ['page', table, select, query],
    queryFn: () => { if (!supabase) throw new Error('Supabase is not configured'); return fetchPage<T>(supabase, table, select, query) },
    placeholderData: keepPreviousData,
  })
  return { query, setQuery, rows: result.data?.rows ?? [], total: result.data?.total ?? 0, isLoading: result.isLoading, error: result.error as Error | null, refetch: result.refetch }
}
