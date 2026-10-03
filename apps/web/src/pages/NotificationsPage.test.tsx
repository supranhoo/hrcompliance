import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { NotificationsView } from './NotificationsPage'
import { notificationSchema, unreadLabel, linkFor, categoryTone } from '../lib/notifications'

const n = (o: Partial<Record<string, unknown>> = {}) => notificationSchema.parse({ id: 'n1', category: 'compliance_reminder', title: 'PF-MONTHLY due in 3 day(s)', body: 'CMP-2026-000001 - due 2026-10-06', link_kind: 'compliance_instance', link_id: 'i1', created_at: '2026-10-03T08:00:00Z', read_at: null, ...o })
const view = (items = [n()], unroutable: Array<{ id: string; exception_no: string; description: string; severity: string; detected_at: string }> = [], cb: Partial<{ onRead: (id: string, r: boolean) => void; onReadAll: () => void }> = {}) =>
  render(<MemoryRouter><NotificationsView items={items} unroutable={unroutable} onRead={cb.onRead ?? vi.fn()} onReadAll={cb.onReadAll ?? vi.fn()} /></MemoryRouter>)

describe('Notification Centre', () => {
  it('lists notifications with category, title and body', () => {
    view(); expect(screen.getByText('PF-MONTHLY due in 3 day(s)')).toBeInTheDocument(); expect(screen.getByText('Reminder')).toBeInTheDocument(); expect(screen.getByText(/CMP-2026-000001/)).toBeInTheDocument()
  })
  it('says so when empty', () => { view([]); expect(screen.getByText('No notifications')).toBeInTheDocument() })
  it('marks read/unread and all-read through callbacks (server enforces own-row RLS)', () => {
    const onRead = vi.fn(), onReadAll = vi.fn(); view([n(), n({ id: 'n2', read_at: '2026-10-03T09:00:00Z' })], [], { onRead, onReadAll })
    fireEvent.click(screen.getByRole('button', { name: 'Mark read' })); expect(onRead).toHaveBeenCalledWith('n1', true)
    fireEvent.click(screen.getByRole('button', { name: 'Mark unread' })); expect(onRead).toHaveBeenCalledWith('n2', false)
    fireEvent.click(screen.getByRole('button', { name: 'Mark all as read' })); expect(onReadAll).toHaveBeenCalled()
  })
  it('"Mark all as read" is disabled when nothing is unread', () => { view([n({ read_at: '2026-10-03T09:00:00Z' })]); expect(screen.getByRole('button', { name: 'Mark all as read' })).toBeDisabled() })
  it('unrouted alerts are marked as such and the unroutable exceptions are surfaced prominently (D-001)', () => {
    view([n({ category: 'alert_unroutable', title: 'UNROUTED: PF due today' })], [{ id: 'e1', exception_no: 'EXC-2026-000009', description: 'Alerts cannot reach anyone', severity: 'high', detected_at: '2026-10-03T08:00:00Z' }])
    expect(screen.getByText('Unrouted alert')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent('Unroutable alerts (1)')
    expect(screen.getByRole('link', { name: 'EXC-2026-000009' })).toHaveAttribute('href', '/exceptions?category=alert_unroutable')
  })
  it('helpers: label, link target, tone', () => {
    expect(unreadLabel(0)).toBe('Notifications'); expect(unreadLabel(3)).toBe('Notifications (3 unread)'); expect(unreadLabel(250)).toBe('Notifications (99+ unread)')
    expect(linkFor({ link_kind: 'licence', body: null })).toBe('/licences'); expect(linkFor({ link_kind: 'compliance_instance', body: null })).toBe('/compliance')
    expect(categoryTone('alert_unroutable')).toBe('crit')
  })
  it('rejects an unknown category instead of rendering garbage', () => { expect(() => n({ category: 'sms' })).toThrow() })
})
