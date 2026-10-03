import type { ReactNode } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Badge, Button, EmptyState, ErrorState, KpiCard, Skeleton, type Tone } from '../components/ui'
import { useDashboard } from '../hooks/useDashboard'
import { drill, fmtPct, type Dashboard } from '../lib/dashboard'
import { dueStateBadge, expiryBadge, severityTone, titleCase } from '../lib/badges'
import { UnauthorizedPage } from './Pages'

/** Single-hue proportional bars (no rainbow charts); each row drills down. Text carries the meaning, bars only the proportion. */
function BarList({ rows, href }: { rows: Array<{ key: string; label: string; value: number; tone?: Tone }>; href: (key: string) => string }) {
  const max = Math.max(1, ...rows.map((r) => r.value))
  if (rows.every((r) => r.value === 0)) return <p className="text-sm text-muted">None.</p>
  return (
    <ul className="space-y-2">
      {rows.filter((r) => r.value > 0).map((r) => (
        <li key={r.key}>
          <Link to={href(r.key)} className="group block">
            <div className="flex justify-between text-sm"><span className="text-ink group-hover:underline">{r.label}</span><span className="font-medium">{r.value}</span></div>
            <div className="mt-1 h-1.5 rounded bg-line" aria-hidden><div className={`h-1.5 rounded ${r.tone === 'crit' ? 'bg-status-crit' : r.tone === 'warn' ? 'bg-status-warn' : 'bg-blue'}`} style={{ width: `${(r.value / max) * 100}%` }} /></div>
          </Link>
        </li>
      ))}
    </ul>
  )
}
const Card = ({ title, children, hint }: { title: string; children: ReactNode; hint?: string }) => (
  <section className="rounded-lg border border-line bg-white p-4"><h2 className="text-sm font-semibold text-navy">{title}</h2>{hint && <p className="text-xs text-muted">{hint}</p>}<div className="mt-3">{children}</div></section>
)

const SEVERITY_ORDER = ['critical', 'high', 'medium', 'low']
const AGE_ORDER = ['0-7', '8-30', '31-90', '90+']

export function DashboardView({ d, nav }: { d: Dashboard; nav?: (to: string) => void }) {
  const o = d.obligations
  const go = (to: string) => nav ? () => nav(to) : undefined
  return (
    <div className="space-y-4">
      {!d.has_data && <EmptyState title="No compliance data in your scope yet" description="Figures appear here once obligations are generated for locations you can see. Nothing is estimated or pre-filled." />}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        <KpiCard label="Compliance" value={fmtPct(o.compliance_pct)} tone={o.compliance_pct === null ? 'neutral' : o.compliance_pct >= 95 ? 'ok' : o.compliance_pct >= 80 ? 'warn' : 'crit'} hint={o.due_so_far ? `${o.completed} of ${o.due_so_far} due so far` : 'Nothing due yet'} onClick={go(drill.completed)} />
        <KpiCard label="On time" value={fmtPct(o.on_time_pct)} hint={`${o.completed_late} completed late`} />
        <KpiCard label="Overdue" value={o.overdue} tone={o.overdue > 0 ? 'crit' : 'ok'} hint="Open past due date" onClick={go(drill.overdue)} />
        <KpiCard label="Due soon" value={o.due_soon} tone={o.due_soon > 0 ? 'warn' : 'neutral'} onClick={go(drill.dueSoon)} />
        <KpiCard label="Next 30 days" value={o.upcoming_30_days} onClick={go(drill.next30)} />
        <KpiCard label="Critical exceptions" value={d.exceptions.critical_open} tone={d.exceptions.critical_open > 0 ? 'crit' : 'ok'} hint={`${d.exceptions.open} open in total`} onClick={go(drill.criticalExceptions)} />
      </div>
      <p className="text-xs text-muted">Compliance % = {d.definitions.compliance_pct} Generated {new Date(d.generated_at).toLocaleString()}.</p>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Exceptions by severity" hint="Open and acknowledged">
          <BarList href={drill.exceptionSeverity} rows={SEVERITY_ORDER.map((s) => ({ key: s, label: titleCase(s), value: d.exceptions.by_severity[s] ?? 0, tone: severityTone(s) }))} />
          <Link to={drill.breached} className="mt-3 block text-sm text-blue hover:underline">{d.exceptions.target_breached} past their resolution target</Link>
        </Card>
        <Card title="Exception ageing" hint="Days since detection">
          <BarList href={drill.exceptionAge} rows={AGE_ORDER.map((b) => ({ key: b, label: `${b} days`, value: d.exceptions.by_age[b] ?? 0, tone: b === '90+' || b === '31-90' ? 'crit' : 'info' as Tone }))} />
        </Card>
        <Card title="Licences & registrations" hint={`${d.licences.active} active`}>
          <ul className="space-y-1 text-sm">
            {Object.entries(d.licences.by_category).sort().map(([cat, n]) => { const b = expiryBadge(cat); return (
              <li key={cat} className="flex items-center justify-between"><Link to={drill.licenceBucket(cat)} className="hover:underline"><Badge tone={b.tone}>{b.label}</Badge></Link><span className="font-medium">{n}</span></li>) })}
            {Object.keys(d.licences.by_category).length === 0 && <li className="text-muted">No active licences.</li>}
          </ul>
          <Link to={drill.renewalWindow} className="mt-3 block text-sm text-blue hover:underline">{d.licences.renewal_window_open} in renewal window</Link>
        </Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Mandatory evidence" hint="Obligations needing documents">
          <ul className="space-y-1 text-sm">
            {([['Missing', d.evidence.missing, drill.evidenceMissing, 'crit'], ['Rejected', d.evidence.rejected, drill.evidenceRejected, 'crit'], ['Expired', d.evidence.expired, drill.evidenceExpired, 'warn'], ['Pending review', d.evidence.pending_review, drill.evidencePending, 'info']] as const).map(([label, n, to, tone]) => (
              <li key={label} className="flex items-center justify-between"><Link to={to} className="hover:underline"><Badge tone={tone}>{label}</Badge></Link><span className="font-medium">{n}</span></li>))}
          </ul>
        </Card>
        <Card title="By location" hint="Most overdue first">
          {d.by_location.length === 0 ? <p className="text-sm text-muted">No obligations.</p> : (
            <table className="w-full text-sm"><thead className="text-left text-xs text-muted"><tr><th className="pb-1 font-medium">Location</th><th className="pb-1 font-medium">Overdue</th><th className="pb-1 font-medium">Due soon</th><th className="pb-1 font-medium">Open</th></tr></thead>
              <tbody>{d.by_location.map((l) => <tr key={l.location_code} className="border-t border-line"><td className="py-1"><Link className="text-blue hover:underline" to={drill.location(l.location_code)}>{l.location_code}</Link></td><td className={l.overdue ? 'font-medium text-status-crit' : ''}>{l.overdue}</td><td>{l.due_soon}</td><td>{l.open}</td></tr>)}</tbody></table>)}
        </Card>
        <Card title="Next due" hint="Within 30 days">
          {d.next_due.length === 0 ? <p className="text-sm text-muted">Nothing due in the next 30 days.</p> : (
            <ul className="space-y-2 text-sm">{d.next_due.map((n) => { const b = dueStateBadge[n.due_state] ?? dueStateBadge.upcoming; return (
              <li key={n.instance_no} className="flex items-start justify-between gap-2"><Link className="min-w-0 text-ink hover:underline" to={`/compliance?q=${encodeURIComponent(n.instance_no)}`}><span className="block truncate">{n.compliance_name}</span><span className="text-xs text-muted">{n.location_code} · {n.due_date}</span></Link><Badge tone={b.tone}>{b.label}</Badge></li>) })}</ul>)}
        </Card>
      </div>
    </div>
  )
}

export function DashboardPage() {
  const q = useDashboard()
  const navigate = useNavigate()
  return (
    <section className="space-y-4">
      <div className="flex items-center justify-between"><h1 className="text-xl font-semibold text-navy">Executive Dashboard</h1><Button variant="secondary" onClick={() => void q.refetch()} loading={q.isFetching}>Refresh</Button></div>
      {q.isLoading ? <div className="space-y-3"><Skeleton rows={3} className="h-16" /></div>
        : q.error ? ((q.error as { code?: string }).code === '42501' ? <UnauthorizedPage /> : <ErrorState message={(q.error as Error).message} onRetry={() => void q.refetch()} />)
        : <DashboardView d={q.data!} nav={navigate} />}
    </section>
  )
}
