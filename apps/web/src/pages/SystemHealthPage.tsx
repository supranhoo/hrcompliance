import { useQuery } from '@tanstack/react-query'
import { z } from 'zod'
import { supabase, appEnv } from '../lib/supabase'
import { Badge, ErrorState, KpiCard, Skeleton, type Tone } from '../components/ui'
import { getServices } from '../services'
import { useNavigate } from 'react-router-dom'

const jobSchema = z.object({ job_code: z.string(), status: z.string(), started_at: z.string(), completed_at: z.string().nullable().optional(), records_processed: z.number().nullable().optional(), attempt: z.number().optional(), message: z.string().nullable().optional() }).nullable()
export const healthSchema = z.object({
  database: z.object({ connected: z.boolean(), server_time: z.string(), postgres_major: z.number() }),
  schema_version: z.string().nullable(),
  integrations: z.record(z.string(), z.string()),
  latest_job: jobSchema, latest_failed_job: jobSchema, jobs_failed_24h: z.number(),
  // added by migration 0023 (D-001); optional so an older deployment still renders
  unroutable_alerts: z.number().default(0),
  unroutable_notifications_7d: z.number().default(0),
  alert_routing: z.object({ errors: z.number(), warnings: z.number() }).default({ errors: 0, warnings: 0 }),
  latest_job_warning: z.object({ job_code: z.string(), started_at: z.string(), message: z.string().nullable().optional() }).nullable().default(null),
  environment: z.string().default('unknown'),
})
export type Health = z.infer<typeof healthSchema>
export const integrationTone = (s?: string): Tone => (s === 'CONFIGURED' ? 'ok' : s === 'ERROR' ? 'crit' : 'warn')

export function SystemHealthPage() {
  const nav = useNavigate()
  const q = useQuery({
    queryKey: ['system-health'], refetchInterval: 60_000,
    queryFn: async () => {
      if (!supabase) throw new Error('Supabase is not configured')
      const { data, error } = await supabase.rpc('system_health'); if (error) throw error
      return healthSchema.parse(data)
    },
  })
  const adapters = useQuery({ queryKey: ['adapter-status'], queryFn: async () => { const s = getServices(); return { storage: (await s.storage.status()).state, mail: (await s.mail.status()).state } } })
  if (q.isLoading) return <Skeleton rows={4} />
  if (q.error) return <ErrorState message={(q.error as Error).message} onRetry={() => void q.refetch()} />
  const h = q.data!
  const drive = adapters.data?.storage ?? h.integrations.google_drive, mail = adapters.data?.mail ?? h.integrations.gmail
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-semibold text-navy">System Health</h1>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Database" value={h.database.connected ? 'Connected' : 'Down'} tone={h.database.connected ? 'ok' : 'crit'} hint={`PostgreSQL ${h.database.postgres_major}`} />
        <KpiCard label="Environment" value={appEnv} hint={`Web v${__APP_VERSION__}`} />
        <KpiCard label="Schema version" value={h.schema_version ?? 'n/a'} />
        <KpiCard label="Failed jobs (24h)" value={h.jobs_failed_24h} tone={h.jobs_failed_24h > 0 ? 'crit' : 'ok'} />
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Unroutable alerts" value={h.unroutable_alerts} tone={h.unroutable_alerts > 0 ? 'crit' : 'ok'} hint="Nobody can be told — see Exceptions" onClick={() => nav('/exceptions?category=alert_unroutable')} />
        <KpiCard label="Alert routing errors" value={h.alert_routing.errors} tone={h.alert_routing.errors > 0 ? 'crit' : 'ok'} hint={`${h.alert_routing.warnings} warning(s)`} />
        <KpiCard label="Unrouted alerts sent (7d)" value={h.unroutable_notifications_7d} tone={h.unroutable_notifications_7d > 0 ? 'warn' : 'ok'} hint="Delivered to escalation recipients" />
        <KpiCard label="Alert fallback" value={h.environment === 'development' ? 'Super Admin (dev)' : 'Escalation rule'} hint="Super Admin fallback is development-only" />
      </div>
      {h.latest_job_warning && <p role="status" className="rounded border border-status-warn bg-white p-3 text-sm">Latest job warning: {h.latest_job_warning.job_code} · {h.latest_job_warning.message ?? 'see job log'}</p>}
      <div className="rounded-lg border border-line bg-white p-4">
        <h2 className="text-sm font-semibold">Integrations</h2>
        <ul className="mt-2 space-y-1 text-sm">
          <li className="flex items-center justify-between">Google Drive <Badge tone={integrationTone(drive)}>{drive.replace('_', ' ')}</Badge></li>
          <li className="flex items-center justify-between">Gmail <Badge tone={integrationTone(mail)}>{mail.replace('_', ' ')}</Badge></li>
        </ul>
      </div>
      <div className="grid gap-3 md:grid-cols-2">
        <div className="rounded-lg border border-line bg-white p-4 text-sm"><h2 className="font-semibold">Latest job</h2>{h.latest_job ? <p className="mt-1 text-muted">{h.latest_job.job_code} · {h.latest_job.status} · {new Date(h.latest_job.started_at).toLocaleString()}</p> : <p className="mt-1 text-muted">No job has run yet.</p>}</div>
        <div className="rounded-lg border border-line bg-white p-4 text-sm"><h2 className="font-semibold">Latest failed job</h2>{h.latest_failed_job ? <p className="mt-1 text-status-crit">{h.latest_failed_job.job_code} · {h.latest_failed_job.message ?? h.latest_failed_job.status}</p> : <p className="mt-1 text-muted">None.</p>}</div>
      </div>
    </section>
  )
}
