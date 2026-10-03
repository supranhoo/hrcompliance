import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { z } from 'zod'
import { supabase } from '../lib/supabase'
import { useAuth } from '../app/AuthProvider'
import { can } from '../lib/access'
import { Badge, EmptyState, ErrorState, Skeleton } from '../components/ui'
import { categoryLabel, categoryTone, linkFor, NOTIFICATION_COLUMNS, notificationSchema, unroutableRowSchema, type AppNotification } from '../lib/notifications'

export const NOTIFICATIONS_KEY = ['notifications'] as const
export const UNREAD_KEY = ['notifications', 'unread'] as const

export function NotificationsView({ items, unroutable, onRead, onReadAll, busy }: {
  items: AppNotification[]; unroutable: Array<z.infer<typeof unroutableRowSchema>>
  onRead: (id: string, read: boolean) => void; onReadAll: () => void; busy?: boolean
}) {
  const unread = items.filter((n) => !n.read_at).length
  return (
    <section className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-navy">Notification Centre</h1>
        <button type="button" disabled={busy || unread === 0} onClick={onReadAll} className="rounded border border-line bg-white px-3 py-1.5 text-sm hover:bg-canvas disabled:opacity-50">Mark all as read</button>
      </div>
      {unroutable.length > 0 && (
        <div role="alert" className="rounded-lg border border-status-crit bg-white p-4">
          <h2 className="text-sm font-semibold text-status-crit">Unroutable alerts ({unroutable.length}) — nobody can currently be told</h2>
          <p className="mt-1 text-sm text-muted">These obligations or licences have an alert rule with no valid recipient and no escalation recipient is configured. Assign an owner or configure routing.</p>
          <ul className="mt-2 space-y-1 text-sm">
            {unroutable.map((u) => <li key={u.id}><Link className="text-brand hover:underline" to="/exceptions?category=alert_unroutable">{u.exception_no}</Link> · {u.description}</li>)}
          </ul>
        </div>
      )}
      {items.length === 0 ? <EmptyState title="No notifications" description="Reminders, escalations and licence-expiry alerts addressed to you appear here." /> : (
        <ul className="divide-y divide-line rounded-lg border border-line bg-white" aria-label="Notifications">
          {items.map((n) => (
            <li key={n.id} className={n.read_at ? 'p-3' : 'bg-blue-50/40 p-3'}>
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={categoryTone(n.category)}>{categoryLabel[n.category]}</Badge>
                <span className={n.read_at ? 'text-sm' : 'text-sm font-semibold'}>{n.title}</span>
                <span className="ml-auto text-xs text-muted">{new Date(n.created_at).toLocaleString()}</span>
              </div>
              {n.body && <p className="mt-1 text-sm text-muted">{n.body}</p>}
              <div className="mt-1 flex gap-3 text-xs">
                <Link className="text-brand hover:underline" to={linkFor(n)}>Open register</Link>
                <button type="button" className="text-muted hover:underline" onClick={() => onRead(n.id, !n.read_at)}>{n.read_at ? 'Mark unread' : 'Mark read'}</button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

export function NotificationsPage() {
  const { access } = useAuth(); const qc = useQueryClient()
  const list = useQuery({
    queryKey: NOTIFICATIONS_KEY,
    queryFn: async () => {
      if (!supabase) throw new Error('Supabase is not configured')
      const { data, error } = await supabase.from('notification').select(NOTIFICATION_COLUMNS).eq('channel', 'in_app').order('created_at', { ascending: false }).range(0, 99)
      if (error) throw error
      return z.array(notificationSchema).parse(data)
    },
  })
  const showUnroutable = can(access, 'exception.read')
  const unroutable = useQuery({
    queryKey: ['notifications', 'unroutable'], enabled: showUnroutable,
    queryFn: async () => {
      if (!supabase) throw new Error('Supabase is not configured')
      const { data, error } = await supabase.from('v_exception').select('id,exception_no,description,severity,detected_at').eq('category', 'alert_unroutable').in('status', ['open', 'acknowledged']).order('detected_at', { ascending: false }).limit(20)
      if (error) throw error
      return z.array(unroutableRowSchema).parse(data)
    },
  })
  const mark = useMutation({
    mutationFn: async (v: { id?: string; read: boolean }) => {
      if (!supabase) throw new Error('Supabase is not configured')
      const stamp = v.read ? new Date().toISOString() : null
      let q = supabase.from('notification').update({ read_at: stamp })
      q = v.id ? q.eq('id', v.id) : q.is('read_at', null).eq('channel', 'in_app')
      const { error } = await q; if (error) throw error
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: NOTIFICATIONS_KEY }) },
  })
  if (list.isLoading) return <Skeleton rows={5} />
  if (list.error) return <ErrorState message={(list.error as Error).message} onRetry={() => void list.refetch()} />
  return <NotificationsView items={list.data ?? []} unroutable={unroutable.data ?? []} busy={mark.isPending}
    onRead={(id, read) => mark.mutate({ id, read })} onReadAll={() => mark.mutate({ read: true })} />
}
