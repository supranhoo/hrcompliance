import { Link, useNavigate } from 'react-router-dom'
import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../../components/table/Register'
import { Badge, Button, type Tone } from '../../components/ui'
import { useAuth } from '../../app/AuthProvider'
import { can } from '../../lib/access'
import { titleCase } from '../../lib/badges'

export type BatchRow = { id: string; batch_no: string; template_code: string; template_name: string; file_name: string; status: string; on_duplicate: string; total_rows: number; valid_rows: number; warning_rows: number; error_rows: number; skipped_rows: number; committed_rows: number; failed_rows: number; created_at: string; created_by_email: string | null; cancel_reason: string | null }
export const BATCH_SELECT = 'id,batch_no,template_code,template_name,file_name,status,on_duplicate,total_rows,valid_rows,warning_rows,error_rows,skipped_rows,committed_rows,failed_rows,created_at,created_by_email,cancel_reason,validated_at,committed_at'
export const STATUS_TONE: Record<string, Tone> = { staged: 'warn', validated: 'warn', committing: 'warn', committed: 'ok', partially_committed: 'crit', cancelled: 'neutral' }
const STATUSES = ['staged', 'validated', 'committed', 'partially_committed', 'cancelled'].map((v) => ({ value: v, label: titleCase(v) }))

const cols: ColumnDef<BatchRow, unknown>[] = [
  { accessorKey: 'batch_no', header: 'Batch', cell: (c) => <Link className="font-medium text-blue hover:underline" to={`/admin/imports/${c.row.original.id}`} onClick={(e) => e.stopPropagation()}>{c.getValue<string>()}</Link> },
  { accessorKey: 'template_name', header: 'Template' }, { accessorKey: 'file_name', header: 'File' },
  { accessorKey: 'status', header: 'Status', cell: (c) => <Badge tone={STATUS_TONE[c.getValue<string>()] ?? 'neutral'}>{titleCase(c.getValue<string>())}</Badge> },
  { id: 'rows', header: 'Rows', cell: (c) => { const r = c.row.original; return `${r.total_rows} · ${r.error_rows} errors · ${r.committed_rows} imported` } },
  { accessorKey: 'created_at', header: 'Uploaded', cell: (c) => new Date(c.getValue<string>()).toLocaleString() },
  { accessorKey: 'created_by_email', header: 'By', cell: (c) => c.getValue<string | null>() ?? '—' },
]

export function ImportsPage() {
  const { access } = useAuth(); const nav = useNavigate(); const canImport = can(access, 'import.manage')
  return <Register<BatchRow> id="imports" title="Imports" table="v_import_batch" select={BATCH_SELECT} columns={cols} getRowId={(r) => r.id} searchColumns={['batch_no', 'file_name', 'template_name']} defaultSort={{ id: 'created_at', desc: true }}
    searchPlaceholder="Search batch, file or template…" filterDefs={[{ key: 'status', label: 'Status', options: STATUSES }, { key: 'template_code', label: 'Template', lookup: { table: 'import_template', value: 'code', label: 'name' } }]}
    quickViewTitle={(r) => `${r.batch_no} · ${r.template_name}`} renderQuickView={(r) => (
      <div className="space-y-3 text-sm"><p>{r.file_name}</p><Badge tone={STATUS_TONE[r.status] ?? 'neutral'}>{titleCase(r.status)}</Badge>
        <dl className="grid grid-cols-3 gap-x-3 gap-y-1"><dt className="text-muted">Rows</dt><dd className="col-span-2">{r.total_rows}</dd><dt className="text-muted">Valid / warnings</dt><dd className="col-span-2">{r.valid_rows} / {r.warning_rows}</dd><dt className="text-muted">Errors / skipped</dt><dd className="col-span-2">{r.error_rows} / {r.skipped_rows}</dd><dt className="text-muted">Imported / failed</dt><dd className="col-span-2">{r.committed_rows} / {r.failed_rows}</dd><dt className="text-muted">Duplicates</dt><dd className="col-span-2">{titleCase(r.on_duplicate)}</dd>{r.cancel_reason && <><dt className="text-muted">Cancelled because</dt><dd className="col-span-2">{r.cancel_reason}</dd></>}</dl>
        <Link className="inline-block text-blue hover:underline" to={`/admin/imports/${r.id}`}>Open batch →</Link></div>)}
    actions={canImport ? <Button onClick={() => nav('/admin/imports/new')}>New import</Button> : undefined} />
}
