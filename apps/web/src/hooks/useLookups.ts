import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import type { Option } from '../components/ui'

/** Options come from the database (LOV Designer / Status Designer), never from hardcoded business lists. */
export function useLovOptions(setCode: string | undefined) {
  return useQuery({
    queryKey: ['lov', setCode], enabled: !!setCode && !!supabase, staleTime: 5 * 60_000,
    queryFn: async (): Promise<Option[]> => {
      const { data, error } = await supabase!.from('lov_value').select('code,label,sort_order,lov_set!inner(code)').eq('lov_set.code', setCode!).eq('is_active', true).order('sort_order')
      if (error) throw error
      return (data ?? []).map((r) => ({ value: r.code as string, label: r.label as string }))
    },
  })
}
export function useStatusOptions(module: string | undefined) {
  return useQuery({
    queryKey: ['status-defs', module], enabled: !!module && !!supabase, staleTime: 5 * 60_000,
    queryFn: async (): Promise<Array<Option & { category: string; color: string | null }>> => {
      const { data, error } = await supabase!.from('status_definition').select('code,label,category,color,sort_order').eq('module', module!).eq('is_active', true).order('sort_order')
      if (error) throw error
      return (data ?? []).map((r) => ({ value: r.code as string, label: r.label as string, category: r.category as string, color: r.color as string | null }))
    },
  })
}
/** Transitions allowed from `from` for a module, with whether a reason is required. */
export function useTransitions(module: string, from: string) {
  return useQuery({
    queryKey: ['transitions', module, from], enabled: !!supabase, staleTime: 60_000,
    queryFn: async (): Promise<Array<{ to: string; label: string; requiresReason: boolean }>> => {
      const [{ data: t, error: e1 }, { data: s, error: e2 }] = await Promise.all([
        supabase!.from('status_transition').select('to_status,requires_reason').eq('module', module).eq('from_status', from).eq('is_active', true),
        supabase!.from('status_definition').select('code,label,sort_order').eq('module', module).eq('is_active', true).order('sort_order'),
      ])
      if (e1) throw e1; if (e2) throw e2
      const labels = new Map((s ?? []).map((r) => [r.code as string, r.label as string]))
      return (t ?? []).map((r) => ({ to: r.to_status as string, label: labels.get(r.to_status as string) ?? (r.to_status as string), requiresReason: !!r.requires_reason }))
    },
  })
}
