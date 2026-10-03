import { useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { Badge, Button, EmptyState, ErrorState, EvidencePlaceholder, Field, PermissionGate, Skeleton, Tabs, Textarea, Timeline, AuditHistory, type AuditEntry } from '../components/ui'
import { StatusActions } from '../components/StatusActions'
import { useToast } from '../app/Toasts'
import { getServices } from '../services'
import { dueStateBadge, evidenceBadge, expiryBadge, severityTone, titleCase } from '../lib/badges'

export type ComplianceRow = { id: string; instance_no: string; compliance_code: string; compliance_name: string; location_code: string; location_name: string; period_start: string; period_end: string; due_date: string; status: string; due_state: string; risk_level: string; criticality: string; frequency: string; evidence_required: boolean; days_overdue: number; days_to_due: number }
export type ExceptionRow = { id: string; exception_no: string; category: string; severity: string; description: string; status: string; detected_at: string; due_date: string | null; age_days: number; age_bucket: string; target_breached: boolean; resolution: string | null; compliance_instance_id: string | null; licence_id: string | null; evidence_id: string | null }
export type LicenceRow = { id: string; licence_no: string; licence_number: string | null; licence_type_name: string; expiry_date: string | null; days_to_expiry: number | null; expiry_category: string; renewal_status: string; risk_level: string | null; renewal_window_open: boolean; lifecycle_status: string }
export type EvidenceReqRow = { compliance_instance_id: string; instance_no: string; document_type_name: string; evidence_state: string; evidence_no: string | null; version: number | null; expiry_date: string | null; due_date: string }

const Dl = ({ rows }: { rows: Array<[string, ReactNode]> }) => <dl className="grid grid-cols-3 gap-x-3 gap-y-2 text-sm">{rows.map(([k, v]) => <div key={k} className="contents"><dt className="text-muted">{k}</dt><dd className="col-span-2 text-ink">{v ?? '—'}</dd></div>)}</dl>

function useRows<T>(key: string, table: string, select: string, col: string, id: string, order?: string) {
  return useQuery({ queryKey: ['quick', key, id], enabled: !!supabase, queryFn: async (): Promise<T[]> => {
    let r = supabase!.from(table).select(select).eq(col, id); if (order) r = r.order(order, { ascending: false })
    const { data, error } = await r; if (error) throw error; return (data ?? []) as unknown as T[] } })
}
const Loading = <T,>({ q, children }: { q: { isLoading: boolean; error: unknown; data?: T }; children: (d: T) => ReactNode }) =>
  q.isLoading ? <Skeleton rows={3} /> : q.error ? <ErrorState message={(q.error as Error).message} /> : <>{children(q.data as T)}</>

function EvidenceList({ instanceId }: { instanceId: string }) {
  const st = useQuery({ queryKey: ['storage-status'], queryFn: async () => (await getServices().storage.status()).state })
  const q = useRows<EvidenceReqRow>('ev', 'v_evidence_requirement', 'compliance_instance_id,instance_no,document_type_name,evidence_state,evidence_no,version,expiry_date,due_date', 'compliance_instance_id', instanceId)
  return <Loading q={q}>{(rows) => (
    <div className="space-y-3">
      {rows.length === 0 ? <p className="text-sm text-muted">This obligation does not require evidence.</p> : (
        <ul className="space-y-2 text-sm">{rows.map((r) => { const b = evidenceBadge[r.evidence_state] ?? evidenceBadge.missing; return (
          <li key={r.document_type_name} className="flex items-center justify-between rounded border border-line p-2"><span>{r.document_type_name}{r.evidence_no && <span className="text-xs text-muted"> · {r.evidence_no} v{r.version}</span>}</span><Badge tone={b.tone}>{b.label}</Badge></li>) })}</ul>)}
      <EvidencePlaceholder storageState={st.data ?? 'NOT_CONFIGURED'} />
    </div>)}</Loading>
}

function ExceptionsFor({ col, id }: { col: 'compliance_instance_id' | 'licence_id'; id: string }) {
  const q = useRows<ExceptionRow>('exc-' + col, 'v_exception', 'id,exception_no,category,severity,description,status,age_days,age_bucket,target_breached,detected_at,due_date,resolution,compliance_instance_id,licence_id,evidence_id', col, id, 'detected_at')
  return <Loading q={q}>{(rows) => rows.length === 0 ? <p className="text-sm text-muted">No exceptions.</p> : (
    <ul className="space-y-2 text-sm">{rows.map((r) => <li key={r.id} className="rounded border border-line p-2"><div className="flex items-center justify-between"><Link className="font-medium text-blue hover:underline" to={`/exceptions?q=${r.exception_no}`}>{r.exception_no}</Link><span className="flex gap-1"><Badge tone={severityTone(r.severity)}>{titleCase(r.severity)}</Badge><Badge>{titleCase(r.status)}</Badge></span></div><p className="mt-1 text-muted">{r.description}</p></li>)}</ul>)}</Loading>
}

function AuditTab({ table, id }: { table: string; id: string }) {
  const q = useQuery({ queryKey: ['quick', 'audit', table, id], enabled: !!supabase, queryFn: async (): Promise<AuditEntry[]> => {
    const { data, error } = await supabase!.from('audit_log').select('id,at,action,actor_id,changed_fields,reason,old_data,new_data').eq('table_name', table).eq('record_id', id).order('at', { ascending: false }).limit(50)
    if (error) throw error; return (data ?? []).map((r) => ({ ...r, actor: r.actor_id as string | null })) as AuditEntry[] } })
  return <Loading q={q}>{(rows) => <AuditHistory entries={rows} />}</Loading>
}

/** Plain-language timing; never shows a negative countdown. */
export function timing(r: Pick<ComplianceRow, 'status' | 'days_overdue' | 'days_to_due'>): string {
  if (r.status === 'completed') return 'Completed'
  if (r.status === 'not_applicable') return 'Not applicable'
  if (r.days_overdue > 0) return `${r.days_overdue} day(s) overdue`
  if (r.days_to_due === 0) return 'Due today'
  return `${r.days_to_due} day(s) to go`
}
export function ComplianceQuickView({ row }: { row: ComplianceRow }) {
  const b = dueStateBadge[row.due_state] ?? dueStateBadge.upcoming
  return (
    <Tabs tabs={[
      { id: 'summary', label: 'Summary', content: (
        <div className="space-y-4">
          <div className="flex items-center gap-2"><Badge tone={b.tone}>{b.label}</Badge>{titleCase(row.status) !== b.label && <Badge>{titleCase(row.status)}</Badge>}<Badge tone={severityTone(row.risk_level)}>{titleCase(row.risk_level)} risk</Badge></div>
          <Dl rows={[['Obligation', `${row.compliance_code} — ${row.compliance_name}`], ['Number', row.instance_no], ['Location', `${row.location_code} · ${row.location_name}`], ['Period', `${row.period_start} → ${row.period_end}`], ['Due date', row.due_date],
            ['Timing', timing(row)], ['Frequency', titleCase(row.frequency)], ['Criticality', titleCase(row.criticality)]]} />
          <PermissionGate perm="compliance.write"><div className="border-t border-line pt-3"><h3 className="mb-2 text-sm font-semibold text-navy">Update status</h3><StatusActions module="compliance" current={row.status} recordId={row.id} rpc="compliance_set_status" /></div></PermissionGate>
        </div>) },
      { id: 'evidence', label: 'Evidence', content: <EvidenceList instanceId={row.id} /> },
      { id: 'exceptions', label: 'Exceptions', content: <ExceptionsFor col="compliance_instance_id" id={row.id} /> },
      { id: 'audit', label: 'History', content: <PermissionGate perm="audit.read" mode="fallback" fallback={<p className="text-sm text-muted">Audit history is available to auditors.</p>}><AuditTab table="compliance_instance" id={row.id} /></PermissionGate> },
    ]} />
  )
}

type ActionRow = { id: string; action_type: string; note: string | null; created_at: string }
export function ExceptionQuickView({ row }: { row: ExceptionRow }) {
  const q = useRows<ActionRow>('exc-actions', 'exception_action', 'id,action_type,note,created_at', 'exception_id', row.id, 'created_at')
  const [comment, setComment] = useState(''); const qc = useQueryClient(); const { notify } = useToast()
  const add = useMutation({
    mutationFn: async () => { const { error } = await supabase!.from('exception_action').insert({ exception_id: row.id, action_type: 'comment', note: comment }); if (error) throw error },
    onSuccess: () => { setComment(''); void qc.invalidateQueries({ queryKey: ['quick'] }) }, onError: (e: Error) => notify(e.message, 'crit'),
  })
  return (
    <Tabs tabs={[
      { id: 'summary', label: 'Summary', content: (
        <div className="space-y-4">
          <div className="flex items-center gap-2"><Badge tone={severityTone(row.severity)}>{titleCase(row.severity)}</Badge><Badge>{titleCase(row.status)}</Badge>{row.target_breached && <Badge tone="crit">Target breached</Badge>}</div>
          <p className="text-sm text-ink">{row.description}</p>
          <Dl rows={[['Category', titleCase(row.category)], ['Age', `${row.age_days} day(s)`], ['Resolution target', row.due_date], ['Resolution', row.resolution]]} />
          {row.compliance_instance_id && <Link className="text-sm text-blue hover:underline" to="/compliance">Open obligations register</Link>}
          <PermissionGate perm="exception.write"><div className="border-t border-line pt-3"><h3 className="mb-2 text-sm font-semibold text-navy">Update status</h3><StatusActions module="exception" current={row.status} recordId={row.id} rpc="exception_set_status" noteIsResolution /></div></PermissionGate>
        </div>) },
      { id: 'timeline', label: 'Timeline', content: (
        <div className="space-y-4"><Loading q={q}>{(rows) => <Timeline items={rows.map((r) => ({ id: r.id, at: r.created_at, title: titleCase(r.action_type), description: r.note ?? undefined }))} />}</Loading>
          <PermissionGate perm="exception.write"><form className="space-y-2" onSubmit={(e) => { e.preventDefault(); add.mutate() }}><Field label="Add a comment">{(f) => <Textarea {...f} rows={2} value={comment} onChange={(e) => setComment(e.target.value)} />}</Field><Button type="submit" disabled={!comment.trim()} loading={add.isPending}>Add comment</Button></form></PermissionGate></div>) },
      { id: 'audit', label: 'History', content: <PermissionGate perm="audit.read" mode="fallback" fallback={<p className="text-sm text-muted">Audit history is available to auditors.</p>}><AuditTab table="exception" id={row.id} /></PermissionGate> },
    ]} />
  )
}

type LicEvent = { id: string; event_type: string; event_date: string; description: string | null }
export function LicenceQuickView({ row }: { row: LicenceRow }) {
  const ev = useRows<LicEvent>('lic-events', 'licence_event', 'id,event_type,event_date,description', 'licence_id', row.id, 'event_date')
  const b = expiryBadge(row.expiry_category)
  return (
    <Tabs tabs={[
      { id: 'summary', label: 'Summary', content: (
        <div className="space-y-4"><div className="flex items-center gap-2"><Badge tone={b.tone}>{b.label}</Badge>{row.renewal_window_open && <Badge tone="warn">Renewal window open</Badge>}</div>
          <Dl rows={[['Licence', `${row.licence_no}${row.licence_number ? ' · ' + row.licence_number : ''}`], ['Type', row.licence_type_name], ['Expiry', row.expiry_date ? `${row.expiry_date} (${row.days_to_expiry} day(s))` : 'No expiry'], ['Renewal status', titleCase(row.renewal_status)], ['Risk', row.risk_level ? titleCase(row.risk_level) : null], ['Lifecycle', titleCase(row.lifecycle_status)]]} /></div>) },
      { id: 'timeline', label: 'Timeline', content: <Loading q={ev}>{(rows) => <Timeline empty="No events recorded." items={rows.map((r) => ({ id: r.id, at: r.event_date, title: titleCase(r.event_type), description: r.description ?? undefined }))} />}</Loading> },
      { id: 'exceptions', label: 'Exceptions', content: <ExceptionsFor col="licence_id" id={row.id} /> },
    ]} />
  )
}

export function EvidenceQuickView({ row }: { row: EvidenceReqRow }) {
  const b = evidenceBadge[row.evidence_state] ?? evidenceBadge.missing
  return (
    <div className="space-y-4"><Badge tone={b.tone}>{b.label}</Badge>
      <Dl rows={[['Document', row.document_type_name], ['Obligation', row.instance_no], ['Due date', row.due_date], ['Evidence', row.evidence_no ? `${row.evidence_no} (v${row.version})` : 'Nothing uploaded'], ['Expiry', row.expiry_date]]} />
      <Link className="text-sm text-blue hover:underline" to={`/compliance?q=${encodeURIComponent(row.instance_no)}`}>Open the obligation</Link>
      {row.evidence_state === 'missing' && <EmptyState title="Upload not available yet" description="Document storage is not connected in this environment, so files cannot be attached from here." />}
    </div>
  )
}
