import { z } from 'zod'

const schema = z.object({
  VITE_SUPABASE_URL: z.string().url(),
  VITE_SUPABASE_ANON_KEY: z.string().min(1),
  VITE_APP_ENV: z.enum(['development', 'uat', 'production']).default('development'),
})
export type AppEnv = z.infer<typeof schema>

/** Parses public env. Returns an error list instead of throwing so the UI can show a clear configuration error. */
export function parseEnv(raw: Record<string, unknown>): { ok: true; env: AppEnv } | { ok: false; errors: string[] } {
  const r = schema.safeParse(raw)
  if (r.success) return { ok: true, env: r.data }
  return { ok: false, errors: r.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`) }
}
