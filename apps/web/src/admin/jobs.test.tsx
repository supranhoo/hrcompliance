import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({ perms: new Set<string>(['job.read', 'job.manage']), rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, data: {} as Record<string, unknown[]> }))
vi.mock('../hooks/useServerTable', () => ({ useServerTable: () => ({ query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: h.data.v_job_status ?? [], total: (h.data.v_job_status ?? []).length, isLoading: false, error: null, refetch: vi.fn() }) }))
vi.mock('../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../lib/supabase', () => {
  const builder = (table: string) => { const c: Record<string, unknown> = {}; c.select = () => c; c.eq = () => c; c.order = () => c; c.limit = () => c; c.then = (res: (v: unknown) => void) => res({ data: h.data[table] ?? [], error: null }); return c }
  return { supabase: { from: builder, rpc: async (fn: string, args: Record<string, unknown>) => { h.rpc.push({ fn, args }); return { error: null } } }, appEnv: 'test' }
})
import { JobMonitorPage, jobHealth } from './jobs'
import { ToastProvider } from '../app/Toasts'

const wrap = () => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><ToastProvider><MemoryRouter><JobMonitorPage /></MemoryRouter></ToastProvider></QueryClientProvider>)
const job = { id: 'j1', code: 'compliance_generation', name: 'Compliance generation', description: 'd', schedule_cron: '0 1 * * *', is_enabled: true, max_attempts: 3, timeout_seconds: 900, has_runner: true, last_status: 'succeeded', last_started_at: '2026-10-03T01:00:00Z', last_completed_at: null, last_records: 5, last_environment: 'development', last_warning: null, last_message: null, last_success_at: '2026-10-03T01:00:00Z', failures_24h: 0 }
beforeEach(() => { h.rpc.length = 0; h.perms = new Set(['job.read', 'job.manage']); h.data = { v_job_status: [job], v_job_run: [] } })

describe('Job health', () => {
  it('reports the states honestly', () => {
    expect(jobHealth(job).label).toBe('Healthy'); expect(jobHealth({ ...job, is_enabled: false }).label).toBe('Disabled'); expect(jobHealth({ ...job, has_runner: false }).label).toBe('No runner yet')
    expect(jobHealth({ ...job, last_status: null }).label).toBe('Never run'); expect(jobHealth({ ...job, failures_24h: 2 }).label).toBe('Failing')
  })
})
describe('Job Monitor', () => {
  it('states that schedules are proposals and the scheduler is off', async () => { wrap(); expect(await screen.findByText(/switched off until the owner approves/)).toBeInTheDocument(); expect(screen.getByText('0 1 * * *')).toBeInTheDocument() })
  it('disabling needs a reason and calls the audited RPC', async () => {
    wrap(); fireEvent.click(await screen.findByText('Compliance generation')); fireEvent.click(await screen.findByRole('button', { name: 'Disable job' }))
    expect(await screen.findByText('A reason is required')).toBeInTheDocument(); expect(h.rpc).toHaveLength(0)
    fireEvent.change(screen.getByLabelText(/Reason for disabling/), { target: { value: 'maintenance' } }); fireEvent.click(screen.getByRole('button', { name: 'Disable job' }))
    await waitFor(() => expect(h.rpc).toHaveLength(1)); expect(h.rpc[0]).toEqual({ fn: 'job_set_enabled', args: { p_code: 'compliance_generation', p_enabled: false, p_reason: 'maintenance' } })
  })
  it('read-only users cannot change jobs', async () => { h.perms = new Set(['job.read']); wrap(); fireEvent.click(await screen.findByText('Compliance generation')); await screen.findByText('Reason for disabling', { exact: false }).catch(() => null); await screen.findByText('Failures (24h)'); expect(screen.queryByRole('button', { name: 'Disable job' })).toBeNull() })
})
