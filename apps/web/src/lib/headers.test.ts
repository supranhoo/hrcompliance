// @vitest-environment node
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const file = readFileSync(new URL('../../public/_headers', import.meta.url), 'utf8')
const block = (path: string) => { const m = file.split(/\n(?=\/)/).find((b) => b.startsWith(path + '\n')); return m ?? '' }
const header = (b: string, name: string) => b.split('\n').map((l) => l.trim()).find((l) => l.toLowerCase().startsWith(name.toLowerCase() + ':'))?.slice(name.length + 1).trim()

describe('Cloudflare Pages security headers', () => {
  const all = block('/*')
  it('sets the baseline hardening headers on every path', () => {
    expect(header(all, 'X-Content-Type-Options')).toBe('nosniff'); expect(header(all, 'X-Frame-Options')).toBe('DENY'); expect(header(all, 'Referrer-Policy')).toBe('strict-origin-when-cross-origin')
    expect(header(all, 'Strict-Transport-Security')).toMatch(/max-age=\d{7,}/); expect(header(all, 'Permissions-Policy')).toMatch(/camera=\(\)/)
  })
  it('CSP: scripts only from the app, no eval, no framing, no plugins', () => {
    const csp = header(all, 'Content-Security-Policy')!
    expect(csp).toContain("script-src 'self'"); expect(csp).not.toMatch(/unsafe-eval|script-src[^;]*unsafe-inline|script-src[^;]*\*/); expect(csp).toContain("frame-ancestors 'none'"); expect(csp).toContain("object-src 'none'"); expect(csp).toContain("default-src 'self'")
  })
  it('CSP: the browser may only talk to the app origin and Supabase', () => {
    const connect = header(all, 'Content-Security-Policy')!.split(';').map((s) => s.trim()).find((s) => s.startsWith('connect-src'))!
    expect(connect).toContain("'self'"); expect(connect).toContain('https://*.supabase.co'); expect(connect.split(' ').filter((t) => /^https?:|^wss?:/.test(t)).every((t) => /supabase\.co$/.test(t))).toBe(true)
  })
  it('hashed assets are cached for a year, the HTML shell is never cached', () => {
    expect(header(block('/assets/*'), 'Cache-Control')).toMatch(/max-age=31536000.*immutable/); expect(header(block('/index.html'), 'Cache-Control')).toBe('no-cache')
  })
  it('the HTML shell has no inline script that the CSP would block', () => {
    const html = readFileSync(new URL('../../index.html', import.meta.url), 'utf8')
    expect(/<script(?![^>]*\bsrc=)[^>]*>/.test(html)).toBe(false); expect(html).not.toMatch(/\son[a-z]+=/)
  })
})
