import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { parseAccess, type Access } from '../lib/access'

type AuthState = {
  status: 'loading' | 'signed_out' | 'unauthorized' | 'ready' | 'error'
  session: Session | null
  access: Access | null
  signInWithGoogle: () => Promise<void>
  signOut: () => Promise<void>
}
const Ctx = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient()
  const [session, setSession] = useState<Session | null>(null)
  const [booted, setBooted] = useState(!supabase)

  useEffect(() => {
    if (!supabase) return
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setBooted(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => { setSession(s); qc.removeQueries({ queryKey: ['access'] }) })
    return () => sub.subscription.unsubscribe()
  }, [qc])

  const accessQ = useQuery({
    queryKey: ['access', session?.user.id],
    enabled: !!session && !!supabase,
    queryFn: async () => {
      const { data, error } = await supabase!.rpc('my_access')
      if (error) throw error
      return parseAccess(data)
    },
  })

  let status: AuthState['status'] = 'loading'
  if (booted && !session) status = 'signed_out'
  else if (session && accessQ.isError) status = 'error'
  else if (session && accessQ.isSuccess) status = accessQ.data ? 'ready' : 'unauthorized'

  const value: AuthState = {
    status, session, access: accessQ.data ?? null,
    signInWithGoogle: async () => {
      await supabase?.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } })
    },
    signOut: async () => { await supabase?.auth.signOut(); qc.clear() },
  }
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useAuth() {
  const v = useContext(Ctx)
  if (!v) throw new Error('useAuth must be used inside AuthProvider')
  return v
}
