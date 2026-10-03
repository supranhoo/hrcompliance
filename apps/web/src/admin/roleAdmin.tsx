import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../components/table/Register'
import { Badge, Button, Dialog, ErrorState, Field, Input, Skeleton, Tabs, Textarea } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { useGuardedRpc } from './guardedRpc'
import { CRITICAL_PERMISSIONS, diffPermissions, groupByModule, touchesCritical, validateRoleForm, type PermissionRow } from './accessLogic'

export type RoleRow = { id: string; code: string; name: string; description: string | null; is_system: boolean; permissions: string[]; user_count: number; grants_role_admin: boolean }
const SELECT = 'id,code,name,description,is_system,permissions,user_count,grants_role_admin'

type Change = { id: number; at: string; action: string; reason: string | null; permission: string | null }
/** Permission changes of one role, read from the audit log (rows carry the role id inside the stored data). */
function PermissionHistory({ roleId }: { roleId: string }) {
  const q = useQuery({ queryKey: ['role-history', roleId], enabled: !!supabase, queryFn: async (): Promise<Change[]> => {
    const { data, error } = await supabase!.from('audit_log').select('id,at,action,reason,old_data,new_data').eq('table_name', 'role_permission').or(`new_data->>role_id.eq.${roleId},old_data->>role_id.eq.${roleId}`).order('at', { ascending: false }).limit(100)
    if (error) throw error
    return (data ?? []).map((r) => { const d = (r.new_data ?? r.old_data) as { permission_code?: string } | null; return { id: r.id as number, at: r.at as string, action: r.action as string, reason: r.reason as string | null, permission: d?.permission_code ?? null } })
  } })
  if (q.isLoading) return <Skeleton rows={3} />; if (q.error) return <ErrorState message={(q.error as Error).message} />
  if (!q.data?.length) return <p className="text-sm text-muted">No permission changes recorded.</p>
  return <ul className="space-y-1 text-sm">{q.data.map((c) => <li key={c.id} className="rounded border border-line p-2"><span className={c.action === 'DELETE' ? 'text-status-crit' : 'text-status-ok'}>{c.action === 'DELETE' ? '− removed' : '+ granted'}</span> <span className="font-mono text-xs">{c.permission}</span> <span className="text-xs text-muted">{new Date(c.at).toLocaleString()}{c.reason ? ` · ${c.reason}` : ''}</span></li>)}</ul>
}

export function usePermissionCatalogue() {
  return useQuery({ queryKey: ['permission-catalogue'], enabled: !!supabase, staleTime: 60_000, queryFn: async (): Promise<PermissionRow[]> => { const { data, error } = await supabase!.from('permission').select('code,module,description').order('code'); if (error) throw error; return (data ?? []) as PermissionRow[] } })
}

/** Role form + permission matrix. Saves through role_save (reason mandatory, audited, guarded); the matrix writes the same role_permission rows RLS and the menu read. */
export function RoleEditor({ role, canEdit, onDone }: { role?: RoleRow; canEdit: boolean; onDone: () => void }) {
  const cat = usePermissionCatalogue(); const { run, dialog, busy } = useGuardedRpc(['permission-catalogue']); const isNew = !role
  const [code, setCode] = useState(role?.code ?? ''); const [name, setName] = useState(role?.name ?? ''); const [description, setDescription] = useState(role?.description ?? '')
  const [perms, setPerms] = useState<string[]>(role?.permissions ?? []); const [reason, setReason] = useState(''); const [errors, setErrors] = useState<Record<string, string>>({})
  const diff = useMemo(() => diffPermissions(role?.permissions ?? [], perms), [role, perms]); const readOnlyIdentity = !canEdit || !!role?.is_system
  async function save() {
    const errs = validateRoleForm({ code, name, reason }, isNew); setErrors(errs); if (Object.keys(errs).length) return
    const ok = await run('role_save', { p_code: code, p_name: name.trim(), p_description: description, p_permissions: perms, p_reason: reason.trim(), p_confirm_self: false }, isNew ? `Role ${code} created` : `Role ${code} updated`)
    if (ok) onDone()
  }
  if (cat.isLoading) return <Skeleton rows={4} />; if (cat.error) return <ErrorState message={(cat.error as Error).message} />
  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Role code" required error={errors.code} help={isNew ? 'Capital letters, digits, underscore. It never changes afterwards.' : 'A code never changes'}>{(f) => <Input {...f} value={code} disabled={!isNew} onChange={(e) => setCode(e.target.value.toUpperCase())} />}</Field>
        <Field label="Name" required error={errors.name}>{(f) => <Input {...f} value={name} disabled={readOnlyIdentity} onChange={(e) => setName(e.target.value)} />}</Field>
      </div>
      <Field label="Description">{(f) => <Textarea {...f} rows={2} value={description} disabled={readOnlyIdentity} onChange={(e) => setDescription(e.target.value)} />}</Field>
      {role?.is_system && <p className="text-xs text-muted">System role: its name is fixed, but its permissions can be changed here.</p>}
      <fieldset className="space-y-3"><legend className="text-sm font-medium">Permissions <span className="font-normal text-muted">({perms.length} selected)</span></legend>
        {groupByModule(cat.data ?? []).map((g) => (
          <div key={g.module} className="rounded border border-line p-2"><h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted">{g.module}</h4>
            <ul className="grid gap-1 sm:grid-cols-2">{g.items.map((p) => (
              <li key={p.code}><label className="flex items-start gap-2 text-sm"><input type="checkbox" className="mt-1" disabled={!canEdit} checked={perms.includes(p.code)} onChange={(e) => setPerms(e.target.checked ? [...perms, p.code] : perms.filter((x) => x !== p.code))} />
                <span><span className="font-mono text-xs">{p.code}</span>{(CRITICAL_PERMISSIONS as readonly string[]).includes(p.code) && <> <Badge tone="warn">admin</Badge></>}<span className="block text-xs text-muted">{p.description}</span></span></label></li>))}</ul>
          </div>))}
      </fieldset>
      {canEdit && (<>
        {(diff.added.length > 0 || diff.removed.length > 0) && <p className="rounded bg-canvas p-2 text-sm" aria-live="polite">Change: {diff.added.length > 0 && <span className="text-status-ok">+ {diff.added.join(', ')} </span>}{diff.removed.length > 0 && <span className="text-status-crit">− {diff.removed.join(', ')}</span>}{touchesCritical(diff) && <strong className="block text-status-crit">This removes an administrative permission.</strong>}</p>}
        <Field label="Reason for this change" required error={errors.reason} help="Recorded in the audit history">{(f) => <Textarea {...f} rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />}</Field>
        <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button loading={busy} onClick={() => void save()}>{isNew ? 'Create role' : 'Save permissions'}</Button></div>
      </>)}
      {dialog}
    </div>
  )
}

const cols: ColumnDef<RoleRow, unknown>[] = [
  { accessorKey: 'name', header: 'Role', cell: (c) => <span><span className="font-medium">{c.getValue<string>()}</span> <span className="text-muted">{c.row.original.code}</span></span> },
  { accessorKey: 'permissions', header: 'Permissions', enableSorting: false, cell: (c) => (c.getValue<string[]>() ?? []).length },
  { accessorKey: 'user_count', header: 'Users' },
  { accessorKey: 'is_system', header: 'Kind', cell: (c) => <Badge tone={c.getValue<boolean>() ? 'info' : 'neutral'}>{c.getValue<boolean>() ? 'System' : 'Custom'}</Badge> },
  { accessorKey: 'grants_role_admin', header: 'Administers roles', cell: (c) => (c.getValue<boolean>() ? <Badge tone="warn">Yes</Badge> : '—') },
]
export function RolesPage() {
  const { access } = useAuth(); const canEdit = can(access, 'role.admin'); const [creating, setCreating] = useState(false)
  return (<div className="space-y-4">
    <p className="rounded border border-line bg-white p-3 text-sm text-muted">The permissions ticked here decide both what each person sees in the menu and what the database allows them to change. Nothing depends on a role’s name. At least one active user must always keep role administration.</p>
    <Register<RoleRow> id="roles" title="Roles & Permissions" table="v_role_admin" select={SELECT} columns={cols} getRowId={(r) => r.id} searchColumns={['code', 'name']} defaultSort={{ id: 'name', desc: false }} searchPlaceholder="Search roles…"
      filterDefs={[{ key: 'is_system', label: 'Kind', options: [{ value: 'true', label: 'System' }, { value: 'false', label: 'Custom' }] }]}
      quickViewTitle={(r) => r.name} renderQuickView={(r, close) => (
        <Tabs tabs={[{ id: 'perm', label: 'Permissions', content: <RoleEditor role={r} canEdit={canEdit} onDone={close} /> }, { id: 'audit', label: 'History', content: <PermissionHistory roleId={r.id} /> }]} />)}
      actions={canEdit ? <Button onClick={() => setCreating(true)}>New role</Button> : undefined} />
    <Dialog open={creating} onClose={() => setCreating(false)} title="New role">{creating && <RoleEditor canEdit onDone={() => setCreating(false)} />}</Dialog>
  </div>)
}
