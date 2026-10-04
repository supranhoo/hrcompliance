import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({ perms: new Set<string>(['compliance.read', 'licence.read', 'report.export']), rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, perf: [] as unknown[], pipe: [] as unknown[], exportError: null as null | { message: string }, downloads: [] as string[] }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../app/Toasts', () => ({ useToast: () => ({ notify: vi.fn() }) }))
vi.mock('../lib/supabase', () => ({ supabase: { rpc: async (fn: string, args: Record<string, unknown>) => { h.rpc.push({ fn, args }); if (fn === 'export_record') return { error: h.exportError }; return { data: fn === 'report_compliance_performance' ? h.perf : h.pipe, error: null } } }, appEnv: 'test' }))
import { ReportsPage } from './ReportsPage'

const wrap = () => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><ReportsPage /></QueryClientProvider>)
const perf = (o: Record<string, unknown>) => ({ group_key: 'k', group_label: 'Pune', total: 4, completed: 3, completed_on_time: 2, completed_late: 1, overdue_open: 1, upcoming_open: 0, due_to_date: 4, on_time_to_date: 2, completed_to_date: 3, on_time_pct: 50, compliance_pct: 75, ...o })
const blobs: Blob[] = []
beforeEach(() => { blobs.length = 0; URL.createObjectURL = ((b: Blob) => { blobs.push(b); h.downloads.push('blob'); return 'blob:x' }) as typeof URL.createObjectURL; URL.revokeObjectURL = () => undefined; HTMLAnchorElement.prototype.click = () => undefined; h.rpc.length = 0; h.downloads.length = 0; h.exportError = null; h.perms = new Set(['compliance.read', 'licence.read', 'report.export']); h.perf = [perf({}), perf({ group_key: 'k2', group_label: 'Mumbai', total: 6, completed: 6, completed_on_time: 6, completed_late: 0, overdue_open: 0, on_time_to_date: 6, completed_to_date: 6, due_to_date: 6, on_time_pct: 100, compliance_pct: 100 })]; h.pipe = [] })

describe('Reports', () => {
  it('shows the breakdown with totals recomputed from counts and queries by the chosen dimension', async () => {
    wrap(); expect(await screen.findByText('Pune')).toBeInTheDocument(); expect(screen.getByText('Mumbai')).toBeInTheDocument()
    expect(h.rpc[0].fn).toBe('report_compliance_performance'); expect(h.rpc[0].args).toMatchObject({ p_dimension: 'month' })
    const total = screen.getByText('Total').closest('tr')!; expect(total).toHaveTextContent('10'); expect(total).toHaveTextContent('80.0%')     // (2+6)/(4+6), not the average of 50% and 100%
    fireEvent.change(screen.getByLabelText('Group by'), { target: { value: 'location' } }); await waitFor(() => expect(h.rpc.some((r) => r.args.p_dimension === 'location')).toBe(true))
  })
  it('an invalid period is explained and nothing is queried', async () => {
    wrap(); await screen.findByText('Pune'); h.rpc.length = 0; fireEvent.change(screen.getByLabelText('Due from'), { target: { value: '2999-01-01' } })
    expect(await screen.findByText(/start date is after the end date/)).toBeInTheDocument(); await new Promise((r) => setTimeout(r, 30)); expect(h.rpc).toHaveLength(0)
  })
  it('export logs first and then downloads the visible rows plus the total, formulas neutralised', async () => {
    h.perf = [perf({ group_label: '=HYPERLINK("x")' })]; wrap(); await screen.findByText('=HYPERLINK("x")'); fireEvent.click(screen.getByRole('button', { name: 'Export CSV' }))
    await waitFor(() => expect(h.downloads).toHaveLength(1)); const log = h.rpc.find((r) => r.fn === 'export_record')!; expect(log.args).toMatchObject({ p_register: 'report-compliance-performance', p_row_count: 2, p_limit_reached: false }); expect(await blobs[0].text()).toContain("'=HYPERLINK")
  })
  it('if the export cannot be logged, nothing is downloaded', async () => {
    h.exportError = { message: 'denied' }; wrap(); await screen.findByText('Pune'); fireEvent.click(screen.getByRole('button', { name: 'Export CSV' })); await waitFor(() => expect(h.rpc.some((r) => r.fn === 'export_record')).toBe(true)); await new Promise((r) => setTimeout(r, 30)); expect(h.downloads).toHaveLength(0)
  })
  it('without report.export there is no Export button', async () => { h.perms = new Set(['compliance.read']); wrap(); await screen.findByText('Pune'); expect(screen.queryByRole('button', { name: 'Export CSV' })).toBeNull() })
  it('the licence pipeline tab pivots expiry buckets by type', async () => {
    h.pipe = [{ bucket: 'expired', licence_type_code: 'FAC', licence_type_name: 'Factory licence', licences: 2 }, { bucket: '2026-12', licence_type_code: 'FAC', licence_type_name: 'Factory licence', licences: 1 }]
    wrap(); fireEvent.click(await screen.findByRole('tab', { name: 'Licence expiry pipeline' })); expect(await screen.findByText('Already expired')).toBeInTheDocument(); expect(screen.getByText('Factory licence')).toBeInTheDocument(); expect(screen.getByText('2026-12')).toBeInTheDocument()
  })
  it('a user with neither read permission sees no reports', () => { h.perms = new Set(); wrap(); expect(screen.getByText('No reports available')).toBeInTheDocument() })
})
