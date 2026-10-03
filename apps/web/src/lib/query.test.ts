import { describe, expect, it, vi } from 'vitest'
import type { SupabaseClient } from '@supabase/supabase-js'
import { fetchPage, sanitizeSearch } from './query'

function mockClient(result = { data: [{ id: 1 }], error: null, count: 42 }) {
  const calls: Array<[string, unknown[]]> = []
  const chain: Record<string, unknown> = {}
  for (const m of ['select', 'eq', 'is', 'in', 'or', 'order']) chain[m] = (...a: unknown[]) => { calls.push([m, a]); return chain }
  chain.range = vi.fn((...a: unknown[]) => { calls.push(['range', a]); return Promise.resolve(result) })
  return { client: { from: (t: string) => { calls.push(['from', [t]]); return chain } } as unknown as SupabaseClient, calls }
}

describe('fetchPage', () => {
  it('requests exactly one server page with an exact count', async () => {
    const { client, calls } = mockClient()
    const r = await fetchPage(client, 'app_user', 'id', { page: 2, pageSize: 25 })
    expect(r).toEqual({ rows: [{ id: 1 }], total: 42 })
    expect(calls).toContainEqual(['select', ['id', { count: 'exact' }]])
    expect(calls).toContainEqual(['range', [50, 74]])
  })
  it('caps page size so a client cannot request the whole table', async () => {
    const { client, calls } = mockClient()
    await fetchPage(client, 'app_user', 'id', { page: 0, pageSize: 100000 })
    expect(calls).toContainEqual(['range', [0, 199]])
  })
  it('pushes filters, search and sort to the server', async () => {
    const { client, calls } = mockClient()
    await fetchPage(client, 'app_user', 'id', { page: 0, pageSize: 10, filters: { status: 'active', role: ['a', 'b'], deleted: null, empty: '' }, search: 'ravi', searchColumns: ['email', 'full_name'], sort: { id: 'email', desc: true } })
    expect(calls).toContainEqual(['eq', ['status', 'active']])
    expect(calls).toContainEqual(['in', ['role', ['a', 'b']]])
    expect(calls).toContainEqual(['is', ['deleted', null]])
    expect(calls.find((c) => c[0] === 'eq' && c[1][0] === 'empty')).toBeUndefined()
    expect(calls).toContainEqual(['or', ['email.ilike.%ravi%,full_name.ilike.%ravi%']])
    expect(calls).toContainEqual(['order', ['email', { ascending: false, nullsFirst: false }]])
  })
  it('rejects injected column identifiers', async () => {
    const { client } = mockClient()
    await expect(fetchPage(client, 'app_user', 'id', { page: 0, pageSize: 10, filters: { 'status;drop table x': 'a' } })).rejects.toThrow(/Invalid column/)
    await expect(fetchPage(client, 'app_user', 'id', { page: 0, pageSize: 10, sort: { id: 'a,b', desc: false } })).rejects.toThrow(/Invalid column/)
    await expect(fetchPage(client, 'users; --', 'id', { page: 0, pageSize: 10 })).rejects.toThrow(/Invalid column/)
  })
  it('propagates server errors', async () => {
    const { client } = mockClient({ data: null as never, error: new Error('rls') as never, count: 0 })
    await expect(fetchPage(client, 'app_user', 'id', { page: 0, pageSize: 10 })).rejects.toThrow('rls')
  })
})

describe('sanitizeSearch', () => {
  it('strips PostgREST syntax characters', () => {
    expect(sanitizeSearch(`a,b.eq.(c)%*"x'`)).toBe('a b.eq. c x')
    expect(sanitizeSearch('  ')).toBe('')
  })
  it('never lets user text add a filter clause', async () => {
    const { client, calls } = mockClient()
    await fetchPage(client, 't', 'id', { page: 0, pageSize: 5, search: 'x),status.eq.admin,(y', searchColumns: ['email'] })
    const or = calls.find((c) => c[0] === 'or')![1][0] as string
    expect(or).toBe('email.ilike.%x status.eq.admin y%')
  })
})
