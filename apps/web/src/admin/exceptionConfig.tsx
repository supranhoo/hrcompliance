import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Badge, ErrorState, Skeleton } from '../components/ui'
import { supabase } from '../lib/supabase'
import { LovValues } from './lov'
import { SettingsPanel } from './SettingsPage'

function ListEditor({ code, title, help }: { code: string; title: string; help: string }) {
  const q = useQuery({ queryKey: ['lov-set-id', code], enabled: !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('lov_set').select('id,code,is_system').eq('code', code).maybeSingle(); if (error) throw error; return data as { id: string; code: string; is_system: boolean } | null } })
  if (q.isLoading) return <Skeleton rows={3} />; if (q.error) return <ErrorState message={(q.error as Error).message} />
  if (!q.data) return <p className="text-sm text-muted">{title}: list {code} is not present in this environment.</p>
  return <section className="space-y-2 rounded-lg border border-line bg-white p-4"><h2 className="text-base font-semibold">{title}</h2><p className="text-sm text-muted">{help}</p><LovValues setId={q.data.id} setCode={q.data.code} isSystem={q.data.is_system} /></section>
}

/** Exception behaviour in one place: service levels and ageing (settings), severities and categories (lists), and the unroutable-alert visibility (D-001). */
export function ExceptionConfigPage() {
  const health = useQuery({ queryKey: ['system-health'], enabled: !!supabase, retry: false, queryFn: async () => { const { data, error } = await supabase!.rpc('system_health'); if (error) throw error; return data as { unroutable_alerts?: number } } })
  return (
    <section className="space-y-6">
      <div><h1 className="text-xl font-semibold text-navy">Exception Settings</h1>
        <p className="text-sm text-muted">Service levels and ageing, severities and categories. Ageing buckets (0–7, 8–30, 31–90, 90+ days) and “target breached” are derived from the resolution targets below. Default values are development settings, not BFCL policy.</p></div>
      <section className="space-y-2 rounded-lg border border-line bg-white p-4">
        <h2 className="text-base font-semibold">Unroutable alerts</h2>
        <p className="text-sm text-muted">Alerts that reach nobody raise an <strong>alert_unroutable</strong> exception. Configure who is told in <Link className="text-blue underline" to="/admin/alert-rules">Alert Rules → escalation recipients</Link>; see them in <Link className="text-blue hover:underline" to="/exceptions?category=alert_unroutable">Exceptions</Link>, <Link className="text-blue hover:underline" to="/admin/system-health">System Health</Link> and the <Link className="text-blue hover:underline" to="/notifications">Notification Centre</Link>.</p>
        {typeof health.data?.unroutable_alerts === 'number' && <Badge tone={health.data.unroutable_alerts ? 'crit' : 'ok'}>{health.data.unroutable_alerts} open unroutable alert(s)</Badge>}
      </section>
      <div><h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted">Service levels (SLA) & ageing</h2><SettingsPanel only={['Exceptions']} /></div>
      <ListEditor code="SEVERITY" title="Severities" help="Used by exceptions and by the SLA table above. The four built-in severities are used by platform logic and cannot be deactivated." />
      <ListEditor code="EXCEPTION_CATEGORY" title="Exception categories" help="Categories raised by the engines are protected; labels, colours and order can be edited and manual categories added." />
    </section>
  )
}
