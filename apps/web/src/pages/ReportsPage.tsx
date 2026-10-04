import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Button, DatePicker, EmptyState, ErrorState, Field, Select, Skeleton, Tabs } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { logAndDownload, type ExportColumn } from '../lib/exportCsv'
import { DIMENSIONS, defaultWindow, pctText, pctWidth, pivotPipeline, totalsOf, validateWindow, type Dimension, type PerfRow, type PipelineRow } from '../lib/reports'

const PERF_COLS: ExportColumn[] = [
  { key: 'group_label', header: 'Group' }, { key: 'total', header: 'Obligations' }, { key: 'completed', header: 'Completed' }, { key: 'completed_on_time', header: 'Completed on time' }, { key: 'completed_late', header: 'Completed late' },
  { key: 'overdue_open', header: 'Overdue (open)' }, { key: 'upcoming_open', header: 'Not yet due (open)' }, { key: 'due_to_date', header: 'Due to date' }, { key: 'on_time_pct', header: 'On-time %' }, { key: 'compliance_pct', header: 'Compliance %' },
]
const Num = ({ v, tone }: { v: number; tone?: 'crit' }) => <td className={`px-3 py-2 text-right tabular-nums ${tone === 'crit' && v > 0 ? 'font-semibold text-status-crit' : ''}`}>{v}</td>
const Pct = ({ v }: { v: number | null }) => (
  <td className="px-3 py-2"><div className="flex items-center gap-2"><span className="w-14 text-right tabular-nums">{pctText(v)}</span><div className="h-1.5 w-20 rounded bg-line" aria-hidden><div className="h-1.5 rounded bg-blue" style={{ width: pctWidth(v) }} /></div></div></td>
)

function ExportButton({ register, filters, rows, cols, disabled }: { register: string; filters: Record<string, unknown>; rows: Array<Record<string, unknown>>; cols: ExportColumn[]; disabled: boolean }) {
  const { access } = useAuth(); const { notify } = useToast(); const [busy, setBusy] = useState(false)
  if (!can(access, 'report.export') || !supabase) return null
  return <Button variant="secondary" loading={busy} disabled={disabled} onClick={async () => { setBusy(true); try { const err = await logAndDownload(supabase!, register, filters, rows, cols); if (err) notify('Export was not recorded, so nothing was downloaded: ' + err, 'crit'); else notify(`Exported ${rows.length} rows`, 'ok') } finally { setBusy(false) } }}>Export CSV</Button>
}

function Performance() {
  const [dimension, setDimension] = useState<Dimension>('month'); const w0 = defaultWindow(); const [from, setFrom] = useState(w0.from); const [to, setTo] = useState(w0.to)
  const problem = validateWindow(from, to)
  const q = useQuery({ queryKey: ['report', 'performance', dimension, from, to], enabled: !!supabase && !problem, queryFn: async (): Promise<PerfRow[]> => {
    const { data, error } = await supabase!.rpc('report_compliance_performance', { p_dimension: dimension, p_from: from, p_to: to }); if (error) throw error; return (data ?? []) as PerfRow[] } })
  const rows = q.data ?? []; const total = rows.length ? totalsOf(rows) : null
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div className="w-56"><Field label="Group by">{(f) => <Select {...f} value={dimension} options={DIMENSIONS} onChange={(e) => setDimension(e.target.value as Dimension)} />}</Field></div>
        <div className="w-44"><Field label="Due from" error={problem ?? undefined}>{(f) => <DatePicker {...f} value={from} onChange={(e) => setFrom(e.target.value)} />}</Field></div>
        <div className="w-44"><Field label="Due to">{(f) => <DatePicker {...f} value={to} onChange={(e) => setTo(e.target.value)} />}</Field></div>
        <ExportButton register="report-compliance-performance" filters={{ dimension, from, to }} rows={[...rows, ...(total ? [total] : [])] as unknown as Array<Record<string, unknown>>} cols={PERF_COLS} disabled={!rows.length} />
      </div>
      <p className="text-xs text-muted">Counts obligations whose due date falls in the period, within your role and scope. “Due to date” are those due on or before today. On-time % = completed on or before the due date ÷ due to date; Compliance % = completed ÷ due to date. Not-applicable obligations are excluded.</p>
      {q.isLoading ? <Skeleton rows={4} /> : q.error ? <ErrorState message={(q.error as Error).message} onRetry={() => void q.refetch()} /> : !rows.length ? <EmptyState title="No obligations in this period" description="Try a wider period. Only obligations in your scope are counted." /> : (
        <div className="overflow-x-auto rounded-lg border border-line bg-white">
          <table className="w-full text-sm">
            <thead className="bg-canvas text-left text-xs uppercase tracking-wide text-muted"><tr><th className="px-3 py-2">Group</th><th className="px-3 py-2 text-right">Obligations</th><th className="px-3 py-2 text-right">Completed</th><th className="px-3 py-2 text-right">On time</th><th className="px-3 py-2 text-right">Late</th><th className="px-3 py-2 text-right">Overdue</th><th className="px-3 py-2 text-right">Not yet due</th><th className="px-3 py-2">On-time %</th><th className="px-3 py-2">Compliance %</th></tr></thead>
            <tbody className="divide-y divide-line">{rows.map((r) => <tr key={r.group_key}><td className="px-3 py-2">{r.group_label}</td><Num v={r.total} /><Num v={r.completed} /><Num v={r.completed_on_time} /><Num v={r.completed_late} /><Num v={r.overdue_open} tone="crit" /><Num v={r.upcoming_open} /><Pct v={r.on_time_pct} /><Pct v={r.compliance_pct} /></tr>)}</tbody>
            {total && <tfoot className="border-t-2 border-line bg-canvas font-medium"><tr><td className="px-3 py-2">Total</td><Num v={total.total} /><Num v={total.completed} /><Num v={total.completed_on_time} /><Num v={total.completed_late} /><Num v={total.overdue_open} tone="crit" /><Num v={total.upcoming_open} /><Pct v={total.on_time_pct} /><Pct v={total.compliance_pct} /></tr></tfoot>}
          </table>
        </div>)}
    </div>
  )
}

const HORIZONS = [{ value: '6', label: 'Next 6 months' }, { value: '12', label: 'Next 12 months' }, { value: '24', label: 'Next 24 months' }, { value: '36', label: 'Next 36 months' }]
function Pipeline() {
  const [months, setMonths] = useState('12')
  const q = useQuery({ queryKey: ['report', 'pipeline', months], enabled: !!supabase, queryFn: async (): Promise<PipelineRow[]> => {
    const { data, error } = await supabase!.rpc('report_licence_pipeline', { p_months: Number(months) }); if (error) throw error; return (data ?? []) as PipelineRow[] } })
  const pv = pivotPipeline(q.data ?? []); const cols: ExportColumn[] = [{ key: 'bucket', header: 'Expiry' }, ...pv.types.map((t) => ({ key: t.code, header: t.name })), { key: 'total', header: 'Total' }]
  const flat = pv.lines.map((l) => ({ bucket: l.bucket === 'expired' ? 'Already expired' : l.bucket, ...l.counts, total: l.total }))
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3"><div className="w-56"><Field label="Horizon">{(f) => <Select {...f} value={months} options={HORIZONS} onChange={(e) => setMonths(e.target.value)} />}</Field></div>
        <ExportButton register="report-licence-pipeline" filters={{ months: Number(months) }} rows={flat} cols={cols} disabled={!flat.length} /></div>
      <p className="text-xs text-muted">Active licences and registrations that have an expiry date, by month of expiry, within your scope. “Already expired” are active licences past their expiry date.</p>
      {q.isLoading ? <Skeleton rows={4} /> : q.error ? <ErrorState message={(q.error as Error).message} onRetry={() => void q.refetch()} /> : !pv.lines.length ? <EmptyState title="No licences expire in this horizon" /> : (
        <div className="overflow-x-auto rounded-lg border border-line bg-white">
          <table className="w-full text-sm"><thead className="bg-canvas text-left text-xs uppercase tracking-wide text-muted"><tr><th className="px-3 py-2">Expiry</th>{pv.types.map((t) => <th key={t.code} className="px-3 py-2 text-right">{t.name}</th>)}<th className="px-3 py-2 text-right">Total</th></tr></thead>
            <tbody className="divide-y divide-line">{pv.lines.map((l) => <tr key={l.bucket}><td className={`px-3 py-2 ${l.bucket === 'expired' ? 'font-semibold text-status-crit' : ''}`}>{l.bucket === 'expired' ? 'Already expired' : l.bucket}</td>{pv.types.map((t) => <td key={t.code} className="px-3 py-2 text-right tabular-nums">{l.counts[t.code] ?? 0}</td>)}<td className="px-3 py-2 text-right font-medium tabular-nums">{l.total}</td></tr>)}</tbody></table>
        </div>)}
    </div>
  )
}

export function ReportsPage() {
  const { access } = useAuth(); useEffect(() => { document.title = 'Reports · BFCL HR Compliance' }, [])
  const tabs = [...(can(access, 'compliance.read') ? [{ id: 'perf', label: 'Compliance performance', content: <Performance /> }] : []), ...(can(access, 'licence.read') ? [{ id: 'pipe', label: 'Licence expiry pipeline', content: <Pipeline /> }] : [])]
  return (<section className="space-y-4"><h1 className="text-xl font-semibold text-navy">Reports</h1>{tabs.length ? <Tabs tabs={tabs} /> : <EmptyState title="No reports available" description="Reports need compliance or licence read access." />}</section>)
}
