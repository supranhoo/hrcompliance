import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../components/table/Register'
import { Badge } from '../components/ui'

export type ExportLogRow = { id: string; created_at: string; register: string; filters: Record<string, unknown>; row_count: number; limit_reached: boolean; user_email: string | null; full_name: string | null }
const SELECT = 'id,created_at,register,filters,row_count,limit_reached,user_email,full_name'
const describeFilters = (f: Record<string, unknown>) => Object.entries(f).map(([k, v]) => `${k.replace(/_/g, ' ')}: ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`).join(' · ') || 'none'
const cols: ColumnDef<ExportLogRow, unknown>[] = [
  { accessorKey: 'created_at', header: 'When', cell: (c) => new Date(c.getValue<string>()).toLocaleString() },
  { accessorKey: 'user_email', header: 'Who', cell: (c) => c.row.original.full_name ?? c.getValue<string | null>() ?? '—' },
  { accessorKey: 'register', header: 'Register' },
  { accessorKey: 'row_count', header: 'Rows', cell: (c) => <span>{c.getValue<number>()}{c.row.original.limit_reached && <> <Badge tone="warn">limit reached</Badge></>}</span> },
  { accessorKey: 'filters', header: 'Filters', enableSorting: false, cell: (c) => <span className="text-xs text-muted">{describeFilters(c.getValue<Record<string, unknown>>() ?? {})}</span> },
]
/** Who exported what, with which filters and how many rows. Each person sees their own; audit.read sees everyone's. Append-only. */
export function ExportHistoryPage() {
  return <Register<ExportLogRow> id="export-history" title="Export History" table="v_export_log" select={SELECT} columns={cols} getRowId={(r) => r.id} searchColumns={['register', 'user_email']} defaultSort={{ id: 'created_at', desc: true }} filterDefs={[]} exportable={false} searchPlaceholder="Search register or person…" />
}
