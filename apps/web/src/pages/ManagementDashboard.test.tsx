import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const E1 = '11111111-1111-1111-1111-111111111111'; const D1 = '33333333-3333-3333-3333-333333333333'
const h = vi.hoisted(() => ({ rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, payload: {} as Record<string, unknown>, error: null as null | { message: string } }))
vi.mock('../lib/supabase', () => ({ supabase: { rpc: async (fn: string, args: Record<string, unknown>) => { h.rpc.push({ fn, args }); return h.error ? { data: null, error: h.error } : { data: h.payload, error: null } } }, appEnv: 'test' }))
vi.mock('../admin/lookups', () => ({ useLookup: (l?: { table: string }) => ({ data: l?.table === 'entity' ? [{ value: E1, label: 'BFCL Ltd' }] : l?.table === 'department' ? [{ value: D1, label: 'Finance' }] : l?.table === 'location' ? [{ value: '22222222-2222-2222-2222-222222222222', label: 'Pune' }] : [] }) }))
import { ManagementDashboard } from './ManagementDashboard'

const base = () => ({
  generated_at: '2026-10-04T10:00:00Z', period: { from: '2025-10-04', to: '2026-10-04' }, filters: { entity_id: null, location_id: null, department_id: null }, top_risk_level: 'critical', top_severity: 'critical',
  kpis: { total_applicable: 120, due_this_month: 14, overdue: 6, critical_open: 9, critical_overdue: 2, due_to_date: 100, completed_to_date: 88, on_time_to_date: 80, compliance_pct: 88, on_time_pct: 80, open_exceptions: 11, critical_exceptions: 3, licences_expiring: 5, licences_expired: 1 },
  licences: { expiring: 5, expired: 1, horizon_days: 90, department_filter_applies: false },
  trend: [{ month: '2026-08', due: 10, completed_on_time: 7, completed_late: 1, overdue_open: 2, upcoming_open: 0, due_to_date: 10, compliance_pct: 80 }, { month: '2026-09', due: 12, completed_on_time: 9, completed_late: 1, overdue_open: 1, upcoming_open: 1, due_to_date: 11, compliance_pct: 90.9 }],
  risk: [{ level: 'low', label: 'Low', sort_order: 10, open: 3, overdue: 0 }, { level: 'critical', label: 'Critical', sort_order: 40, open: 9, overdue: 2 }],
  by_location: [{ code: 'PUN', name: 'Pune', total: 40, open: 8, overdue: 4, due_to_date: 35, completed_to_date: 30, compliance_pct: 85.7 }],
  by_department: [{ id: D1, name: 'Finance', total: 30, open: 5, overdue: 2, due_to_date: 28, completed_to_date: 25, compliance_pct: 89.3 }, { id: null, name: '(no responsible department)', total: 10, open: 1, overdue: 0, due_to_date: 9, completed_to_date: 9, compliance_pct: 100 }],
  upcoming: [{ instance_no: 'CMP-1', compliance_code: 'PF', compliance_name: 'PF return', location_code: 'PUN', due_date: '2026-10-10', risk_level: 'high', due_state: 'due_soon' }],
  critical_exceptions: [{ id: 'x1', exception_no: 'EXC-9', category: 'overdue', severity: 'critical', description: 'Filing not made', age_days: 12, target_breached: true, location_code: 'PUN' }],
  exception_ageing: { '0-7': 2, '31-90': 1 }, definitions: { overdue: 'x' },
})
const kpi = (label: string) => screen.getAllByText(label).map((e) => e.closest('button')).find((b): b is HTMLButtonElement => !!b)!
const Loc = () => { const l = useLocation(); return <output data-testid="loc">{l.pathname + l.search}</output> }
const wrap = (url = '/') => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><MemoryRouter initialEntries={[url]}><ManagementDashboard /><Loc /></MemoryRouter></QueryClientProvider>)
beforeEach(() => { h.rpc.length = 0; h.error = null; h.payload = base() })

describe('Management dashboard', () => {
  it('shows the requested KPIs and reads figures straight from the database result', async () => {
    wrap(); expect(await screen.findByText('Total applicable')).toBeInTheDocument()
    for (const [label, value] of [['Total applicable', '120'], ['Due this month', '14'], ['Overdue', '6'], ['Critical', '9'], ['Open exceptions', '11'], ['Licences expiring', '5']]) expect(kpi(label)).toHaveTextContent(value)
    expect(h.rpc[0].fn).toBe('management_dashboard'); expect(h.rpc[0].args).toMatchObject({ p_entity: null, p_location: null, p_department: null })
    expect(screen.getByText(/Compliance 88.0%|Compliance 88%/)).toBeInTheDocument()
  })
  it('no invented thresholds: a percentage never turns the card green/amber/red', async () => {
    wrap(); await screen.findByText('Total applicable'); expect(kpi('Total applicable').innerHTML).not.toMatch(/status-(ok|warn|crit)/)
  })
  it('status colours appear only where meaningful (overdue / critical exceptions)', async () => {
    const first = wrap(); await screen.findByText('Total applicable'); expect(kpi('Overdue').innerHTML).toMatch(/status-crit/); first.unmount()
    h.payload = { ...base(), kpis: { ...base().kpis, overdue: 0, critical_overdue: 0, critical_exceptions: 0 } }; wrap('/?period=6m'); await waitFor(() => expect(kpi('Overdue').innerHTML).not.toMatch(/status-crit/))
  })
  it('KPIs drill into the existing registers with the dashboard filters carried over', async () => {
    wrap(`/?entity=${E1}&department=${D1}`); await screen.findByText('Total applicable')
    fireEvent.click(kpi('Overdue')); expect(screen.getByTestId('loc')).toHaveTextContent(`/compliance?due_state=overdue&entity_id=${E1}&owner_department_id=${D1}`)
  })
  it('Critical drills to open obligations at the top risk level (from the list, not a hardcoded name)', async () => {
    wrap(); await screen.findByText('Total applicable'); fireEvent.click(kpi('Critical')); expect(screen.getByTestId('loc')).toHaveTextContent('/compliance?status=active&risk_level=critical')
  })
  it('exceptions and licences drill with the filters their registers support (no department on licences)', async () => {
    wrap(`/?entity=${E1}&department=${D1}`); await screen.findByText('Total applicable')
    fireEvent.click(kpi('Licences expiring')); expect(screen.getByTestId('loc')).toHaveTextContent(`/licences?entity_id=${E1}`); expect(screen.getByTestId('loc')).not.toHaveTextContent('department')
  })
  it('changing a filter writes it to the URL and re-queries; the entity change clears the location', async () => {
    wrap(); await screen.findByText('Total applicable'); fireEvent.change(screen.getByLabelText('Entity'), { target: { value: E1 } })
    await waitFor(() => expect(h.rpc.some((r) => r.args.p_entity === E1)).toBe(true)); expect(screen.getByTestId('loc')).toHaveTextContent(`entity=${E1}`)
    fireEvent.change(screen.getByLabelText('Department'), { target: { value: D1 } }); await waitFor(() => expect(h.rpc.some((r) => r.args.p_department === D1)).toBe(true))
    fireEvent.click(screen.getByRole('button', { name: 'Clear filters' })); expect(screen.getByTestId('loc')).toHaveTextContent(/^\/$/)
  })
  it('a custom period is validated before anything is queried', async () => {
    wrap('/?period=custom&from=2026-03-01&to=2026-01-01'); expect(await screen.findByRole('alert')).toHaveTextContent(/start date is after the end date/); await new Promise((r) => setTimeout(r, 30)); expect(h.rpc).toHaveLength(0)
  })
  it('renders trend (with an accessible table), risk, location, department, upcoming, critical exceptions and ageing', async () => {
    wrap(); await screen.findByText('Compliance trend'); expect(screen.getByRole('img', { name: /2026-09: 12 due, 9 on time, 1 late, 1 overdue/ })).toBeInTheDocument()
    expect(within(screen.getByRole('table', { name: /by due month/i, hidden: true })).getByText('2026-08')).toBeInTheDocument()
    expect(screen.getByText('Risk distribution')).toBeInTheDocument(); expect(screen.getAllByRole('link').some((a) => a.getAttribute('href') === '/compliance?status=active&risk_level=critical' && /Critical/.test(a.textContent ?? ''))).toBe(true)
    expect(screen.getByRole('link', { name: 'PUN · Pune' })).toHaveAttribute('href', '/compliance?location_code=PUN')
    expect(screen.getByRole('link', { name: 'Finance' })).toHaveAttribute('href', `/compliance?owner_department_id=${D1}`); expect(screen.getByText('(no responsible department)')).toBeInTheDocument(); expect(screen.queryByRole('link', { name: '(no responsible department)' })).toBeNull()
    expect(screen.getByRole('link', { name: /PF return/ })).toHaveAttribute('href', '/compliance?q=CMP-1'); expect(screen.getByRole('link', { name: /EXC-9/ })).toHaveAttribute('href', '/exceptions?q=EXC-9')
    expect(screen.getByRole('link', { name: /0-7 days/ })).toHaveAttribute('href', '/exceptions?status=open&age_bucket=0-7'); expect(screen.getByRole('link', { name: 'Open the compliance calendar' })).toHaveAttribute('href', '/calendar')
  })
  it('an empty scope says so instead of showing zeros as if measured', async () => {
    h.payload = { ...base(), kpis: { ...base().kpis, total_applicable: 0, overdue: 0, open_exceptions: 0, critical_open: 0, critical_overdue: 0, critical_exceptions: 0, due_this_month: 0, licences_expiring: 0, licences_expired: 0, compliance_pct: null, on_time_pct: null }, licences: { ...base().licences, expiring: 0 }, trend: [], upcoming: [], critical_exceptions: [], by_location: [], by_department: [] }
    wrap(); expect(await screen.findByText('Nothing to show for these filters')).toBeInTheDocument(); expect(screen.getByText(/Compliance —/)).toBeInTheDocument()
  })
  it('database errors are shown with a retry, not swallowed', async () => { h.error = { message: 'permission denied' }; wrap(); expect(await screen.findByText(/permission denied/)).toBeInTheDocument() })
})
