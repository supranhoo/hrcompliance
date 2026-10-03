import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({ rpc: vi.fn(), trans: { data: [] as Array<{ to: string; label: string; requiresReason: boolean }>, isLoading: false } }))
vi.mock('../lib/supabase', () => ({ supabase: { rpc: h.rpc } }))
vi.mock('../hooks/useLookups', () => ({ useTransitions: () => h.trans }))
vi.mock('../app/Toasts', () => ({ useToast: () => ({ notify: vi.fn() }) }))
import { StatusActions } from './StatusActions'

const setup = (rpc: 'compliance_set_status' | 'exception_set_status' = 'compliance_set_status', resolution = false) =>
  render(<QueryClientProvider client={new QueryClient()}><StatusActions module="compliance" current="open" recordId="rec-1" rpc={rpc} noteIsResolution={resolution} /></QueryClientProvider>)
beforeEach(() => { h.rpc.mockReset(); h.rpc.mockResolvedValue({ error: null }); h.trans.data = [{ to: 'in_progress', label: 'In progress', requiresReason: false }, { to: 'not_applicable', label: 'Not applicable', requiresReason: true }, { to: 'resolved', label: 'Resolved', requiresReason: false }] })

describe('StatusActions', () => {
  it('offers only the configured transitions and flags those needing a reason', () => {
    setup(); const opts = Array.from((screen.getByLabelText('Change status to') as HTMLSelectElement).options).map((o) => o.text)
    expect(opts).toEqual(['Select…', 'In progress', 'Not applicable (reason required)', 'Resolved'])
  })
  it('a plain transition needs no reason and sends the right RPC arguments', async () => {
    setup(); fireEvent.change(screen.getByLabelText('Change status to'), { target: { value: 'in_progress' } })
    expect(screen.queryByLabelText(/Reason/)).toBeNull(); fireEvent.click(screen.getByText('Apply'))
    await waitFor(() => expect(h.rpc).toHaveBeenCalledWith('compliance_set_status', { p_instance: 'rec-1', p_status: 'in_progress', p_reason: null }))
  })
  it('a reason-required transition blocks Apply until a reason is typed, then sends it', async () => {
    setup(); fireEvent.change(screen.getByLabelText('Change status to'), { target: { value: 'not_applicable' } })
    expect(screen.getByText('Apply')).toBeDisabled()
    fireEvent.change(screen.getByLabelText(/Reason/), { target: { value: '   ' } }); expect(screen.getByText('Apply')).toBeDisabled()
    fireEvent.change(screen.getByLabelText(/Reason/), { target: { value: 'site closed' } }); expect(screen.getByText('Apply')).toBeEnabled()
    fireEvent.click(screen.getByText('Apply'))
    await waitFor(() => expect(h.rpc).toHaveBeenCalledWith('compliance_set_status', { p_instance: 'rec-1', p_status: 'not_applicable', p_reason: 'site closed' }))
  })
  it('exceptions: resolving requires a resolution note and uses the exception RPC', async () => {
    setup('exception_set_status', true); fireEvent.change(screen.getByLabelText('Change status to'), { target: { value: 'resolved' } })
    expect(screen.getByLabelText(/Resolution/)).toBeInTheDocument(); expect(screen.getByText('Apply')).toBeDisabled()
    fireEvent.change(screen.getByLabelText(/Resolution/), { target: { value: 'fixed' } }); fireEvent.click(screen.getByText('Apply'))
    await waitFor(() => expect(h.rpc).toHaveBeenCalledWith('exception_set_status', { p_id: 'rec-1', p_status: 'resolved', p_note: 'fixed' }))
  })
  it('says so when no further transition is configured', () => { h.trans.data = []; setup(); expect(screen.getByText(/No further status changes/)).toBeInTheDocument() })
})
