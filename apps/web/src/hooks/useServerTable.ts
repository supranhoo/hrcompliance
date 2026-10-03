import { useState } from 'react'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { fetchPage, type PageQuery } from '../lib/query'

/** Glue between SmartTable and PostgREST: query state in, one server page out. Search is debounced by the caller via key change. */
export function useServerTable<T>(table: string, select: string, opts: { searchColumns?: string[]; pageSize?: number; sort?: PageQuery['sort']; filters?: PageQuery['filters'] } = {}) {
  const [query, setQuery] = useState<PageQuery>({ page: 0, pageSize: opts.pageSize ?? 25, sort: opts.sort ?? null, search: '', searchColumns: opts.searchColumns, filters: opts.filters })
  const result = useQuery({
    queryKey: ['page', table, select, query],
    queryFn: () => { if (!supabase) throw new Error('Supabase is not configured'); return fetchPage<T>(supabase, table, select, query) },
    placeholderData: keepPreviousData,
  })
  return { query, setQuery, rows: result.data?.rows ?? [], total: result.data?.total ?? 0, isLoading: result.isLoading, error: result.error as Error | null, refetch: result.refetch }
}
