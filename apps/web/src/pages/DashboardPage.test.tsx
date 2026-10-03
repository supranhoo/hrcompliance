import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { DashboardView } from './DashboardPage'
import { dashboardSchema, type Dashboard } from '../lib/dashboard'
import sample from '../lib/fixtures/dashboard.json'

const real = dashboardSchema.parse(sample)
const empty: Dashboard = { ...real, has_data: false,
  obligations: { total: 0, completed: 0, open: 0, overdue: 0, due_soon: 0, upcoming_30_days: 0, completed_late: 0, due_so_far: 0, compliance_pct: null, on_time_pct: null, overdue_by_risk: {} },
  exceptions: { open: 0, critical_open: 0, target_breached: 0, by_severity: {}, by_age: {}, by_category: {} }, evidence: { missing: 0, pending_review: 0, rejected: 0, expired: 0 },
  licences: { active: 0, expired: 0, renewal_window_open: 0, by_category: {} }, by_location: [], next_due: [] }
const view = (d: Dashboard, nav?: (to: string) => void) => render(<MemoryRouter><DashboardView d={d} nav={nav} /></MemoryRouter>)

describe('DashboardView', () => {
  const tile = (name: RegExp) => screen.getByRole('button', { name })
  it('shows the server numbers exactly as returned (no client-side computation)', () => {
    view(real, vi.fn())
    expect(tile(/^Overdue/)).toHaveTextContent(String(real.obligations.overdue))
    expect(tile(/^Critical exceptions/)).toHaveTextContent(String(real.exceptions.critical_open))
    expect(tile(/^Due soon/)).toHaveTextContent(String(real.obligations.due_soon))
    expect(tile(/^Next 30 days/)).toHaveTextContent(String(real.obligations.upcoming_30_days))
  })
  it('KPI tiles drill down to the filtered register', () => {
    const nav = vi.fn(); view(real, nav)
    fireEvent.click(tile(/^Overdue/)); expect(nav).toHaveBeenLastCalledWith('/compliance?due_state=overdue')
    fireEvent.click(tile(/^Critical exceptions/)); expect(nav).toHaveBeenLastCalledWith('/exceptions?severity=critical&status=open')
    fireEvent.click(tile(/^Next 30 days/)); expect(nav).toHaveBeenLastCalledWith('/compliance?due_within=30')
    fireEvent.click(tile(/^Due soon/)); expect(nav).toHaveBeenLastCalledWith('/compliance?due_state=due_soon')
  })
  it('sections link to filtered registers', () => {
    view(real)
    const hrefs = screen.getAllByRole('link').map((a) => a.getAttribute('href'))
    expect(hrefs).toContain('/exceptions?target_breached=true'); expect(hrefs).toContain('/licences?renewal_window_open=true'); expect(hrefs).toContain('/evidence?evidence_state=missing')
  })
  it('with nothing to measure it says so: percentages are "—", never a fabricated 0% or 100%', () => {
    view(empty)
    expect(screen.getByText('No compliance data in your scope yet')).toBeInTheDocument()
    expect(screen.getAllByText('—').length).toBeGreaterThanOrEqual(2)
    expect(screen.queryByText('0%')).toBeNull(); expect(screen.queryByText('100%')).toBeNull()
    expect(screen.getByText('Nothing due yet')).toBeInTheDocument()
  })
  it('states how compliance % is defined next to the number', () => { view(real); expect(screen.getByText(/Completed obligations as a share of obligations already due/)).toBeInTheDocument() })
})
