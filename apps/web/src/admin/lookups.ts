import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import type { Option } from '../components/ui'
import type { FieldSpec, Lookup } from './spec'
import { useLovOptions } from '../hooks/useLookups'

/** Options for a reference field, read from the database (never hardcoded). RLS decides what the caller may see. */
export function useLookup(l: Lookup | undefined) {
  return useQuery({
    queryKey: ['lookup', l?.table, l?.value, l?.label, JSON.stringify(l?.filter ?? {})], enabled: !!l && !!supabase, staleTime: 60_000,
    queryFn: async (): Promise<Option[]> => {
      let q = supabase!.from(l!.table).select(`${l!.value},${l!.label}`).order(l!.order ?? l!.label).limit(500)
      for (const [k, v] of Object.entries(l!.filter ?? {})) q = q.eq(k, v)
      const { data, error } = await q; if (error) throw error
      return ((data ?? []) as unknown as Array<Record<string, unknown>>).map((r) => ({ value: String(r[l!.value]), label: String(r[l!.label]) }))
    },
  })
}
export function useFieldOptions(f: FieldSpec): Option[] {
  const lov = useLovOptions(f.lov); const look = useLookup(f.lookup)
  return f.options ?? lov.data ?? look.data ?? []
}
