import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { dashboardSchema } from '../lib/dashboard'

export function useDashboard() {
  return useQuery({
    queryKey: ['dashboard'], refetchInterval: 5 * 60_000,
    queryFn: async () => {
      if (!supabase) throw new Error('Supabase is not configured')
      const { data, error } = await supabase.rpc('compliance_dashboard')
      if (error) throw error
      return dashboardSchema.parse(data)
    },
  })
}
