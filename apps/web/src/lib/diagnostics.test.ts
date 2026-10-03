import { describe, expect, it } from 'vitest'
import { buildReport, decodeSafeClaims } from './diagnostics'
import { can, parseAccess } from './access'
import sample from './my_access.sample.json'

const b64 = (o: object) => btoa(JSON.stringify(o)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_')
const token = (c: object) => `${b64({ alg: 'HS256' })}.${b64(c)}.SIGNATURE_MUST_NEVER_APPEAR`

describe('real my_access() payload (generated from the migrations) is accepted by the frontend', () => {
  it('parses a SUPER_ADMIN profile into a usable Access object', () => {
    const a = parseAccess(sample)
    expect(a).not.toBeNull()
    expect(a!.roles).toEqual(['SUPER_ADMIN'])
    for (const p of ['user.read', 'health.read', 'config.write', 'master.read']) expect(can(a, p)).toBe(true)
  })
  it('an empty object is the ONLY thing that means "not provisioned"', () => { expect(parseAccess({})).toBeNull() })
})

describe('safe diagnostics', () => {
  it('decodes only non-secret claims', () => {
    const c = decodeSafeClaims(token({ role: 'authenticated', sub: 'u1', exp: 2_000_000_000, email: 'x@y.z', aud: 'authenticated', secret_like: 'zzz' }))
    expect(c).toEqual({ role: 'authenticated', aal: undefined, sub: 'u1', exp: 2_000_000_000, aud: 'authenticated' })
    expect(JSON.stringify(c)).not.toContain('zzz')
  })
  it('is null-safe for garbage', () => { expect(decodeSafeClaims('nope')).toBeNull(); expect(decodeSafeClaims(null)).toBeNull(); expect(decodeSafeClaims('a.!!!.c')).toBeNull() })
  it('report never contains the token, signature or key material', () => {
    const t = token({ role: 'authenticated', sub: 'user-1', exp: 4_000_000_000 })
    const r = buildReport({ build: '0.2.0', env: 'development', origin: 'https://hrcompliance.pages.dev', supabaseUrl: 'https://abc.supabase.co/', accessResult: 'empty', accessError: null,
      user: { id: 'user-1', email: 'a@b.c', app_metadata: { provider: 'google', providers: ['google'] } }, accessToken: t, now: 1_000_000_000_000 })
    const text = JSON.stringify(r)
    expect(text).not.toContain('SIGNATURE_MUST_NEVER_APPEAR'); expect(text).not.toContain(t.split('.')[1])
    expect(r.supabaseHost).toBe('abc.supabase.co')
    expect(r.session).toMatchObject({ userId: 'user-1', providers: ['google'], tokenRole: 'authenticated', tokenSubMatchesUser: true })
    expect(r.accessResult).toBe('empty')
  })
  it('flags a token whose subject differs from the session user', () => {
    const r = buildReport({ build: 'x', env: 'e', origin: 'o', accessResult: 'profile', accessError: null, user: { id: 'A' }, accessToken: token({ sub: 'B', role: 'anon' }) })
    expect(r.session?.tokenSubMatchesUser).toBe(false)
  })
  it('reports no_session when signed out', () => {
    expect(buildReport({ build: 'x', env: 'e', origin: 'o', accessResult: 'loading', accessError: null, user: null }).accessResult).toBe('no_session')
  })
})
