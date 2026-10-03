import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { isoDate } from '../lib/urlFilters'

const rpc = vi.hoisted(() => vi.fn())
vi.mock('../lib/supabase', () => ({ supabase: { rpc } }))
import { CalendarPage } from './CalendarPage'

const today = new Date(); const t = isoDate(today)
const item = (id: string, due: string, state: string) => ({ instance_id: id, instance_no: 'CMP-2026-00000' + id, compliance_code: 'PF-' + id, compliance_name: 'Return ' + id, location_code: 'L-E1', due_date: due, status: 'open', due_state: state, risk_level: 'high' })
const renderPage = () => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><MemoryRouter><CalendarPage /></MemoryRouter></QueryClientProvider>)

describe('CalendarPage', () => {
  beforeEach(() => { rpc.mockReset(); rpc.mockResolvedValue({ data: [item('1', t, 'due_soon'), item('2', t, 'overdue')], error: null }) })
  it('asks the server for exactly the visible month range (6 weeks, Monday first)', async () => {
    renderPage(); await waitFor(() => expect(rpc).toHaveBeenCalled())
    const [name, args] = rpc.mock.calls[0]; expect(name).toBe('compliance_calendar')
    expect(new Date(args.p_from + 'T00:00:00').getDay()).toBe(1); expect((new Date(args.p_to + 'T00:00:00').getTime() - new Date(args.p_from + 'T00:00:00').getTime()) / 86400000).toBe(41)
  })
  it('renders items on their due date and opens the day panel on click', async () => {
    renderPage(); const day = await screen.findByLabelText(`${t}, 2 item(s)`)
    fireEvent.click(day); expect(await screen.findByText('Return 1')).toBeInTheDocument(); expect(screen.getByText('Return 2')).toBeInTheDocument()
    expect(screen.getAllByText('Overdue').length).toBeGreaterThan(0)
    expect(screen.getAllByRole('link', { name: 'Open in register' })[0]).toHaveAttribute('href', expect.stringContaining('/compliance?q=CMP-2026-'))
  })
  it('switching view re-queries the server for the new range', async () => {
    renderPage(); await waitFor(() => expect(rpc).toHaveBeenCalledTimes(1))
    fireEvent.click(screen.getByRole('button', { name: 'Agenda' })); await waitFor(() => expect(rpc).toHaveBeenCalledTimes(2))
    expect(rpc.mock.calls[1][1].p_from).toBe(t)
    expect(await screen.findByText('Return 1')).toBeInTheDocument()
  })
  it('navigating months re-queries', async () => {
    renderPage(); await waitFor(() => expect(rpc).toHaveBeenCalledTimes(1)); fireEvent.click(screen.getByRole('button', { name: 'Next' })); await waitFor(() => expect(rpc).toHaveBeenCalledTimes(2))
    expect(rpc.mock.calls[1][1].p_from).not.toBe(rpc.mock.calls[0][1].p_from)
  })
  it('shows an error state with retry when the server call fails', async () => {
    rpc.mockResolvedValue({ data: null, error: new Error('permission denied') }); renderPage()
    expect(await screen.findByRole('alert')).toHaveTextContent('permission denied')
  })
  it('legend names every state (colour is never the only signal)', async () => {
    renderPage(); await screen.findByLabelText(`${t}, 2 item(s)`); const legend = screen.getByRole('list', { name: 'Legend' })
    for (const s of ['Overdue', 'Due soon', 'Upcoming', 'Completed', 'Not applicable']) expect(legend).toHaveTextContent(s)
  })
})
