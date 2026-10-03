import { describe, expect, it } from 'vitest'
import { parseEnv } from './env'
import { can, parseAccess } from './access'

describe('parseEnv', () => {
  it('accepts a valid config', () => {
    const r = parseEnv({ VITE_SUPABASE_URL: 'https://x.supabase.co', VITE_SUPABASE_ANON_KEY: 'k' })
    expect(r.ok).toBe(true)
  })
  it('reports missing values without throwing', () => {
    const r = parseEnv({})
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.errors.length).toBe(2)
  })
  it('rejects unknown environment names', () => {
    expect(parseEnv({ VITE_SUPABASE_URL: 'https://x.co', VITE_SUPABASE_ANON_KEY: 'k', VITE_APP_ENV: 'staging' }).ok).toBe(false)
  })
})

describe('parseAccess / can', () => {
  it('treats an empty object as unprovisioned', () => {
    expect(parseAccess({})).toBeNull()
    expect(can(parseAccess({}), 'master.read')).toBe(false)
  })
  it('parses a provisioned profile and checks permissions', () => {
    const a = parseAccess({ user_id: 'u', email: 'a@b.c', full_name: null, scope_all: true, roles: ['VIEWER'], permissions: ['master.read'], scopes: [] })
    expect(can(a, 'master.read')).toBe(true)
    expect(can(a, 'master.write')).toBe(false)
  })
  it('rejects malformed payloads', () => {
    expect(() => parseAccess({ user_id: 1 })).toThrow()
  })
})
