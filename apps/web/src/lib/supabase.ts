import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { parseEnv } from './env'

const parsed = parseEnv(import.meta.env as Record<string, unknown>)
export const envErrors = parsed.ok ? [] : parsed.errors
export const appEnv = parsed.ok ? parsed.env.VITE_APP_ENV : 'development'
/** Browser client: publishable key only. PKCE flow; the callback route exchanges the code explicitly (see AuthCallbackPage). */
export const supabase: SupabaseClient | null = parsed.ok
  ? createClient(parsed.env.VITE_SUPABASE_URL, parsed.env.VITE_SUPABASE_PUBLISHABLE_KEY, {
      auth: { flowType: 'pkce', persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
    })
  : null
export const callbackUrl = () => `${window.location.origin}/auth/callback`
