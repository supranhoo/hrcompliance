const KEY = 'auth:returnTo'

/** Only same-origin relative paths are accepted: blocks open redirects such as `//evil.com`, `https://…`, `/\evil.com`. */
export function safeReturnTo(raw: string | null | undefined): string {
  if (!raw || !raw.startsWith('/') || raw.startsWith('//') || raw.includes('\\') || [...raw].some((ch) => ch.charCodeAt(0) < 32)) return '/'
  if (raw.startsWith('/auth/') || raw === '/login' || raw === '/no-access') return '/'
  return raw
}
export const rememberReturnTo = (path: string) => { try { sessionStorage.setItem(KEY, safeReturnTo(path)) } catch { /* storage unavailable: fall back to / */ } }
export const takeReturnTo = (): string => {
  try { const v = sessionStorage.getItem(KEY); sessionStorage.removeItem(KEY); return safeReturnTo(v) } catch { return '/' }
}
