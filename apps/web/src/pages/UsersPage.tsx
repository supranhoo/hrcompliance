import { useState } from 'react'
import type { ColumnDef } from '@tanstack/react-table'
import { SmartTable } from '../components/table/SmartTable'
import { Badge, Drawer } from '../components/ui'
import { useServerTable } from '../hooks/useServerTable'

type UserRow = { id: string; email: string; full_name: string | null; status: 'invited' | 'active' | 'disabled'; scope_all: boolean; last_login_at: string | null }
const tone = { active: 'ok', invited: 'info', disabled: 'neutral' } as const
const columns: ColumnDef<UserRow, unknown>[] = [
  { accessorKey: 'full_name', header: 'Name', cell: (c) => c.getValue<string | null>() ?? '—' },
  { accessorKey: 'email', header: 'Email' },
  { accessorKey: 'status', header: 'Status', cell: (c) => <Badge tone={tone[c.getValue<UserRow['status']>()]}>{c.getValue<string>()}</Badge> },
  { accessorKey: 'scope_all', header: 'Scope', cell: (c) => (c.getValue<boolean>() ? 'All locations' : 'Restricted') },
  { accessorKey: 'last_login_at', header: 'Last login', cell: (c) => { const v = c.getValue<string | null>(); return v ? new Date(v).toLocaleString() : 'Never' } },
]

/** First real consumer of the server-side table framework. RLS decides which rows the caller may see. */
export function UsersPage() {
  const t = useServerTable<UserRow>('app_user', 'id,email,full_name,status,scope_all,last_login_at', { searchColumns: ['email', 'full_name'], sort: { id: 'email', desc: false } })
  const [selected, setSelected] = useState<UserRow | null>(null)
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-semibold text-navy">Users</h1>
      <SmartTable id="users" columns={columns} data={t.rows} total={t.total} query={t.query} onQueryChange={t.setQuery}
        isLoading={t.isLoading} error={t.error} onRetry={() => void t.refetch()} getRowId={(r) => r.id} onRowClick={setSelected}
        searchPlaceholder="Search name or email" emptyTitle="No users found" />
      <Drawer open={!!selected} onClose={() => setSelected(null)} title={selected?.full_name ?? selected?.email ?? 'User'}>
        {selected && <dl className="space-y-2 text-sm"><div><dt className="text-muted">Email</dt><dd>{selected.email}</dd></div><div><dt className="text-muted">Status</dt><dd>{selected.status}</dd></div></dl>}
      </Drawer>
    </section>
  )
}
