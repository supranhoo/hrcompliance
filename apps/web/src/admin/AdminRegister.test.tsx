import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  perms: new Set<string>(['compliance.manage']),
  calls: [] as Array<{ op: string; table: string; payload?: unknown; filters: Array<[string, unknown]> }>,
  updateResult: { data: { id: 'c1' } as unknown, error: null as unknown },
  rows: [{ id: 'c1', row_version: 3, code: 'PF-MONTHLY', name: 'PF', description: null, domain: null, category_id: null, category_name: null, law_id: null, law_name: null, section_reference: null, legal_source: null, last_reviewed_at: null, owner_department_id: null, department_name: null, default_owner_user_id: null, owner_email: null, is_active: true, effective_from: null, effective_to: null, active_version: 1, active_frequency: 'monthly', active_risk: 'high', version_count: 1, draft_count: 0 }],
}))
vi.mock('../hooks/useServerTable', () => ({ useServerTable: () => ({ query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: h.rows, total: 1, isLoading: false, error: null, refetch: vi.fn() }) }))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('./lookups', () => ({ useFieldOptions: () => [], useLookup: () => ({ data: [] }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../pages/quickviews', () => ({ AuditTab: () => <p>audit history</p> }))
vi.mock('../lib/supabase', () => {
  const chain = (op: string, table: string, payload?: unknown) => {
    const rec = { op, table, payload, filters: [] as Array<[string, unknown]> }; h.calls.push(rec)
    const c: Record<string, unknown> = {}
    c.eq = (k: string, v: unknown) => { rec.filters.push([k, v]); return c }
    c.select = () => c
    c.single = async () => ({ data: { id: 'new' }, error: null })
    c.maybeSingle = async () => h.updateResult
    return c
  }
  return { supabase: { from: (t: string) => ({ insert: (p: unknown) => chain('insert', t, p), update: (p: unknown) => chain('update', t, p) }) }, appEnv: 'test' }
})
import { AdminRegister } from './AdminRegister'
import { ToastProvider } from '../app/Toasts'
import { complianceMasterSpec } from './masters'

const setup = () => render(<QueryClientProvider client={new QueryClient()}><ToastProvider><MemoryRouter><AdminRegister spec={complianceMasterSpec} /></MemoryRouter></ToastProvider></QueryClientProvider>)

describe('AdminRegister (Compliance Master)', () => {
  beforeEach(() => { h.calls.length = 0; h.perms = new Set(['compliance.manage']); h.updateResult = { data: { id: 'c1' }, error: null } })
  it('shows the register and the New button only to users who can manage', () => {
    setup(); expect(screen.getByText('PF-MONTHLY')).toBeInTheDocument(); expect(screen.getByRole('button', { name: 'New compliance' })).toBeInTheDocument()
  })
  it('hides create/edit controls for read-only users (RLS is still the authority)', () => {
    h.perms = new Set(['compliance.read']); setup(); expect(screen.queryByRole('button', { name: 'New compliance' })).toBeNull()
    fireEvent.click(screen.getByText('PF-MONTHLY')); expect(screen.queryByRole('button', { name: 'Edit' })).toBeNull()
  })
  it('blocks an empty create on the frontend: required messages, no request', async () => {
    setup(); fireEvent.click(screen.getByRole('button', { name: 'New compliance' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Create compliance' }))
    expect(await screen.findByText('Code is required')).toBeInTheDocument(); expect(screen.getByText('Name is required')).toBeInTheDocument()
    expect(h.calls).toHaveLength(0)
  })
  it('rejects a malformed code before it reaches the database', async () => {
    setup(); fireEvent.click(screen.getByRole('button', { name: 'New compliance' }))
    fireEvent.change(await screen.findByLabelText(/^Code/), { target: { value: 'pf monthly' } }); fireEvent.change(screen.getByLabelText(/^Name/), { target: { value: 'PF' } })
    fireEvent.click(screen.getByRole('button', { name: 'Create compliance' }))
    expect(await screen.findByText(/capital letters/)).toBeInTheDocument(); expect(h.calls).toHaveLength(0)
  })
  it('creates through the base table with a clean payload (no view-only columns)', async () => {
    setup(); fireEvent.click(screen.getByRole('button', { name: 'New compliance' }))
    fireEvent.change(await screen.findByLabelText(/^Code/), { target: { value: 'esic-monthly' } }); fireEvent.change(screen.getByLabelText(/^Name/), { target: { value: 'ESIC monthly' } })
    fireEvent.click(screen.getByRole('button', { name: 'Create compliance' }))
    await waitFor(() => expect(h.calls).toHaveLength(1))
    expect(h.calls[0]).toMatchObject({ op: 'insert', table: 'compliance_master' })
    const p = h.calls[0].payload as Record<string, unknown>
    expect(p.code).toBe('ESIC-MONTHLY'); expect(p.name).toBe('ESIC monthly'); expect(p.is_active).toBe(true); expect(p.description).toBeNull()
    for (const k of ['category_name', 'law_name', 'active_version', 'version_count', 'id', 'row_version']) expect(p).not.toHaveProperty(k)
  })
  it('edit: code is locked, update is guarded by row_version, code is not sent', async () => {
    setup(); fireEvent.click(screen.getByText('PF-MONTHLY')); fireEvent.click(await screen.findByRole('button', { name: 'Edit' }))
    expect(screen.getByLabelText(/^Code/)).toBeDisabled()
    fireEvent.change(screen.getByLabelText(/^Name/), { target: { value: 'Provident Fund' } }); fireEvent.click(screen.getByRole('button', { name: 'Save changes' }))
    await waitFor(() => expect(h.calls).toHaveLength(1))
    expect(h.calls[0]).toMatchObject({ op: 'update', table: 'compliance_master' }); expect(h.calls[0].payload).not.toHaveProperty('code')
    expect(h.calls[0].filters).toEqual([['id', 'c1'], ['row_version', 3]])
  })
  it('a concurrent change (no row matched) is reported, not silently overwritten', async () => {
    h.updateResult = { data: null, error: null }
    setup(); fireEvent.click(screen.getByText('PF-MONTHLY')); fireEvent.click(await screen.findByRole('button', { name: 'Edit' }))
    fireEvent.click(screen.getByRole('button', { name: 'Save changes' }))
    expect(await screen.findByText(/changed by someone else/)).toBeInTheDocument()
  })
  it('database errors are shown in plain language', async () => {
    h.updateResult = { data: null, error: { code: '42501', message: 'the code of a compliance master is its identity and cannot be changed' } }
    setup(); fireEvent.click(screen.getByText('PF-MONTHLY')); fireEvent.click(await screen.findByRole('button', { name: 'Edit' }))
    fireEvent.click(screen.getByRole('button', { name: 'Save changes' }))
    expect(await screen.findByText(/identity and cannot be changed/)).toBeInTheDocument()
  })
  it('details link to rule versions and applicability; history tab is available', async () => {
    setup(); fireEvent.click(screen.getByText('PF-MONTHLY'))
    expect(await screen.findByRole('link', { name: /Manage rule versions/ })).toHaveAttribute('href', '/admin/rule-versions?compliance_code=PF-MONTHLY')
    fireEvent.click(screen.getByRole('tab', { name: 'History' })); expect(screen.getByText('audit history')).toBeInTheDocument()
  })
})
