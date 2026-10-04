import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../components/table/Register'
import { Badge, Button, ErrorState, Field, Skeleton, Tabs, Textarea, type Tone } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { describeError } from './errors'

export type JobRow = { id: string; code: string; name: string; description: string | null; schedule_cron: string | null; is_enabled: boolean; max_attempts: number; timeout_seconds: number; has_runner: boolean; last_status: string | null; last_started_at: string | null; last_completed_at: string | null; last_records: number | null; last_environment: string | null; last_warning: string | null; last_message: string | null; last_success_at: string | null; failures_24h: number }
const SELECT = 'id,code,name,description,schedule_cron,is_enabled,max_attempts,timeout_seconds,has_runner,last_status,last_started_at,last_completed_at,last_records,last_environment,last_warning,last_message,last_success_at,failures_24h'
type Run = { id: string; status: string; attempt: number; triggered_by: string | null; environment: string | null; started_at: string; duration_s: number | null; records_processed: number | null; error_message: string | null; warning: string | null }
export const RUN_TONE: Record<string, Tone> = { succeeded: 'ok', running: 'info', failed: 'crit', retry_wait: 'warn', cancelled: 'neutral' }
const fmt = (s: string | null) => (s ? new Date(s).toLocaleString() : '—')

/** Plain-language health of one job: never-run and unscheduled states are reported, not hidden. */
export function jobHealth(j: Pick<JobRow, 'is_enabled' | 'has_runner' | 'last_status' | 'failures_24h'>): { label: string; tone: Tone } {
  if (!j.has_runner) return { label: 'Not implemented', tone: 'neutral' }
  if (!j.is_enabled) return { label: 'Disabled', tone: 'neutral' }
  if (j.failures_24h > 0 || j.last_status === 'failed') return { label: 'Failing', tone: 'crit' }
  if (!j.last_status) return { label: 'Never run', tone: 'warn' }
  return { label: 'Healthy', tone: 'ok' }
}

function Detail({ row, canManage, close }: { row: JobRow; canManage: boolean; close: () => void }) {
  const { notify } = useToast(); const qc = useQueryClient(); const [reason, setReason] = useState(''); const [err, setErr] = useState(''); const [busy, setBusy] = useState(false)
  const runs = useQuery({ queryKey: ['jobs', 'runs', row.code], enabled: !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('v_job_run').select('id,status,attempt,triggered_by,environment,started_at,duration_s,records_processed,error_message,warning').eq('job_code', row.code).order('started_at', { ascending: false }).limit(25); if (error) throw error; return (data ?? []) as Run[] } })
  async function toggle() {
    if (!reason.trim()) return setErr('A reason is required'); if (!supabase) return; setErr(''); setBusy(true)
    try {
      const { error } = await supabase.rpc('job_set_enabled', { p_code: row.code, p_enabled: !row.is_enabled, p_reason: reason.trim() })
      if (error) return notify(describeError(error), 'crit')
      notify(`${row.name} ${row.is_enabled ? 'disabled' : 'enabled'}`, 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); void qc.invalidateQueries({ queryKey: ['jobs'] }); close()
    } finally { setBusy(false) }
  }
  const h = jobHealth(row)
  return (
    <Tabs tabs={[
      { id: 'job', label: 'Job', content: (
        <div className="space-y-3 text-sm">
          <div className="flex items-center gap-2"><Badge tone={h.tone}>{h.label}</Badge>{row.last_environment && <span className="text-xs text-muted">last run in {row.last_environment}</span>}</div>
          <p>{row.description ?? ''}</p>
          <dl className="grid grid-cols-3 gap-x-3 gap-y-2"><dt className="text-muted">Proposed schedule</dt><dd className="col-span-2 font-mono">{row.schedule_cron ?? '—'} <span className="font-sans text-xs text-muted">(not active: scheduler is off)</span></dd>
            <dt className="text-muted">Attempts / timeout</dt><dd className="col-span-2">{row.max_attempts} attempts · {row.timeout_seconds}s</dd><dt className="text-muted">Last success</dt><dd className="col-span-2">{fmt(row.last_success_at)}</dd>
            <dt className="text-muted">Failures (24h)</dt><dd className="col-span-2">{row.failures_24h}</dd>{row.last_message && <><dt className="text-muted">Last error</dt><dd className="col-span-2 text-status-crit">{row.last_message}</dd></>}{row.last_warning && <><dt className="text-muted">Warning</dt><dd className="col-span-2 text-status-warn">{row.last_warning}</dd></>}</dl>
          {canManage && !row.has_runner ? <p className="border-t border-line pt-3 text-xs text-muted">This job has no runner yet. It stays a disabled definition and cannot be enabled until its behaviour and acceptance rules are agreed and implemented.</p> : canManage ? (<div className="space-y-2 border-t border-line pt-3"><Field label={row.is_enabled ? 'Reason for disabling' : 'Reason for enabling'} required error={err}>{(f) => <Textarea {...f} rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />}</Field>
            <Button variant={row.is_enabled ? 'secondary' : 'primary'} loading={busy} onClick={() => void toggle()}>{row.is_enabled ? 'Disable job' : 'Enable job'}</Button>
            <p className="text-xs text-muted">Enabling a job does not start it. Jobs only run when the scheduler is approved and switched on.</p></div>) : null}
        </div>) },
      { id: 'runs', label: 'Runs', content: runs.isLoading ? <Skeleton rows={3} /> : runs.error ? <ErrorState message={(runs.error as Error).message} /> : (runs.data ?? []).length === 0 ? <p className="text-sm text-muted">This job has not run.</p> : (
        <ul className="space-y-2 text-sm">{runs.data!.map((r) => <li key={r.id} className="rounded border border-line p-2"><Badge tone={RUN_TONE[r.status] ?? 'neutral'}>{r.status}</Badge> {fmt(r.started_at)} · {r.duration_s ?? '—'}s · {r.records_processed ?? 0} records · attempt {r.attempt}{r.environment ? ` · ${r.environment}` : ''}
          {r.error_message && <div className="text-status-crit">{r.error_message}</div>}{r.warning && <div className="text-status-warn">{r.warning}</div>}</li>)}</ul>) },
    ]} />
  )
}

const cols: ColumnDef<JobRow, unknown>[] = [
  { accessorKey: 'name', header: 'Job', cell: (c) => <span><span className="font-medium">{c.getValue<string>()}</span> <span className="text-muted">{c.row.original.code}</span></span> },
  { id: 'health', header: 'Health', enableSorting: false, cell: (c) => { const h = jobHealth(c.row.original); return <Badge tone={h.tone}>{h.label}</Badge> } },
  { accessorKey: 'last_status', header: 'Last run', cell: (c) => (c.getValue<string | null>() ? <Badge tone={RUN_TONE[c.getValue<string>()] ?? 'neutral'}>{c.getValue<string>()}</Badge> : '—') },
  { accessorKey: 'last_started_at', header: 'Started', cell: (c) => fmt(c.getValue<string | null>()) },
  { accessorKey: 'schedule_cron', header: 'Proposed schedule', cell: (c) => <span className="font-mono text-xs">{c.getValue<string | null>() ?? '—'}</span> },
]
export function JobMonitorPage() {
  const { access } = useAuth(); const canManage = can(access, 'job.manage')
  return (<div className="space-y-4">
    <p className="rounded border border-line bg-white p-3 text-sm text-muted">Schedules shown are <strong>proposals</strong>. The automatic scheduler is switched off until the owner approves the exact times, so jobs only run when started deliberately.</p>
    <Register<JobRow> id="jobs" title="Job Monitor" table="v_job_status" select={SELECT} columns={cols} getRowId={(r) => r.id} searchColumns={['code', 'name']} defaultSort={{ id: 'name', desc: false }} searchPlaceholder="Search jobs…"
      filterDefs={[{ key: 'is_enabled', label: 'Enabled', options: [{ value: 'true', label: 'Enabled' }, { value: 'false', label: 'Disabled' }] }]}
      quickViewTitle={(r) => r.name} renderQuickView={(r, close) => <Detail row={r} canManage={canManage} close={close} />} />
  </div>)
}
