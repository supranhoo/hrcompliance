import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  perms: new Set<string>(['user.admin', 'role.admin', 'user.read']), rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, data: {} as Record<string, unknown[]>,
  rpcError: null as null | ((fn: string, args: Record<string, unknown>) => { code: string; message: string } | null),
}))
vi.mock('../hooks/useServerTable', () => ({ useServerTable: (table: string) => ({ query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: h.data[table] ?? [], total: (h.data[table] ?? []).length, isLoading: false, error: null, refetch: vi.fn() }) }))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('./lookups', () => ({ useLookup: (l?: { table: string }) => ({ data: l?.table === 'role' ? [{ value: 'HEAD_HR', label: 'Head HR' }, { value: 'VIEWER', label: 'Viewer' }] : l?.table === 'entity' ? [{ value: 'e1', label: 'BFCL Ltd' }] : l?.table === 'location' ? [{ value: 'l1', label: 'Pune' }] : [] }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../pages/quickviews', () => ({ AuditTab: () => <p>audit history</p> }))
vi.mock('../lib/supabase', () => {
  const builder = (table: string) => { const c: Record<string, unknown> = {}; c.select = () => c; c.eq = () => c; c.or = () => c; c.order = () => c; c.limit = () => c; c.then = (res: (v: unknown) => void) => res({ data: h.data[table] ?? [], error: null }); return c }
  return { supabase: { from: builder, rpc: async (fn: string, args: Record<string, unknown>) => { h.rpc.push({ fn, args }); return { error: h.rpcError?.(fn, args) ?? null } } }, appEnv: 'test' }
})
import { RolesPage } from './roleAdmin'
import { UsersAdminPage } from './userAdmin'
import { ToastProvider } from '../app/Toasts'

const wrap = (ui: React.ReactElement) => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><ToastProvider><MemoryRouter>{ui}</MemoryRouter></ToastProvider></QueryClientProvider>)
const perms = [{ code: 'compliance.read', module: 'compliance', description: 'Read compliance' }, { code: 'role.admin', module: 'user', description: 'Administer roles' }, { code: 'user.admin', module: 'user', description: 'Administer users' }]
const role = { id: 'r1', code: 'HEAD_HR', name: 'Head HR', description: null, is_system: true, permissions: ['compliance.read', 'role.admin'], user_count: 2, grants_role_admin: true }
const user = { id: 'u1', email: 'a@bfcl.test', full_name: 'Asha', status: 'active', scope_all: false, last_login_at: null, signed_in: true, roles: ['VIEWER'], entity_scopes: 1, location_scopes: 0, is_role_admin: false }
beforeEach(() => { h.rpc.length = 0; h.rpcError = null; h.perms = new Set(['user.admin', 'role.admin', 'user.read']); h.data = { v_role_admin: [role], permission: perms, v_user_admin: [user], v_user_scope: [{ scope_type: 'entity', scope_id: 'e1' }] } })

describe('Roles & permissions', () => {
  it('the editor sends the full permission set with a mandatory reason and shows the diff, flagging admin removals', async () => {
    wrap(<RolesPage />); fireEvent.click(await screen.findByText('Head HR')); const box = await screen.findByLabelText(/role\.admin/)
    fireEvent.click(box); expect(await screen.findByText(/removes an administrative permission/)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Save permissions' })); expect(await screen.findByText(/A reason is required/)).toBeInTheDocument(); expect(h.rpc).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/Reason for this change/), { target: { value: 'least privilege' } }); fireEvent.click(screen.getByRole('button', { name: 'Save permissions' }))
    await waitFor(() => expect(h.rpc).toHaveLength(1)); expect(h.rpc[0]).toEqual({ fn: 'role_save', args: { p_code: 'HEAD_HR', p_name: 'Head HR', p_description: '', p_permissions: ['compliance.read'], p_reason: 'least privilege', p_confirm_self: false } })
  })
  it('removing your own admin access asks for explicit confirmation, then repeats the call with the flag', async () => {
    h.rpcError = (_fn, a) => (a.p_confirm_self ? null : { code: 'AD002', message: 'this change removes your own administrative access (role.admin): confirm explicitly to proceed' })
    wrap(<RolesPage />); fireEvent.click(await screen.findByText('Head HR')); fireEvent.click(await screen.findByLabelText(/role\.admin/)); fireEvent.change(screen.getByLabelText(/Reason for this change/), { target: { value: 'oops' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save permissions' })); expect(await screen.findByText('This removes your own administrative access')).toBeInTheDocument(); expect(h.rpc).toHaveLength(1)
    fireEvent.click(screen.getByRole('button', { name: 'Yes, remove my access' })); await waitFor(() => expect(h.rpc).toHaveLength(2)); expect(h.rpc[1].args.p_confirm_self).toBe(true)
  })
  it('cancelling the confirmation changes nothing', async () => {
    h.rpcError = () => ({ code: 'AD002', message: 'x' })
    wrap(<RolesPage />); fireEvent.click(await screen.findByText('Head HR')); fireEvent.click(await screen.findByLabelText(/role\.admin/)); fireEvent.change(screen.getByLabelText(/Reason for this change/), { target: { value: 'r' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save permissions' })); fireEvent.click(await screen.findByRole('button', { name: 'Cancel', hidden: false }))
    expect(h.rpc).toHaveLength(1)
  })
  it('users without role.admin can read but not edit or create', async () => {
    h.perms = new Set(['user.read']); wrap(<RolesPage />); expect(screen.queryByRole('button', { name: 'New role' })).toBeNull(); fireEvent.click(await screen.findByText('Head HR')); expect(await screen.findByLabelText(/compliance\.read/)).toBeDisabled(); expect(screen.queryByRole('button', { name: 'Save permissions' })).toBeNull()
  })
  it('new role: code format is validated before anything is sent', async () => {
    wrap(<RolesPage />); fireEvent.click(await screen.findByRole('button', { name: 'New role' })); fireEvent.change(await screen.findByLabelText(/Role code/), { target: { value: 'bad code' } }); fireEvent.click(screen.getByRole('button', { name: 'Create role' }))
    expect(await screen.findByText(/capital letters, digits and underscores/i)).toBeInTheDocument(); expect(h.rpc).toHaveLength(0)
  })
})

describe('Users administration', () => {
  it('invite validates the email and reason, then calls user_invite (roles only when the caller holds role.admin)', async () => {
    wrap(<UsersAdminPage />); fireEvent.click(await screen.findByRole('button', { name: 'Invite user' })); await screen.findByLabelText(/Email/); fireEvent.click(screen.getAllByRole('button', { name: 'Invite user' }).at(-1)!)
    expect(await screen.findByText(/valid email/)).toBeInTheDocument(); expect(h.rpc).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/Email/), { target: { value: 'n@bfcl.test' } }); fireEvent.click(screen.getByLabelText('Viewer')); fireEvent.change(screen.getByLabelText(/Reason/), { target: { value: 'joining' } }); fireEvent.click(screen.getAllByRole('button', { name: 'Invite user' }).at(-1)!)
    await waitFor(() => expect(h.rpc).toHaveLength(1)); expect(h.rpc[0]).toEqual({ fn: 'user_invite', args: { p_email: 'n@bfcl.test', p_full_name: '', p_roles: ['VIEWER'], p_reason: 'joining' } })
  })
  it('scope: restricted needs a choice; saving sends entity and location lists', async () => {
    wrap(<UsersAdminPage />); fireEvent.click(await screen.findByText('Asha')); fireEvent.click(await screen.findByRole('tab', { name: 'Scope' }))
    fireEvent.click(await screen.findByLabelText('BFCL Ltd')); fireEvent.click(screen.getByLabelText('Pune')); fireEvent.change(screen.getByLabelText(/Reason/), { target: { value: 'plant move' } }); fireEvent.click(screen.getByRole('button', { name: 'Save scope' }))
    await waitFor(() => expect(h.rpc).toHaveLength(1)); expect(h.rpc[0]).toEqual({ fn: 'user_set_scope', args: { p_user: 'u1', p_scope_all: false, p_entities: [], p_locations: ['l1'], p_reason: 'plant move' } })
  })
  it('role editing is unavailable without role.admin; disabling needs a reason', async () => {
    h.perms = new Set(['user.admin', 'user.read']); wrap(<UsersAdminPage />); fireEvent.click(await screen.findByText('Asha'))
    fireEvent.click(await screen.findByRole('tab', { name: 'Roles' })); expect(await screen.findByText(/needs role administration/)).toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Save roles' })).toBeNull()
    fireEvent.click(screen.getByRole('tab', { name: 'User' })); fireEvent.click(await screen.findByRole('button', { name: 'Disable user' })); expect(await screen.findByText('A reason is required')).toBeInTheDocument(); expect(h.rpc).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/Reason/), { target: { value: 'left' } }); fireEvent.click(screen.getByRole('button', { name: 'Disable user' })); await waitFor(() => expect(h.rpc).toHaveLength(1)); expect(h.rpc[0]).toMatchObject({ fn: 'user_set_status', args: { p_status: 'disabled', p_reason: 'left', p_confirm_self: false } })
  })
  it('read-only viewers see the list without Invite', async () => { h.perms = new Set(['user.read']); wrap(<UsersAdminPage />); await screen.findByText('Asha'); expect(screen.queryByRole('button', { name: 'Invite user' })).toBeNull() })
})
