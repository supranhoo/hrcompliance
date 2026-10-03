import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  perms: new Set<string>(['compliance.manage']),
  rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, inserts: [] as Array<{ table: string; payload: unknown }>, updates: [] as Array<{ table: string; payload: unknown; filters: Array<[string, unknown]> }>,
  rows: [] as Array<Record<string, unknown>>,
}))
const base = { compliance_id: 'c1', compliance_code: 'PF-MONTHLY', compliance_name: 'PF monthly', compliance_type: 'statutory', frequency: 'monthly', period_start_month: 1, due_rule: { type: 'day_of_month', day: 15, month_offset: 1 },
  risk_level: 'high', criticality: 'critical', evidence_required: false, alert_rule_code: null, escalation_rule_code: null, effective_to: null, change_reason: null, row_version: 2, evidence_count: 0, obligation_count: 4 }
vi.mock('../hooks/useServerTable', () => ({ useServerTable: () => ({ query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: h.rows, total: h.rows.length, isLoading: false, error: null, refetch: vi.fn() }) }))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [{ value: 'high', label: 'High' }] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('./lookups', () => ({ useFieldOptions: () => [{ value: 'statutory', label: 'Statutory' }], useLookup: () => ({ data: [{ value: 'c1', label: 'PF-MONTHLY' }] }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../pages/quickviews', () => ({ AuditTab: () => <p>audit history</p> }))
vi.mock('../lib/supabase', () => {
  const upd = (table: string, payload: unknown) => { const rec = { table, payload, filters: [] as Array<[string, unknown]> }; h.updates.push(rec); const c: Record<string, unknown> = {}; c.eq = (k: string, v: unknown) => { rec.filters.push([k, v]); return c }; c.select = () => c; c.maybeSingle = async () => ({ data: { id: 'x' }, error: null }); return c }
  return { supabase: {
    rpc: async (fn: string, args: Record<string, unknown>) => { h.rpc.push({ fn, args }); return { error: null } },
    from: (table: string) => ({
      insert: (payload: unknown) => { h.inserts.push({ table, payload }); return { select: () => ({ single: async () => ({ data: { id: 'n' }, error: null }) }) } },
      update: (payload: unknown) => upd(table, payload),
      select: () => ({ eq: async () => ({ data: [], error: null }) }),
      delete: () => ({ eq: () => ({ eq: async () => ({ error: null }) }) }),
    }) }, appEnv: 'test' }
})
import { RuleVersionsPage } from './ruleVersions'
import { ToastProvider } from '../app/Toasts'

const setup = () => render(<QueryClientProvider client={new QueryClient()}><ToastProvider><MemoryRouter><RuleVersionsPage /></MemoryRouter></ToastProvider></QueryClientProvider>)
const active = { ...base, id: 'v1', version: 1, status: 'active', effective_from: '2020-01-01' }
const draft = { ...base, id: 'v2', version: 2, status: 'draft', effective_from: '2026-11-01' }

describe('Rule Versions', () => {
  beforeEach(() => { h.rpc.length = 0; h.inserts.length = 0; h.updates.length = 0; h.perms = new Set(['compliance.manage']); h.rows = [active, draft] })
  it('lists the complete version history with a clear state for each version', () => {
    setup(); expect(screen.getByText('v1')).toBeInTheDocument(); expect(screen.getByText('v2')).toBeInTheDocument()
    expect(within(screen.getByRole('table')).getByText('Active')).toBeInTheDocument(); expect(within(screen.getByRole('table')).getByText('Draft')).toBeInTheDocument()
  })
  it('an ACTIVE version has no edit/activate controls: only "create a new version from this"', async () => {
    setup(); fireEvent.click(screen.getByText('v1'))
    expect(await screen.findByText(/can never be edited/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Edit draft' })).toBeNull(); expect(screen.queryByRole('button', { name: /Activate/ })).toBeNull()
    expect(screen.getByRole('button', { name: 'Create new version from this' })).toBeInTheDocument()
    expect(screen.getByText('15th of the month after the period ends')).toBeInTheDocument()
  })
  it('creating a new version calls the clone RPC (never an update of the effective one)', async () => {
    setup(); fireEvent.click(screen.getByText('v1')); fireEvent.click(await screen.findByRole('button', { name: 'Create new version from this' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Create draft' }))
    await waitFor(() => expect(h.rpc).toHaveLength(1)); expect(h.rpc[0]).toEqual({ fn: 'compliance_rule_new_draft', args: { p_compliance: 'c1', p_effective_from: null } })
    expect(h.updates).toHaveLength(0)
  })
  it('a DRAFT can be edited, activated or discarded; activation needs a reason and uses the existing function', async () => {
    setup(); fireEvent.click(screen.getByText('v2'))
    expect(await screen.findByRole('button', { name: 'Edit draft' })).toBeInTheDocument(); expect(screen.getByRole('button', { name: 'Discard draft' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Activate…' }))
    const go = await screen.findByRole('button', { name: 'Activate version' }); expect(go).toBeDisabled()
    fireEvent.change(screen.getByLabelText(/Change reason/), { target: { value: '  due day moves to the 20th ' } }); expect(go).toBeEnabled(); fireEvent.click(go)
    await waitFor(() => expect(h.rpc).toHaveLength(1)); expect(h.rpc[0]).toEqual({ fn: 'compliance_activate_rule_version', args: { p_version_id: 'v2', p_reason: 'due day moves to the 20th' } })
  })
  it('editing a draft is guarded by row_version and validates the due rule on the frontend', async () => {
    setup(); fireEvent.click(screen.getByText('v2')); fireEvent.click(await screen.findByRole('button', { name: 'Edit draft' }))
    fireEvent.change(await screen.findByLabelText('Due date rule type'), { target: { value: '' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save draft' })); expect(await screen.findByText(/Choose how the due date/)).toBeInTheDocument(); expect(h.updates).toHaveLength(0)
    fireEvent.change(screen.getByLabelText('Due date rule type'), { target: { value: 'days_after_period_end' } }); fireEvent.click(screen.getByRole('button', { name: 'Save draft' }))
    await waitFor(() => expect(h.updates).toHaveLength(1))
    expect(h.updates[0].table).toBe('compliance_rule_version'); expect(h.updates[0].filters).toEqual([['id', 'v2'], ['row_version', 2]])
    expect(h.updates[0].payload).toMatchObject({ due_rule: { type: 'days_after_period_end', days: 7 }, period_start_month: 1, frequency: 'monthly' })
    expect(h.updates[0].payload).not.toHaveProperty('status'); expect(h.updates[0].payload).not.toHaveProperty('version')
  })
  it('read-only users see the history but no actions', async () => {
    h.perms = new Set(['compliance.read']); setup(); expect(screen.queryByRole('button', { name: 'New rule version' })).toBeNull()
    fireEvent.click(screen.getByText('v2')); await screen.findByText(/not in effect/); expect(screen.queryByRole('button', { name: 'Edit draft' })).toBeNull()
  })
})
