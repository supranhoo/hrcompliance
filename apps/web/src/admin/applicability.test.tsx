import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  perms: new Set<string>(['compliance.manage']), rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, inserts: [] as unknown[], updates: [] as Array<{ payload: unknown; filters: Array<[string, unknown]> }>, rows: [] as Array<Record<string, unknown>>,
}))
const base = { compliance_id: 'c1', compliance_code: 'FACT-1', compliance_name: 'Factories', entity_id: null, entity_code: null, location_id: 'l1', location_code: 'PLANT-A', location_name: 'Plant A', business_unit_id: null, business_unit_name: null, state: null,
  establishment_type: null, industry: null, employee_headcount_min: null, employee_headcount_max: null, contractor_headcount_min: null, contractor_headcount_max: null, condition: null, reason: null, source_reference: null, effective_to: null, is_active: true, row_version: 4 }
vi.mock('../hooks/useServerTable', () => ({ useServerTable: () => ({ query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: h.rows, total: h.rows.length, isLoading: false, error: null, refetch: vi.fn() }) }))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('./lookups', () => ({ useFieldOptions: (f: { key: string }) => (f.key === 'compliance_id' ? [{ value: 'c1', label: 'FACT-1' }] : f.key === 'location_id' ? [{ value: 'l1', label: 'PLANT-A' }] : f.key === 'status' ? [{ value: 'applicable', label: 'Applicable' }, { value: 'not_applicable', label: 'Not applicable' }, { value: 'conditional', label: 'Conditional' }] : []), useLookup: () => ({ data: [] }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: false, roles: [] } }) }))
vi.mock('../pages/quickviews', () => ({ AuditTab: () => <p>audit history</p> }))
vi.mock('../lib/supabase', () => {
  const upd = (payload: unknown) => { const rec = { payload, filters: [] as Array<[string, unknown]> }; h.updates.push(rec); const c: Record<string, unknown> = {}; c.eq = (k: string, v: unknown) => { rec.filters.push([k, v]); return c }; c.select = () => c; c.maybeSingle = async () => ({ data: { id: 'x' }, error: null }); return c }
  return { supabase: { rpc: async (fn: string, args: Record<string, unknown>) => { h.rpc.push({ fn, args }); return { error: null } },
    from: () => ({ insert: (p: unknown) => { h.inserts.push(p); return { select: () => ({ single: async () => ({ data: { id: 'n' }, error: null }) }) } }, update: (p: unknown) => upd(p) }) }, appEnv: 'test' }
})
import { ApplicabilityPage, scopeSummary } from './applicability'
import { ToastProvider } from '../app/Toasts'

const setup = () => render(<QueryClientProvider client={new QueryClient()}><ToastProvider><MemoryRouter><ApplicabilityPage /></MemoryRouter></ToastProvider></QueryClientProvider>)
const inEffect = { ...base, id: 'a1', status: 'applicable', effective_from: '2020-01-01', in_effect: true }
const future = { ...base, id: 'a2', location_code: 'PLANT-B', status: 'not_applicable', reason: 'closed', effective_from: '2999-01-01', in_effect: false }

describe('Applicability Matrix', () => {
  beforeEach(() => { h.rpc.length = 0; h.inserts.length = 0; h.updates.length = 0; h.perms = new Set(['compliance.manage']); h.rows = [inEffect, future] })
  it('summarises the scope in plain words (location > unit > entity > state ...)', () => {
    expect(scopeSummary({ ...base, entity_code: 'E1', state: 'Odisha', employee_headcount_min: 50 })).toBe('Location PLANT-A · Entity E1 · State Odisha · Employees 50–∞')
    expect(scopeSummary({ ...base, location_code: null })).toBe('Everywhere (global)')
  })
  it('an in-effect decision cannot be edited: replace (with a reason) or end it', async () => {
    setup(); fireEvent.click(screen.getAllByText('FACT-1')[0])
    expect(await screen.findByText(/in effect and cannot be edited/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Edit' })).toBeNull(); expect(screen.getByRole('button', { name: 'Replace decision…' })).toBeInTheDocument(); expect(screen.getByRole('button', { name: 'End…' })).toBeInTheDocument()
  })
  it('replace: reason and a later effective date are required; sent through the replace RPC', async () => {
    setup(); fireEvent.click(screen.getAllByText('FACT-1')[0]); fireEvent.click(await screen.findByRole('button', { name: 'Replace decision…' }))
    fireEvent.change(await screen.findByLabelText(/^Decision/), { target: { value: 'not_applicable' } }); fireEvent.change(screen.getByLabelText(/^Reason$/), { target: { value: 'site closed' } })
    fireEvent.click(screen.getByRole('button', { name: 'Replace decision' }))
    expect(await screen.findByText(/Effective from is required/)).toBeInTheDocument(); expect(await screen.findByText(/reason for the change is required/)).toBeInTheDocument(); expect(h.rpc).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/^Effective from/), { target: { value: '2027-01-01' } }); fireEvent.change(screen.getByLabelText(/^Reason for the change/), { target: { value: 'closure approved' } })
    fireEvent.click(screen.getByRole('button', { name: 'Replace decision' }))
    await waitFor(() => expect(h.rpc).toHaveLength(1))
    expect(h.rpc[0].fn).toBe('applicability_replace'); expect(h.rpc[0].args).toMatchObject({ p_old: 'a1', p_reason: 'closure approved' })
    expect(h.rpc[0].args.p_new).toMatchObject({ status: 'not_applicable', effective_from: '2027-01-01', reason: 'site closed', condition: null }); expect(h.rpc[0].args.p_new).not.toHaveProperty('compliance_id')
  })
  it('a not-yet-started decision can be edited, guarded by row_version', async () => {
    setup(); fireEvent.click(screen.getByText(/PLANT-B/)); const edit = await screen.findByRole('button', { name: 'Edit' }); fireEvent.click(edit)
    fireEvent.change(await screen.findByLabelText(/^Reason$/), { target: { value: 'closed for good' } }); fireEvent.click(screen.getByRole('button', { name: 'Save changes' }))
    await waitFor(() => expect(h.updates).toHaveLength(1)); expect(h.updates[0].filters).toEqual([['id', 'a2'], ['row_version', 4]]); expect(h.updates[0].payload).toMatchObject({ reason: 'closed for good', status: 'not_applicable' })
  })
  it('create: not-applicable needs a reason, conditional needs a valid condition, min cannot exceed max', async () => {
    setup(); fireEvent.click(screen.getByRole('button', { name: 'Add decision' }))
    fireEvent.change(await screen.findByLabelText(/^Compliance/), { target: { value: 'c1' } }); fireEvent.change(screen.getByLabelText(/^Effective from/), { target: { value: '2027-01-01' } })
    fireEvent.change(screen.getByLabelText(/^Decision/), { target: { value: 'not_applicable' } });     fireEvent.click(screen.getAllByRole('button', { name: 'Add decision' }).at(-1)!)
    expect(await screen.findByText(/reason is required for “not applicable”/)).toBeInTheDocument(); expect(h.inserts).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/^Decision/), { target: { value: 'conditional' } }); fireEvent.change(screen.getByLabelText(/^Employees — at least/), { target: { value: '60' } }); fireEvent.change(screen.getByLabelText(/^Employees — at most/), { target: { value: '10' } })
    fireEvent.click(screen.getAllByRole('button', { name: 'Add decision' }).at(-1)!)
    expect(await screen.findByText(/minimum cannot exceed the maximum/)).toBeInTheDocument(); expect(await screen.findByText('Enter a value')).toBeInTheDocument(); expect(h.inserts).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/^Employees — at most/), { target: { value: '' } }); fireEvent.change(screen.getByLabelText('Value 1'), { target: { value: '50' } })
    fireEvent.click(screen.getAllByRole('button', { name: 'Add decision' }).at(-1)!)
    await waitFor(() => expect(h.inserts).toHaveLength(1))
    expect(h.inserts[0]).toMatchObject({ compliance_id: 'c1', status: 'conditional', employee_headcount_min: 60, employee_headcount_max: null, condition: { op: 'and', args: [{ op: 'gte', field: 'location.employee_headcount', value: 50 }] } })
  })
  it('read-only users cannot add, edit or replace', async () => {
    h.perms = new Set(['compliance.read']); setup(); expect(screen.queryByRole('button', { name: 'Add decision' })).toBeNull()
    fireEvent.click(screen.getAllByText('FACT-1')[0]); await screen.findByText(/in effect and cannot be edited/); expect(screen.queryByRole('button', { name: 'Replace decision…' })).toBeNull()
  })
})
