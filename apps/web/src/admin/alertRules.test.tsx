import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  perms: new Set<string>(['config.write', 'config.read']), rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>,
  data: {} as Record<string, unknown[]>, health: { environment: 'production', unroutable_alerts: 2 } as Record<string, unknown>,
}))
vi.mock('../hooks/useServerTable', () => ({ useServerTable: () => ({ query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: h.data.v_alert_rule ?? [], total: (h.data.v_alert_rule ?? []).length, isLoading: false, error: null, refetch: vi.fn() }) }))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('./lookups', () => ({ useLookup: (l?: { table: string }) => ({ data: l?.table === 'role' ? [{ value: 'HEAD_HR', label: 'Head HR' }] : l?.table === 'app_user' ? [{ value: '59bace57-c19a-4169-901e-e837e871109a', label: 'admin@bfcl.test' }] : [] }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../pages/quickviews', () => ({ AuditTab: () => <p>audit history</p> }))
vi.mock('../lib/supabase', () => {
  const builder = (table: string) => { const c: Record<string, unknown> = {}; const f: Array<[string, unknown]> = []
    const rows = () => (h.data[table] ?? []).filter((r) => f.every(([k, v]) => (r as Record<string, unknown>)[k] === v))
    c.select = () => c; c.eq = (k: string, v: unknown) => { f.push([k, v]); return c }; c.order = () => c; c.maybeSingle = async () => ({ data: rows()[0] ?? null, error: null }); c.then = (res: (v: unknown) => void) => res({ data: rows(), error: null }); return c }
  return { supabase: { from: builder, rpc: async (fn: string, args: Record<string, unknown>) => { h.rpc.push({ fn, args }); return fn === 'system_health' ? { data: h.health, error: null } : { error: null } } }, appEnv: 'test' }
})
import { AlertRulesPage } from './alertRules'
import { ToastProvider } from '../app/Toasts'

const wrap = () => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><ToastProvider><MemoryRouter><AlertRulesPage /></MemoryRouter></ToastProvider></QueryClientProvider>)
const rule = { id: 'r1', code: 'DEFAULT_COMPLIANCE_ALERT', name: 'Default reminders', version: 2, status: 'active', applies: 'compliance', offsets: [-7, 0], channels: ['in_app'], recipients: ['owner'], critical: false,
  definition: { applies: 'compliance', offsets: [-7, 0], channels: ['in_app'], recipients: ['owner'], when: { op: 'eq', field: 'status', value: 'open' } }, effective_from: '2026-01-01', effective_to: null, change_reason: 'initial', row_version: 1, is_latest: true }
beforeEach(() => { h.rpc.length = 0; h.perms = new Set(['config.write', 'config.read']); h.health = { environment: 'production', unroutable_alerts: 2 }
  h.data = { v_alert_rule: [rule], v_alert_routing_issue: [{ rule_code: 'UNROUTABLE_ESCALATION', severity: 'error', problem: 'BLOCKING for production: no active UNROUTABLE_ESCALATION rule' }] } })

describe('Alert rules & D-001 routing', () => {
  it('shows missing escalation recipients, the blocking routing error and the unroutable count', async () => {
    wrap(); expect(await screen.findByText('No escalation recipients configured')).toBeInTheDocument(); expect(await screen.findByText(/BLOCKING for production/)).toBeInTheDocument()
    expect(await screen.findByText('2 unroutable alert(s)')).toBeInTheDocument(); expect(screen.getByText('1 routing error(s)')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'System Health' })).toHaveAttribute('href', '/admin/system-health'); expect(screen.getByRole('link', { name: 'Notification Centre' })).toHaveAttribute('href', '/notifications')
    expect(screen.queryByText(/Super Admin is also used/)).toBeNull()
  })
  it('development mentions the dev-only Super Admin fallback', async () => { h.health = { environment: 'development', unroutable_alerts: 0 }; wrap(); expect(await screen.findByText(/development: Super Admin is also used as a fallback — never in production/)).toBeInTheDocument() })
  it('configuring escalation recipients creates a new version of UNROUTABLE_ESCALATION through the config API (reason mandatory, no owner)', async () => {
    wrap(); fireEvent.click(await screen.findByRole('button', { name: 'Configure escalation recipients' }))
    expect(await screen.findByLabelText(/Rule code/)).toHaveValue('UNROUTABLE_ESCALATION'); expect(screen.getByLabelText(/Rule code/)).toBeDisabled(); expect(screen.queryByRole('button', { name: 'Add owner' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Create rule' })); expect(await screen.findByText('Add at least one recipient')).toBeInTheDocument(); expect(screen.getByText('A change reason is required')).toBeInTheDocument(); expect(h.rpc.filter((r) => r.fn === 'config_new_version')).toHaveLength(0)
    fireEvent.change(screen.getByLabelText('Role'), { target: { value: 'HEAD_HR' } }); fireEvent.click(screen.getAllByRole('button', { name: 'Add' })[0]); fireEvent.change(screen.getByLabelText(/Change reason/), { target: { value: 'BFCL escalation owners' } })
    fireEvent.click(screen.getByRole('button', { name: 'Create rule' }))
    await waitFor(() => expect(h.rpc.filter((r) => r.fn === 'config_new_version')).toHaveLength(1))
    expect(h.rpc.find((r) => r.fn === 'config_new_version')!.args).toMatchObject({ p_kind: 'alert_rule', p_code: 'UNROUTABLE_ESCALATION', p_reason: 'BFCL escalation owners', p_effective_from: null,
      p_definition: { applies: 'compliance', offsets: [0], channels: ['in_app'], recipients: ['role:HEAD_HR'], critical: true } })
  })
  it('a new version of an existing rule keeps its other settings (e.g. a "when" condition) and never edits the old version', async () => {
    wrap(); fireEvent.click(await screen.findByText('DEFAULT_COMPLIANCE_ALERT')); fireEvent.click(await screen.findByRole('button', { name: 'Create new version…' }))
    fireEvent.change(await screen.findByLabelText(/Offsets/), { target: { value: '-14, -7, 0' } }); fireEvent.change(screen.getByLabelText(/Change reason/), { target: { value: 'earlier reminder' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save as new version' }))
    await waitFor(() => expect(h.rpc.filter((r) => r.fn === 'config_new_version')).toHaveLength(1))
    expect(h.rpc.find((r) => r.fn === 'config_new_version')!.args.p_definition).toMatchObject({ when: { op: 'eq', field: 'status', value: 'open' }, offsets: [-14, -7, 0], recipients: ['owner'] })
  })
  it('malformed offsets are refused on the frontend', async () => {
    wrap(); fireEvent.click(await screen.findByText('DEFAULT_COMPLIANCE_ALERT')); fireEvent.click(await screen.findByRole('button', { name: 'Create new version…' }))
    fireEvent.change(await screen.findByLabelText(/Offsets/), { target: { value: '1.5, x' } }); fireEvent.change(screen.getByLabelText(/Change reason/), { target: { value: 'r' } }); fireEvent.click(screen.getByRole('button', { name: 'Save as new version' }))
    expect(await screen.findByText(/not a whole number/)).toBeInTheDocument(); expect(h.rpc.filter((r) => r.fn === 'config_new_version')).toHaveLength(0)
  })
  it('read-only users cannot configure', async () => { h.perms = new Set(['config.read']); wrap(); await screen.findByText('No escalation recipients configured'); expect(screen.queryByRole('button', { name: /escalation recipients/ })).toBeNull(); expect(screen.queryByRole('button', { name: 'New alert rule' })).toBeNull() })
})
