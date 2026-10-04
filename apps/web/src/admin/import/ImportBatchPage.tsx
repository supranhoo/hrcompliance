import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Badge, Button, ConfirmDialog, Dialog, EmptyState, ErrorState, Field, Select, Skeleton, Textarea } from '../../components/ui'
import { useAuth } from '../../app/AuthProvider'
import { useToast } from '../../app/Toasts'
import { can } from '../../lib/access'
import { supabase } from '../../lib/supabase'
import { titleCase } from '../../lib/badges'
import { describeError } from '../errors'
import { BATCH_SELECT, STATUS_TONE, type BatchRow } from './ImportsPage'
import { download, errorsCsv, type ErrRow } from './importFile'
import { useTemplateDef } from './hooks'

type Msg = { column: string | null; message: string }
type RowRec = ErrRow & { action: string | null; target_id: string | null }
const PAGE = 50
const ROW_TONE: Record<string, 'ok' | 'warn' | 'crit' | 'neutral'> = { valid: 'ok', warning: 'warn', error: 'crit', committed: 'ok', failed: 'crit', skipped: 'neutral', pending: 'neutral' }
const FILTERS = [{ value: '', label: 'All rows' }, { value: 'error', label: 'Errors' }, { value: 'warning', label: 'Warnings' }, { value: 'valid', label: 'Valid' }, { value: 'committed', label: 'Imported' }, { value: 'skipped', label: 'Skipped' }, { value: 'failed', label: 'Failed' }]

export function ImportBatchPage() {
  const { id } = useParams(); const { access } = useAuth(); const canManage = can(access, 'import.manage'); const qc = useQueryClient(); const { notify } = useToast()
  const [filter, setFilter] = useState(''); const [page, setPage] = useState(0); const [confirm, setConfirm] = useState<null | 'all' | 'valid'>(null); const [cancel, setCancel] = useState(false); const [reason, setReason] = useState('')
  const batch = useQuery({ queryKey: ['import-batch', id], enabled: !!id && !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('v_import_batch').select(BATCH_SELECT).eq('id', id!).maybeSingle(); if (error) throw error; return data as BatchRow | null } })
  const def = useTemplateDef(batch.data?.template_code)
  const rows = useQuery({ queryKey: ['import-rows', id, filter, page, batch.data?.status, batch.data?.committed_rows], enabled: !!id && !!batch.data && !!supabase, queryFn: async () => {
    let q = supabase!.from('import_row').select('row_no,status,action,errors,warnings,raw,target_id', { count: 'exact' }).eq('batch_id', id!).order('row_no'); if (filter) q = q.eq('status', filter)
    const { data, error, count } = await q.range(page * PAGE, page * PAGE + PAGE - 1); if (error) throw error; return { rows: (data ?? []) as RowRec[], total: count ?? 0 } } })
  const refresh = () => { void qc.invalidateQueries({ queryKey: ['import-batch', id] }); void qc.invalidateQueries({ queryKey: ['import-rows', id] }); void qc.invalidateQueries({ queryKey: ['page'] }) }
  const commit = useMutation({ mutationFn: async (validOnly: boolean) => { const { data, error } = await supabase!.rpc('import_commit', { p_batch: id, p_valid_only: validOnly }); if (error) throw error; return data as { committed: number; failed: number; skipped: number } },
    onSuccess: (r) => { notify(`Imported ${r.committed} record(s)${r.skipped ? `, skipped ${r.skipped}` : ''}${r.failed ? `, ${r.failed} failed` : ''}`, r.failed ? 'crit' : 'ok'); setConfirm(null); refresh() }, onError: (e) => { setConfirm(null); notify(describeError(e), 'crit') } })
  const revalidate = useMutation({ mutationFn: async () => { const { error } = await supabase!.rpc('import_validate', { p_batch: id }); if (error) throw error }, onSuccess: () => { notify('Validated again', 'ok'); refresh() }, onError: (e) => notify(describeError(e), 'crit') })
  const doCancel = useMutation({ mutationFn: async () => { const { error } = await supabase!.rpc('import_cancel', { p_batch: id, p_reason: reason.trim() }); if (error) throw error }, onSuccess: () => { notify('Batch cancelled', 'ok'); setCancel(false); setReason(''); refresh() }, onError: (e) => notify(describeError(e), 'crit') })
  async function downloadProblems() {
    const all: RowRec[] = []; for (let p = 0; p < 200; p++) { const { data, error } = await supabase!.from('import_row').select('row_no,status,action,errors,warnings,raw,target_id').eq('batch_id', id!).in('status', ['error', 'failed', 'warning']).order('row_no').range(p * 1000, p * 1000 + 999); if (error) return notify(describeError(error), 'crit'); all.push(...((data ?? []) as RowRec[])); if ((data ?? []).length < 1000) break }
    download(`${batch.data?.batch_no ?? 'import'}_problems.csv`, errorsCsv(all, def.data?.columns ?? []))
  }
  if (batch.isLoading) return <Skeleton rows={5} />; if (batch.error) return <ErrorState message={describeError(batch.error)} />
  const b = batch.data; if (!b) return <EmptyState title="Batch not found" description="It does not exist or you do not have access to it." />
  const open = b.status === 'validated' || b.status === 'partially_committed'; const importable = b.valid_rows + b.warning_rows
  return (
    <section className="space-y-4">
      <div><Link className="text-sm text-blue hover:underline" to="/admin/imports">← Imports</Link>
        <h1 className="flex flex-wrap items-center gap-2 text-xl font-semibold text-navy">{b.batch_no} <Badge tone={STATUS_TONE[b.status] ?? 'neutral'}>{titleCase(b.status)}</Badge></h1>
        <p className="text-sm text-muted">{b.template_name} · {b.file_name} · uploaded {new Date(b.created_at).toLocaleString()}{b.created_by_email ? ` by ${b.created_by_email}` : ''}</p></div>
      <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7" aria-label="Batch summary">
        {([['Rows', b.total_rows, 'neutral'], ['Valid', b.valid_rows, 'ok'], ['Warnings', b.warning_rows, 'warn'], ['Errors', b.error_rows, b.error_rows ? 'crit' : 'ok'], ['Skipped', b.skipped_rows, 'neutral'], ['Imported', b.committed_rows, 'ok'], ['Failed', b.failed_rows, b.failed_rows ? 'crit' : 'ok']] as const).map(([k, v, tone]) => (
          <div key={k} className="rounded-lg border border-line bg-white p-3"><dt className="text-xs text-muted">{k}</dt><dd className="text-lg font-semibold"><Badge tone={tone}>{v}</Badge></dd></div>))}
      </dl>
      {b.status === 'cancelled' && <p className="rounded border border-line bg-white p-3 text-sm">Cancelled: {b.cancel_reason}. Nothing was imported.</p>}
      {canManage && open && (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border border-line bg-white p-3">
          {b.error_rows === 0 ? <Button onClick={() => setConfirm('all')} disabled={importable === 0}>Commit {importable} record(s)</Button> : <>
            <p className="w-full text-sm text-status-crit">{b.error_rows} row(s) have errors. Fix the file and upload it again, or import only the valid rows.</p>
            <Button variant="secondary" onClick={() => setConfirm('valid')} disabled={importable === 0}>Commit the {importable} valid row(s) only</Button></>}
          <Button variant="secondary" loading={revalidate.isPending} onClick={() => revalidate.mutate()}>Validate again</Button>
          {b.status === 'validated' && <Button variant="ghost" onClick={() => setCancel(true)}>Cancel this batch</Button>}
          {(b.error_rows > 0 || b.warning_rows > 0 || b.failed_rows > 0) && <Button variant="ghost" onClick={() => void downloadProblems()}>Download problems (CSV)</Button>}
        </div>)}
      {!open && (b.error_rows > 0 || b.warning_rows > 0 || b.failed_rows > 0) && <Button variant="ghost" onClick={() => void downloadProblems()}>Download problems (CSV)</Button>}
      <div className="flex items-end gap-2"><div className="w-48"><Select aria-label="Show rows" value={filter} options={FILTERS} onChange={(e) => { setFilter(e.target.value); setPage(0) }} /></div>
        <span className="text-sm text-muted">{rows.data ? `${rows.data.total} row(s)` : ''}</span></div>
      {rows.isLoading ? <Skeleton rows={4} /> : rows.error ? <ErrorState message={describeError(rows.error)} /> : (rows.data?.rows ?? []).length === 0 ? <EmptyState title="No rows" /> : (
        <div tabIndex={0} role="region" aria-label="Import rows, scrollable" className="overflow-x-auto rounded-lg border border-line bg-white"><table className="w-full text-left text-sm"><caption className="sr-only">Rows of {b.batch_no}</caption>
          <thead><tr className="border-b border-line text-muted"><th className="p-2">Row</th><th>Status</th><th>Action</th><th>Values</th><th>Problems</th></tr></thead>
          <tbody>{rows.data!.rows.map((r) => (
            <tr key={r.row_no} className="border-b border-line align-top"><td className="p-2">{r.row_no}</td><td><Badge tone={ROW_TONE[r.status] ?? 'neutral'}>{titleCase(r.status)}</Badge></td><td>{r.action ? titleCase(r.action) : '—'}</td>
              <td className="max-w-xs truncate text-muted" title={Object.entries(r.raw).map(([k, v]) => `${k}=${v}`).join('; ')}>{Object.values(r.raw).filter(Boolean).slice(0, 4).join(' · ')}</td>
              <td>{[...(r.errors as Msg[]).map((e) => ({ ...e, t: 'crit' as const })), ...(r.warnings as Msg[]).map((e) => ({ ...e, t: 'warn' as const }))].map((m, i) => <p key={i} className={m.t === 'crit' ? 'text-status-crit' : 'text-status-warn'}>{m.message}</p>)}</td></tr>))}</tbody></table></div>)}
      {rows.data && rows.data.total > PAGE && <div className="flex items-center justify-between text-sm"><Button variant="secondary" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Button><span>{page * PAGE + 1}–{Math.min((page + 1) * PAGE, rows.data.total)} of {rows.data.total}</span><Button variant="secondary" disabled={(page + 1) * PAGE >= rows.data.total} onClick={() => setPage(page + 1)}>Next</Button></div>}
      <ConfirmDialog open={confirm !== null} title="Commit import" confirmLabel="Commit" message={<div className="space-y-2"><p>{importable} record(s) will be written to the system now, under your own permissions and scope, and recorded in the audit history as {b.batch_no}.</p>{confirm === 'valid' && <p>{b.error_rows} row(s) with errors will NOT be imported.</p>}<p>This cannot be undone from here.</p></div>}
        onConfirm={() => commit.mutate(confirm === 'valid')} onCancel={() => setConfirm(null)} />
      <Dialog open={cancel} onClose={() => setCancel(false)} title="Cancel this batch" footer={<><Button variant="secondary" onClick={() => setCancel(false)}>Back</Button><Button variant="danger" disabled={!reason.trim()} loading={doCancel.isPending} onClick={() => doCancel.mutate()}>Cancel batch</Button></>}>
        <Field label="Reason" required help="Nothing has been imported. The same file can be uploaded again afterwards.">{(f) => <Textarea {...f} rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />}</Field></Dialog>
    </section>
  )
}
