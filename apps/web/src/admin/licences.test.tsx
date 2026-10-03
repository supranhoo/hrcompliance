import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({ perms: new Set<string>(['licence.write']), inserts: [] as Array<{ table: string; payload: unknown }>, updates: [] as Array<{ payload: unknown; filters: Array<[string, unknown]> }>,
  types: [{ id: 't1', default_renewal_lead_days: 90, default_risk: 'high', has_expiry: true }, { id: 't2', default_renewal_lead_days: 30, default_risk: null, has_expiry: false }] }))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [{ value: 'high', label: 'High' }, { value: 'not_started', label: 'Not started' }] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('./lookups', () => ({ useFieldOptions: (f: { key: string }) => (f.key === 'licence_type_id' ? [{ value: 't1', label: 'Factory licence' }, { value: 't2', label: 'Registration' }] : f.key === 'entity_id' ? [{ value: 'e1', label: 'Entity One' }] : f.key === 'lifecycle_status' ? [{ value: 'active', label: 'Active' }] : f.key === 'risk_level' ? [{ value: 'high', label: 'High' }] : f.key === 'renewal_status' ? [{ value: 'not_started', label: 'Not started' }] : []), useLookup: () => ({ data: [] }), useLicenceTypes: () => ({ data: h.types }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: false, roles: [] } }) }))
vi.mock('../lib/supabase', () => {
  const upd = (payload: unknown) => { const rec = { payload, filters: [] as Array<[string, unknown]> }; h.updates.push(rec); const c: Record<string, unknown> = {}; c.eq = (k: string, v: unknown) => { rec.filters.push([k, v]); return c }; c.select = () => c; c.maybeSingle = async () => ({ data: { id: 'x' }, error: null }); return c }
  return { supabase: { from: (table: string) => ({ insert: (payload: unknown) => { h.inserts.push({ table, payload }); return { select: () => ({ single: async () => ({ data: { id: 'n' }, error: null }) }) } }, update: (p: unknown) => upd(p) }) }, appEnv: 'test' }
})
import { LicenceForm, NewLicenceButton, licenceProblems } from './licences'
import { ToastProvider } from '../app/Toasts'

const wrap = (ui: React.ReactNode) => render(<QueryClientProvider client={new QueryClient()}><ToastProvider><MemoryRouter>{ui}</MemoryRouter></ToastProvider></QueryClientProvider>)
beforeEach(() => { h.inserts.length = 0; h.updates.length = 0; h.perms = new Set(['licence.write']) })

describe('licence rules', () => {
  it('expiry is required only when the type expires and the licence is an issued, active one', () => {
    expect(licenceProblems({ expiry_date: '', lifecycle_status: 'active', is_new_application: false }, { has_expiry: true }).expiry_date).toMatch(/required/)
    expect(licenceProblems({ expiry_date: '', lifecycle_status: 'active', is_new_application: false }, { has_expiry: false })).toEqual({})
    expect(licenceProblems({ expiry_date: '', lifecycle_status: 'active', is_new_application: true }, { has_expiry: true })).toEqual({})
    expect(licenceProblems({ expiry_date: '2025-01-01', issue_date: '2026-01-01', lifecycle_status: 'active' }, { has_expiry: true }).expiry_date).toMatch(/before the issue/)
  })
})
describe('Licence form', () => {
  it('only users with licence.write see "New licence"', () => { h.perms = new Set(['licence.read']); wrap(<NewLicenceButton />); expect(screen.queryByRole('button', { name: 'New licence' })).toBeNull() })
  it('choosing a type pre-fills its renewal lead time and risk (configurable per type); the user can still override', async () => {
    wrap(<LicenceForm mode="create" onDone={vi.fn()} />)
    fireEvent.change(await screen.findByLabelText(/^Licence \/ registration type/), { target: { value: 't1' } })
    await waitFor(() => expect((screen.getByLabelText(/^Renewal lead time/) as HTMLInputElement).value).toBe('90'))
    fireEvent.change(screen.getByLabelText(/^Renewal lead time/), { target: { value: '45' } })
    fireEvent.change(screen.getByLabelText(/^Licence \/ registration type/), { target: { value: 't2' } })
    expect((screen.getByLabelText(/^Renewal lead time/) as HTMLInputElement).value).toBe('45')       // an explicit choice is not overwritten
  })
  it('validates on the frontend and creates through the licence table without licence_no (the database assigns LIC-…)', async () => {
    const done = vi.fn(); wrap(<LicenceForm mode="create" onDone={done} />)
    fireEvent.click(await screen.findByRole('button', { name: 'Create licence' }))
    expect(await screen.findByText('Licence / registration type is required')).toBeInTheDocument(); expect(screen.getByText('Legal entity is required')).toBeInTheDocument(); expect(h.inserts).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/^Licence \/ registration type/), { target: { value: 't1' } }); fireEvent.change(screen.getByLabelText(/^Legal entity/), { target: { value: 'e1' } })
    fireEvent.click(screen.getByRole('button', { name: 'Create licence' })); expect(await screen.findByText(/Expiry date is required/)).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText(/^Expiry date/), { target: { value: '2027-06-30' } }); fireEvent.click(screen.getByRole('button', { name: 'Create licence' }))
    await waitFor(() => expect(h.inserts).toHaveLength(1))
    expect(h.inserts[0].table).toBe('licence'); expect(h.inserts[0].payload).toMatchObject({ licence_type_id: 't1', entity_id: 'e1', expiry_date: '2027-06-30', renewal_lead_days: 90, risk_level: 'high', lifecycle_status: 'active' })
    expect(h.inserts[0].payload).not.toHaveProperty('licence_no'); expect(done).toHaveBeenCalled()
  })
})
