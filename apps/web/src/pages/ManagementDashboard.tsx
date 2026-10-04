import { useMemo, type ReactNode } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Button, DatePicker, EmptyState, ErrorState, KpiCard, Select, Skeleton } from '../components/ui'
import { supabase } from '../lib/supabase'
import { useLookup } from '../admin/lookups'
import { dueStateBadge, severityTone, titleCase } from '../lib/badges'
import { Badge } from '../components/ui'
import { drillTo, filtersFromParams, managementSchema, paramsFromFilters, PERIOD_PRESETS, periodFor, validateDashPeriod, type DashFilters, type Management, type PeriodPreset } from '../lib/management'
import { fmtPct } from '../lib/dashboard'

const Card = ({ title, hint, children, className = '' }: { title: string; hint?: string; children: ReactNode; className?: string }) => (
  <section className={`rounded-lg border border-line bg-white p-4 ${className}`}><h2 className="text-sm font-semibold text-navy">{title}</h2>{hint && <p className="text-xs text-muted">{hint}</p>}<div className="mt-3">{children}</div></section>
)

/** Stacked monthly bars: completed on time (navy), completed late (amber), overdue open (red), not yet due (grey). Red/amber carry meaning; a table below is the accessible equivalent. */
export function TrendChart({ rows }: { rows: Management['trend'] }) {
  const max = Math.max(1, ...rows.map((r) => r.due)); const H = 120; const bw = Math.max(12, Math.min(64, Math.floor(640 / Math.max(1, rows.length)) - 8))
  const w = rows.length * (bw + 8) + 8
  const summary = rows.map((r) => `${r.month}: ${r.due} due, ${r.completed_on_time} on time, ${r.completed_late} late, ${r.overdue_open} overdue`).join('; ')
  return (
    <div className="relative overflow-hidden">
      <div className="overflow-x-auto" tabIndex={0} role="region" aria-label="Compliance trend chart, scrollable">
        <svg role="img" aria-label={`Obligations by due month. ${summary}`} width={Math.max(w, 280)} height={H + 28} className="block">
          {rows.map((r, i) => {
            const x = 4 + i * (bw + 8); let y = H
            const seg = (v: number, cls: string, label: string) => { const h = (v / max) * H; y -= h; return h > 0 ? <rect key={label} x={x} y={y} width={bw} height={h} className={cls}><title>{`${r.month} · ${label}: ${v}`}</title></rect> : null }
            return (<g key={r.month}>{seg(r.completed_on_time, 'fill-navy', 'completed on time')}{seg(r.completed_late, 'fill-status-warn', 'completed late')}{seg(r.overdue_open, 'fill-status-crit', 'overdue')}{seg(r.upcoming_open, 'fill-line', 'not yet due')}
              <text x={x + bw / 2} y={H + 14} textAnchor="middle" className="fill-muted text-[9px]">{r.month.slice(2)}</text></g>)
          })}
        </svg>
      </div>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted" aria-label="Legend">
        <li><span className="mr-1 inline-block size-2 rounded-sm bg-navy" />On time</li><li><span className="mr-1 inline-block size-2 rounded-sm bg-status-warn" />Completed late</li><li><span className="mr-1 inline-block size-2 rounded-sm bg-status-crit" />Overdue</li><li><span className="mr-1 inline-block size-2 rounded-sm bg-line" />Not yet due</li>
      </ul>
      <table className="sr-only"><caption>Obligations by due month</caption><thead><tr><th>Month</th><th>Due</th><th>On time</th><th>Late</th><th>Overdue</th><th>Not yet due</th></tr></thead>
        <tbody>{rows.map((r) => <tr key={r.month}><td>{r.month}</td><td>{r.due}</td><td>{r.completed_on_time}</td><td>{r.completed_late}</td><td>{r.overdue_open}</td><td>{r.upcoming_open}</td></tr>)}</tbody></table>
    </div>
  )
}

function PerfTable({ rows, label, href }: { rows: Array<{ key: string; name: string; total: number; open: number; overdue: number; compliance_pct: number | null }>; label: string; href: (key: string) => string | null }) {
  if (!rows.length) return <p className="text-sm text-muted">No obligations in this view.</p>
  return (
    <div className="overflow-x-auto" tabIndex={0} role="region" aria-label={`${label} performance, scrollable`}><table className="w-full text-sm"><thead className="text-left text-xs text-muted"><tr><th className="pb-1 pr-3 font-medium">{label}</th><th className="pb-1 px-2 text-right font-medium">Obligations</th><th className="pb-1 px-2 text-right font-medium">Open</th><th className="pb-1 px-2 text-right font-medium">Overdue</th><th className="pb-1 pl-3 font-medium">Compliance</th></tr></thead>
      <tbody>{rows.map((r) => { const to = href(r.key); return (
        <tr key={r.key} className="border-t border-line"><td className="py-1.5">{to ? <Link className="text-blue hover:underline" to={to}>{r.name}</Link> : r.name}</td><td className="px-2 py-1.5 text-right tabular-nums">{r.total}</td><td className="px-2 py-1.5 text-right tabular-nums">{r.open}</td>
          <td className={`px-2 py-1.5 text-right tabular-nums ${r.overdue ? 'font-medium text-status-crit' : ''}`}>{r.overdue}</td>
          <td className="py-1.5 pl-3"><div className="flex items-center gap-2"><span className="w-12 text-right tabular-nums">{fmtPct(r.compliance_pct)}</span><div className="h-1.5 w-16 rounded bg-line" aria-hidden><div className="h-1.5 rounded bg-blue" style={{ width: `${Math.max(0, Math.min(100, r.compliance_pct ?? 0))}%` }} /></div></div></td></tr>) })}</tbody></table></div>
  )
}

export function ManagementView({ d, f }: { d: Management; f: DashFilters }) {
  const navigate = useNavigate(); const k = d.kpis; const top = d.top_risk_level ?? ''; const topSev = d.top_severity ?? ''
  const go = (to: string) => () => navigate(to)
  const maxRisk = Math.max(1, ...d.risk.map((r) => r.open))
  const byDate = useMemo(() => { const m = new Map<string, Management['upcoming']>(); for (const u of d.upcoming) m.set(u.due_date, [...(m.get(u.due_date) ?? []), u]); return [...m.entries()] }, [d.upcoming])
  const empty = k.total_applicable === 0 && k.overdue === 0 && k.open_exceptions === 0 && d.licences.expiring === 0
  const ageing = ['0-7', '8-30', '31-90', '90+'].map((b) => ({ bucket: b, n: d.exception_ageing[b] ?? 0 })); const maxAge = Math.max(1, ...ageing.map((a) => a.n))
  return (
    <div className="space-y-4">
      {empty && <EmptyState title="Nothing to show for these filters" description="Only obligations, exceptions and licences within your role and scope are counted. Nothing is estimated." />}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
        <KpiCard label="Total applicable" value={k.total_applicable} hint="Due in the period" onClick={go(drillTo('/compliance', f))} />
        <KpiCard label="Due this month" value={k.due_this_month} hint="Open, this calendar month" onClick={go('/calendar')} />
        <KpiCard label="Overdue" value={k.overdue} tone={k.overdue > 0 ? 'crit' : 'neutral'} hint="Open past due date" onClick={go(drillTo('/compliance', f, { due_state: 'overdue' }))} />
        <KpiCard label="Critical" value={k.critical_open} tone={k.critical_overdue > 0 ? 'crit' : 'neutral'} hint={`${k.critical_overdue} overdue · highest risk level`} onClick={go(drillTo('/compliance', f, { status: 'active', risk_level: top }))} />
        <KpiCard label="Open exceptions" value={k.open_exceptions} hint={`${k.critical_exceptions} at ${topSev ? titleCase(topSev).toLowerCase() : 'top'} severity`} tone={k.critical_exceptions > 0 ? 'crit' : 'neutral'} onClick={go(drillTo('/exceptions', f, { status: 'open' }))} />
        <KpiCard label="Licences expiring" value={k.licences_expiring} hint={`Next ${d.licences.horizon_days} days · ${k.licences_expired} expired`} onClick={go(drillTo('/licences', f, {}, { department: false }))} />
      </div>
      <p className="text-xs text-muted">Compliance {fmtPct(k.compliance_pct)} · On time {fmtPct(k.on_time_pct)} for obligations already due in the period ({d.period.from} to {d.period.to}). {d.licences.department_filter_applies ? '' : 'The department filter does not apply to licences. '}Generated {new Date(d.generated_at).toLocaleString()}.</p>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Compliance trend" hint="Obligations by due month" className="lg:col-span-2">{d.trend.length ? <TrendChart rows={d.trend} /> : <p className="text-sm text-muted">No obligations fall in this period.</p>}</Card>
        <Card title="Risk distribution" hint="Open obligations by risk level">
          <ul className="space-y-2">{[...d.risk].reverse().map((r) => (
            <li key={r.level}><Link to={drillTo('/compliance', f, { status: 'active', risk_level: r.level })} className="group block"><div className="flex justify-between text-sm"><span className="group-hover:underline">{r.label}</span><span className="font-medium tabular-nums">{r.open}{r.overdue > 0 && <span className="ml-2 text-xs font-normal text-status-crit">{r.overdue} overdue</span>}</span></div>
              <div className="mt-1 h-1.5 rounded bg-line" aria-hidden><div className="h-1.5 rounded bg-blue" style={{ width: `${(r.open / maxRisk) * 100}%` }} /></div></Link></li>))}</ul>
        </Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="By location" hint="Most overdue first"><PerfTable label="Location" rows={d.by_location.map((l) => ({ key: l.code, name: l.name ? `${l.code} · ${l.name}` : l.code, total: l.total, open: l.open, overdue: l.overdue, compliance_pct: l.compliance_pct }))} href={(c) => `/compliance?location_code=${encodeURIComponent(c)}`} /></Card>
        <Card title="By responsible department" hint="Of the compliance master"><PerfTable label="Department" rows={d.by_department.map((x) => ({ key: x.id ?? '', name: x.name, total: x.total, open: x.open, overdue: x.overdue, compliance_pct: x.compliance_pct }))} href={(id) => (id ? drillTo('/compliance', { ...f, department: id }) : null)} /></Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card title="Upcoming" hint="Next 30 days" className="lg:col-span-1">
          {byDate.length === 0 ? <p className="text-sm text-muted">Nothing due in the next 30 days.</p> : (
            <ol className="space-y-3 text-sm">{byDate.map(([date, items]) => (
              <li key={date}><div className="text-xs font-semibold text-muted">{new Date(date + 'T00:00:00').toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' })}</div>
                <ul className="mt-1 space-y-1">{items.map((n) => { const b = dueStateBadge[n.due_state] ?? dueStateBadge.upcoming; return (
                  <li key={n.instance_no} className="flex items-start justify-between gap-2"><Link className="min-w-0 hover:underline" to={`/compliance?q=${encodeURIComponent(n.instance_no)}`}><span className="block truncate">{n.compliance_name}</span><span className="text-xs text-muted">{n.location_code} · {titleCase(n.risk_level)}</span></Link><Badge tone={b.tone}>{b.label}</Badge></li>) })}</ul></li>))}</ol>)}
          <Link to="/calendar" className="mt-3 block text-sm text-blue hover:underline">Open the compliance calendar</Link>
        </Card>
        <Card title="Critical exceptions" hint={`Open at ${topSev ? titleCase(topSev).toLowerCase() : 'top'} severity, oldest first`} className="lg:col-span-1">
          {d.critical_exceptions.length === 0 ? <p className="text-sm text-muted">None open.</p> : (
            <ul className="space-y-2 text-sm">{d.critical_exceptions.map((e) => (
              <li key={e.id}><Link to={`/exceptions?q=${encodeURIComponent(e.exception_no)}`} className="block hover:underline"><span className="font-medium">{e.exception_no}</span> <Badge tone={severityTone(e.severity)}>{titleCase(e.severity)}</Badge>{e.target_breached && <> <Badge tone="crit">Past target</Badge></>}
                <span className="block truncate text-xs text-muted">{e.description ?? titleCase(e.category)} · {e.location_code ?? '—'} · {e.age_days} days</span></Link></li>))}</ul>)}
        </Card>
        <Card title="Exception ageing" hint="Open, days since detection" className="lg:col-span-1">
          <ul className="space-y-2">{ageing.map((a) => (
            <li key={a.bucket}><Link to={drillTo('/exceptions', f, { status: 'open', age_bucket: a.bucket })} className="group block"><div className="flex justify-between text-sm"><span className="group-hover:underline">{a.bucket} days</span><span className="font-medium tabular-nums">{a.n}</span></div>
              <div className="mt-1 h-1.5 rounded bg-line" aria-hidden><div className="h-1.5 rounded bg-blue" style={{ width: `${(a.n / maxAge) * 100}%` }} /></div></Link></li>))}</ul>
          <Link to="/reports" className="mt-3 block text-sm text-blue hover:underline">Full compliance reports</Link>
        </Card>
      </div>
    </div>
  )
}

export function ManagementDashboard() {
  const [params, setParams] = useSearchParams(); const f = useMemo(() => filtersFromParams(params), [params])
  const entities = useLookup({ table: 'entity', value: 'id', label: 'name' }); const locations = useLookup({ table: 'location', value: 'id', label: 'name', filter: f.entity ? { entity_id: f.entity } : undefined }); const departments = useLookup({ table: 'department', value: 'id', label: 'name' })
  const problem = f.preset === 'custom' ? validateDashPeriod(f.from, f.to) : null
  const set = (patch: Partial<DashFilters>) => { const next = { ...f, ...patch }; if (patch.entity !== undefined && patch.entity !== f.entity) next.location = ''; if (patch.preset && patch.preset !== 'custom') Object.assign(next, periodFor(patch.preset)); setParams(paramsFromFilters(next), { replace: true }) }
  const q = useQuery({ queryKey: ['management', f], enabled: !!supabase && !problem, refetchInterval: 5 * 60_000, queryFn: async () => {
    const { data, error } = await supabase!.rpc('management_dashboard', { p_entity: f.entity || null, p_location: f.location || null, p_department: f.department || null, p_from: f.from, p_to: f.to }); if (error) throw error; return managementSchema.parse(data) } })
  const anyFilter = !!(f.entity || f.location || f.department || f.preset !== '12m')
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3" role="group" aria-label="Dashboard filters">
        <div className="w-48"><Select aria-label="Entity" value={f.entity} placeholder="Entity: all" options={entities.data ?? []} onChange={(e) => set({ entity: e.target.value })} /></div>
        <div className="w-48"><Select aria-label="Location" value={f.location} placeholder="Location: all" options={locations.data ?? []} onChange={(e) => set({ location: e.target.value })} /></div>
        <div className="w-48"><Select aria-label="Department" value={f.department} placeholder="Department: all" options={departments.data ?? []} onChange={(e) => set({ department: e.target.value })} /></div>
        <div className="w-44"><Select aria-label="Period" value={f.preset} options={PERIOD_PRESETS} onChange={(e) => set({ preset: e.target.value as PeriodPreset })} /></div>
        {f.preset === 'custom' && <><div className="w-40"><DatePicker aria-label="Period from" value={f.from} onChange={(e) => set({ from: e.target.value })} /></div><div className="w-40"><DatePicker aria-label="Period to" value={f.to} onChange={(e) => set({ to: e.target.value })} /></div></>}
        {anyFilter && <Button variant="ghost" onClick={() => setParams(new URLSearchParams(), { replace: true })}>Clear filters</Button>}
        <Button variant="secondary" onClick={() => void q.refetch()} loading={q.isFetching}>Refresh</Button>
      </div>
      {problem && <p role="alert" className="text-sm text-status-crit">{problem}</p>}
      {q.isLoading ? <Skeleton rows={4} className="h-20" /> : q.error ? <ErrorState message={(q.error as Error).message} onRetry={() => void q.refetch()} /> : q.data ? <ManagementView d={q.data} f={f} /> : null}
    </div>
  )
}
