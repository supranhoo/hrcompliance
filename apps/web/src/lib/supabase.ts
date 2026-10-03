import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { parseEnv } from './env'

const parsed = parseEnv(import.meta.env as Record<string, unknown>)
export const envErrors = parsed.ok ? [] : parsed.errors
export const appEnv = parsed.ok ? parsed.env.VITE_APP_ENV : 'development'
export const supabase: SupabaseClient | null = parsed.ok
  ? createClient(parsed.env.VITE_SUPABASE_URL, parsed.env.VITE_SUPABASE_ANON_KEY)
  : null
