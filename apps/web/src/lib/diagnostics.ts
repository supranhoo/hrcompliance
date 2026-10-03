/** Safe, non-secret facts about the current session for support. NEVER includes the token itself or any signature part. */
export type SafeClaims = { role?: string; aal?: string; sub?: string; exp?: number; aud?: string }

export function decodeSafeClaims(token: string | undefined | null): SafeClaims | null {
  if (!token) return null
  const part = token.split('.')[1]
  if (!part) return null
  try {
    const json = JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=')))
    const aud = typeof json.aud === 'string' ? json.aud : Array.isArray(json.aud) ? String(json.aud[0]) : undefined
    return { role: json.role, aal: json.aal, sub: json.sub, exp: json.exp, aud }
  } catch { return null }
}

export type AccessResult = 'loading' | 'profile' | 'empty' | 'error' | 'no_session'
export type DiagnosticsReport = {
  at: string; build: string; env: string; origin: string; supabaseHost: string | null
  accessResult: AccessResult; accessError: string | null
  session: null | { userId: string; email: string | null; providers: string[]; tokenRole?: string; tokenSubMatchesUser: boolean; expiresInSeconds: number | null }
}
const hostOf = (u?: string): string | null => { try { return u ? new URL(u).host : null } catch { return null } }
export function buildReport(i: { build: string; env: string; origin: string; supabaseUrl?: string; accessResult: AccessResult; accessError: string | null;
  user: { id: string; email?: string | null; app_metadata?: { provider?: string; providers?: string[] } } | null; accessToken?: string | null; now?: number }): DiagnosticsReport {
  const claims = decodeSafeClaims(i.accessToken)
  const now = i.now ?? Date.now()
  const host = hostOf(i.supabaseUrl)
  return {
    at: new Date(now).toISOString(), build: i.build, env: i.env, origin: i.origin, supabaseHost: host,
    accessResult: i.user ? i.accessResult : 'no_session', accessError: i.accessError,
    session: i.user ? {
      userId: i.user.id, email: i.user.email ?? null,
      providers: i.user.app_metadata?.providers ?? (i.user.app_metadata?.provider ? [i.user.app_metadata.provider] : []),
      tokenRole: claims?.role, tokenSubMatchesUser: claims?.sub === i.user.id,
      expiresInSeconds: claims?.exp ? Math.round(claims.exp - now / 1000) : null,
    } : null,
  }
}
