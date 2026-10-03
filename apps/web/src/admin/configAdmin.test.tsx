import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  perms: new Set<string>(['config.write', 'config.read']),
  updates: [] as Array<{ table: string; payload: unknown; filters: Array<[string, unknown]> }>, inserts: [] as Array<{ table: string; payload: unknown }>,
  values: [] as Array<Record<string, unknown>>, settings: [] as Array<Record<string, unknown>>, transitions: [] as Array<Record<string, unknown>>,
}))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: (s?: string) => ({ data: s === 'SEVERITY' ? ['critical', 'high', 'medium', 'low'].map((v) => ({ value: v, label: v })) : [] , isLoading: false }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../lib/supabase', () => {
  const builder = (table: string) => {
    const state = { filters: [] as Array<[string, unknown]> }
    const result = () => (table === 'lov_value' ? h.values : table === 'system_config' ? h.settings : table === 'status_transition' ? h.transitions : [{ code: 'open', label: 'Open' }])
    const c: Record<string, unknown> = {}
    c.select = () => c; c.eq = (k: string, v: unknown) => { state.filters.push([k, v]); return c }; c.in = () => c
    c.order = () => c
    c.then = (res: (v: unknown) => void) => res({ data: result(), error: null })
    c.insert = (payload: unknown) => { h.inserts.push({ table, payload }); return Promise.resolve({ error: null }) }
    c.update = (payload: unknown) => { const rec = { table, payload, filters: state.filters }; h.updates.push(rec); const u: Record<string, unknown> = {}; u.eq = (k: string, v: unknown) => { state.filters.push([k, v]); return u }; u.select = () => u; u.maybeSingle = async () => ({ data: { id: 'x' }, error: null }); return u }
    return c
  }
  return { supabase: { from: builder }, appEnv: 'test' }
})
import { LovValues, LOV_VALUE_CODE } from './lov'
import { SettingsPage } from './SettingsPage'
import { ToastProvider } from '../app/Toasts'

const wrap = (ui: React.ReactNode) => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><ToastProvider><MemoryRouter>{ui}</MemoryRouter></ToastProvider></QueryClientProvider>)
beforeEach(() => {
  h.updates.length = 0; h.inserts.length = 0; h.perms = new Set(['config.write', 'config.read'])
  h.values = [{ id: 'v1', code: 'critical', label: 'Critical', sort_order: 40, color: 'red', is_active: true, meta: { protected: true }, row_version: 2 }, { id: 'v2', code: 'CUSTOM', label: 'Custom', sort_order: 50, color: null, is_active: true, meta: {}, row_version: 1 }]
  h.settings = [{ key: 'compliance.due_soon_days', value: 7, description: '', row_version: 3 }, { key: 'licence.expiry_thresholds', value: [90, 60, 30, 15, 7], description: '', row_version: 1 }, { key: 'exception.target_days', value: { low: 14, high: 3, medium: 7, critical: 1 }, description: '', row_version: 2 }]
})

describe('LOV values editor', () => {
  it('protected (system-used) values cannot be deactivated from the UI; others can', async () => {
    wrap(<LovValues setId="s1" setCode="RISK" isSystem />)
    const buttons = await screen.findAllByRole('button', { name: /Deactivate/ }); expect(buttons[0]).toBeDisabled(); expect(buttons[1]).toBeEnabled()
    expect(screen.getByText('system')).toBeInTheDocument()
  })
  it('editing a label updates only that field, guarded by row_version; the code is never sent', async () => {
    wrap(<LovValues setId="s1" setCode="RISK" isSystem />)
    const input = await screen.findByLabelText('Label for CUSTOM'); fireEvent.change(input, { target: { value: 'Custom risk' } }); fireEvent.blur(input)
    await waitFor(() => expect(h.updates).toHaveLength(1)); expect(h.updates[0]).toMatchObject({ table: 'lov_value', payload: { label: 'Custom risk' }, filters: [['id', 'v2'], ['row_version', 1]] })
  })
  it('adding a value validates the code and label first and appends after the last order', async () => {
    wrap(<LovValues setId="s1" setCode="RISK" isSystem />)
    fireEvent.change(await screen.findByLabelText('New value code'), { target: { value: 'bad code!' } }); fireEvent.change(screen.getByLabelText('New value label'), { target: { value: 'Bad' } })
    fireEvent.click(screen.getByRole('button', { name: 'Add value' })); expect(await screen.findByText(/Code: letters, digits/)).toBeInTheDocument(); expect(h.inserts).toHaveLength(0)
    fireEvent.change(screen.getByLabelText('New value code'), { target: { value: 'URGENT' } }); fireEvent.click(screen.getByRole('button', { name: 'Add value' }))
    await waitFor(() => expect(h.inserts).toHaveLength(1)); expect(h.inserts[0].payload).toMatchObject({ set_id: 's1', code: 'URGENT', label: 'Bad', sort_order: 60, color: null })
    expect(LOV_VALUE_CODE.test('A_1')).toBe(true); expect(LOV_VALUE_CODE.test('a b')).toBe(false)
  })
  it('read-only users cannot edit', async () => {
    h.perms = new Set(['config.read']); wrap(<LovValues setId="s1" setCode="RISK" isSystem />)
    expect(await screen.findByLabelText('Label for CUSTOM')).toBeDisabled(); expect(screen.queryByRole('button', { name: 'Add value' })).toBeNull()
  })
})

describe('Settings page', () => {
  it('shows the stored values and saves only a validated change, guarded by row_version', async () => {
    wrap(<SettingsPage />)
    const due = await screen.findByLabelText('Due-soon window (days)'); expect(due).toHaveValue('7')
    expect(screen.getByLabelText('Licence expiry thresholds (days)')).toHaveValue('90, 60, 30, 15, 7'); expect(screen.getByLabelText('Resolution target by severity (days)')).toHaveValue('critical=1, high=3, medium=7, low=14')
    const save = screen.getAllByRole('button', { name: 'Save' })[0]; expect(save).toBeDisabled()
    fireEvent.change(due, { target: { value: 'soon' } }); fireEvent.click(screen.getAllByRole('button', { name: 'Save' })[0]); expect(await screen.findByText('Enter a whole number')).toBeInTheDocument(); expect(h.updates).toHaveLength(0)
    fireEvent.change(due, { target: { value: '10' } }); fireEvent.click(screen.getAllByRole('button', { name: 'Save' })[0])
    await waitFor(() => expect(h.updates).toHaveLength(1)); expect(h.updates[0]).toMatchObject({ table: 'system_config', payload: { value: 10 }, filters: [['key', 'compliance.due_soon_days'], ['row_version', 3]] })
  })
  it('thresholds must descend; severity targets must cover every configured severity', async () => {
    wrap(<SettingsPage />)
    const th = await screen.findByLabelText('Licence expiry thresholds (days)'); fireEvent.change(th, { target: { value: '7, 30' } }); fireEvent.submit(th.closest('form')!)
    expect(await screen.findByText(/strictly descending/)).toBeInTheDocument()
    const sla = screen.getByLabelText('Resolution target by severity (days)'); fireEvent.change(sla, { target: { value: 'critical=1, high=3' } }); fireEvent.submit(sla.closest('form')!)
    expect(await screen.findByText(/Add a target for “medium”/)).toBeInTheDocument(); expect(h.updates).toHaveLength(0)
  })
  it('read-only users see values but no Save', async () => {
    h.perms = new Set(['config.read']); wrap(<SettingsPage />); expect(await screen.findByLabelText('Due-soon window (days)')).toBeDisabled(); expect(screen.queryByRole('button', { name: 'Save' })).toBeNull()
  })
})
