import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../components/table/Register'
import { Badge, Button, Dialog, ErrorState, Field, Input, Skeleton, Tabs, Textarea, type Tone } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { AuditTab } from '../pages/quickviews'
import { useLookup } from './lookups'
import { useGuardedRpc } from './guardedRpc'
import { validateInvite, validateScope } from './accessLogic'

export type UserAdminRow = { id: string; email: string; full_name: string | null; status: 'invited' | 'active' | 'disabled'; scope_all: boolean; last_login_at: string | null; signed_in: boolean; roles: string[]; entity_scopes: number; location_scopes: number; is_role_admin: boolean }
const SELECT = 'id,email,full_name,status,scope_all,last_login_at,signed_in,roles,entity_scopes,location_scopes,is_role_admin'
const TONE: Record<string, Tone> = { active: 'ok', invited: 'info', disabled: 'neutral' }
const REASON_HELP = 'Recorded in the audit history'

function ReasonField({ value, onChange, error }: { value: string; onChange: (v: string) => void; error?: string }) {
  return <Field label="Reason" required error={error} help={REASON_HELP}>{(f) => <Textarea {...f} rows={2} value={value} onChange={(e) => onChange(e.target.value)} />}</Field>
}
function CheckList({ legend, options, value, onChange, disabled }: { legend: string; options: Array<{ value: string; label: string }>; value: string[]; onChange: (v: string[]) => void; disabled?: boolean }) {
  const [q, setQ] = useState(''); const shown = options.filter((o) => o.label.toLowerCase().includes(q.toLowerCase()) || value.includes(o.value))
  return (
    <fieldset className="space-y-1"><legend className="text-sm font-medium">{legend} <span className="font-normal text-muted">({value.length} selected)</span></legend>
      {options.length > 8 && <Input aria-label={`Filter ${legend}`} placeholder="Filter…" value={q} onChange={(e) => setQ(e.target.value)} />}
      <ul className="max-h-48 space-y-1 overflow-auto rounded border border-line p-2">{shown.map((o) => <li key={o.value}><label className="flex items-center gap-2 text-sm"><input type="checkbox" disabled={disabled} checked={value.includes(o.value)} onChange={(e) => onChange(e.target.checked ? [...value, o.value] : value.filter((x) => x !== o.value))} />{o.label}</label></li>)}</ul>
    </fieldset>
  )
}

function InviteForm({ onDone }: { onDone: () => void }) {
  const { run, dialog, busy } = useGuardedRpc(); const [email, setEmail] = useState(''); const [name, setName] = useState(''); const [reason, setReason] = useState(''); const [roles, setRoles] = useState<string[]>([]); const [errors, setErrors] = useState<Record<string, string>>({})
  const roleOpts = useLookup({ table: 'role', value: 'code', label: 'name' }); const { access } = useAuth(); const canRoles = can(access, 'role.admin')
  async function submit(e: React.FormEvent) {
    e.preventDefault(); const errs = validateInvite({ email, reason }); setErrors(errs); if (Object.keys(errs).length) return
    const ok = await run('user_invite', { p_email: email.trim(), p_full_name: name, p_roles: canRoles ? roles : [], p_reason: reason.trim() }, `${email.trim()} invited`); if (ok) onDone()
  }
  return (
    <form className="space-y-3" onSubmit={(e) => void submit(e)} noValidate>
      <Field label="Email (Google account)" required error={errors.email}>{(f) => <Input {...f} type="email" value={email} onChange={(e) => setEmail(e.target.value)} />}</Field>
      <Field label="Full name">{(f) => <Input {...f} value={name} onChange={(e) => setName(e.target.value)} />}</Field>
      {canRoles ? <CheckList legend="Roles" options={roleOpts.data ?? []} value={roles} onChange={setRoles} /> : <p className="text-xs text-muted">Roles are assigned by someone with role administration. A new user sees nothing until they have a role and a scope.</p>}
      <ReasonField value={reason} onChange={setReason} error={errors.reason} />
      <p className="text-xs text-muted">The person signs in with Google using this email. Until they do, the account stays “invited”.</p>
      <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button type="submit" loading={busy}>Invite user</Button></div>
      {dialog}
    </form>
  )
}

function StatusPanel({ u, canEdit, close }: { u: UserAdminRow; canEdit: boolean; close: () => void }) {
  const { run, dialog, busy } = useGuardedRpc(); const [reason, setReason] = useState(''); const [err, setErr] = useState('')
  const next = u.status === 'disabled' ? 'active' : 'disabled'
  async function go() { if (!reason.trim()) return setErr('A reason is required'); setErr(''); if (await run('user_set_status', { p_user: u.id, p_status: next, p_reason: reason.trim(), p_confirm_self: false }, next === 'disabled' ? `${u.email} disabled` : `${u.email} re-enabled`)) close() }
  return (
    <div className="space-y-3 text-sm">
      <dl className="grid grid-cols-3 gap-x-3 gap-y-2"><dt className="text-muted">Email</dt><dd className="col-span-2">{u.email}</dd><dt className="text-muted">Status</dt><dd className="col-span-2"><Badge tone={TONE[u.status]}>{u.status}</Badge> {!u.signed_in && <span className="text-xs text-muted">has not signed in yet</span>}</dd>
        <dt className="text-muted">Roles</dt><dd className="col-span-2">{u.roles.join(', ') || 'None: this user sees nothing'}</dd><dt className="text-muted">Last sign-in</dt><dd className="col-span-2">{u.last_login_at ? new Date(u.last_login_at).toLocaleString() : 'Never'}</dd></dl>
      {canEdit && <div className="space-y-2 border-t border-line pt-3"><ReasonField value={reason} onChange={setReason} error={err} /><Button variant={next === 'disabled' ? 'danger' : 'primary'} loading={busy} onClick={() => void go()}>{next === 'disabled' ? 'Disable user' : 'Re-enable user'}</Button></div>}
      {dialog}
    </div>
  )
}

function RolesPanel({ u, canEdit, close }: { u: UserAdminRow; canEdit: boolean; close: () => void }) {
  const { run, dialog, busy } = useGuardedRpc(); const opts = useLookup({ table: 'role', value: 'code', label: 'name' }); const [roles, setRoles] = useState(u.roles); const [reason, setReason] = useState(''); const [err, setErr] = useState('')
  async function save() { if (!reason.trim()) return setErr('A reason is required'); setErr(''); if (await run('user_set_roles', { p_user: u.id, p_roles: roles, p_reason: reason.trim(), p_confirm_self: false }, `Roles updated for ${u.email}`)) close() }
  return (
    <div className="space-y-3">
      <CheckList legend="Roles" options={opts.data ?? []} value={roles} onChange={setRoles} disabled={!canEdit} />
      {!canEdit ? <p className="text-xs text-muted">Changing roles needs role administration.</p> : <><ReasonField value={reason} onChange={setReason} error={err} /><Button loading={busy} onClick={() => void save()}>Save roles</Button></>}
      {dialog}
    </div>
  )
}

function ScopePanel({ u, canEdit, close }: { u: UserAdminRow; canEdit: boolean; close: () => void }) {
  const { run, dialog, busy } = useGuardedRpc(['user-scope']); const ents = useLookup({ table: 'entity', value: 'id', label: 'name' }); const locs = useLookup({ table: 'location', value: 'id', label: 'name' })
  const cur = useQuery({ queryKey: ['user-scope', u.id], enabled: !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('v_user_scope').select('scope_type,scope_id').eq('user_id', u.id); if (error) throw error; return (data ?? []) as Array<{ scope_type: 'entity' | 'location'; scope_id: string }> } })
  if (cur.isLoading) return <Skeleton rows={3} />; if (cur.error) return <ErrorState message={(cur.error as Error).message} />
  return <ScopeForm key={u.id} u={u} canEdit={canEdit} close={close} run={run} busy={busy} dialog={dialog} entOpts={ents.data ?? []} locOpts={locs.data ?? []} initialEntities={(cur.data ?? []).filter((s) => s.scope_type === 'entity').map((s) => s.scope_id)} initialLocations={(cur.data ?? []).filter((s) => s.scope_type === 'location').map((s) => s.scope_id)} />
}
function ScopeForm({ u, canEdit, close, run, busy, dialog, entOpts, locOpts, initialEntities, initialLocations }: { u: UserAdminRow; canEdit: boolean; close: () => void; run: ReturnType<typeof useGuardedRpc>['run']; busy: boolean; dialog: React.ReactNode; entOpts: Array<{ value: string; label: string }>; locOpts: Array<{ value: string; label: string }>; initialEntities: string[]; initialLocations: string[] }) {
  const [all, setAll] = useState(u.scope_all); const [entities, setEntities] = useState(initialEntities); const [locations, setLocations] = useState(initialLocations); const [reason, setReason] = useState(''); const [errors, setErrors] = useState<Record<string, string>>({})
  async function save() { const errs = validateScope({ scopeAll: all, entities, locations, reason }); setErrors(errs); if (Object.keys(errs).length) return; if (await run('user_set_scope', { p_user: u.id, p_scope_all: all, p_entities: all ? [] : entities, p_locations: all ? [] : locations, p_reason: reason.trim() }, `Scope updated for ${u.email}`)) close() }
  return (
    <div className="space-y-3">
      <label className="flex items-center gap-2 text-sm font-medium"><input type="checkbox" disabled={!canEdit} checked={all} onChange={(e) => setAll(e.target.checked)} /> All locations (unrestricted)</label>
      {!all && <><CheckList legend="Legal entities" options={entOpts} value={entities} onChange={setEntities} disabled={!canEdit} /><CheckList legend="Locations" options={locOpts} value={locations} onChange={setLocations} disabled={!canEdit} /></>}
      {errors.scope && <p role="alert" className="text-xs text-status-crit">{errors.scope}</p>}
      <p className="text-xs text-muted">Entity access covers all locations of that entity. Department scope is not enforced by access checks yet, so it is not offered here.</p>
      {canEdit && <><ReasonField value={reason} onChange={setReason} error={errors.reason} /><Button loading={busy} onClick={() => void save()}>Save scope</Button></>}
      {dialog}
    </div>
  )
}

const cols: ColumnDef<UserAdminRow, unknown>[] = [
  { accessorKey: 'full_name', header: 'Name', cell: (c) => c.getValue<string | null>() ?? '—' }, { accessorKey: 'email', header: 'Email' },
  { accessorKey: 'status', header: 'Status', cell: (c) => <Badge tone={TONE[c.getValue<string>()] ?? 'neutral'}>{c.getValue<string>()}</Badge> },
  { accessorKey: 'roles', header: 'Roles', enableSorting: false, cell: (c) => (c.getValue<string[]>() ?? []).join(', ') || '—' },
  { id: 'scope', header: 'Scope', enableSorting: false, cell: (c) => { const r = c.row.original; return r.scope_all ? 'All locations' : `${r.entity_scopes} entities · ${r.location_scopes} locations` } },
  { accessorKey: 'last_login_at', header: 'Last sign-in', cell: (c) => { const v = c.getValue<string | null>(); return v ? new Date(v).toLocaleString() : 'Never' } },
]
export function UsersAdminPage() {
  const { access } = useAuth(); const canUsers = can(access, 'user.admin'); const canRoles = can(access, 'role.admin'); const [inviting, setInviting] = useState(false)
  return (<div className="space-y-4">
    <Register<UserAdminRow> id="users" title="Users" table="v_user_admin" select={SELECT} columns={cols} getRowId={(r) => r.id} searchColumns={['email', 'full_name']} defaultSort={{ id: 'email', desc: false }} searchPlaceholder="Search name or email"
      filterDefs={[{ key: 'status', label: 'Status', options: [{ value: 'active', label: 'Active' }, { value: 'invited', label: 'Invited' }, { value: 'disabled', label: 'Disabled' }] }]}
      quickViewTitle={(r) => r.full_name ?? r.email}
      renderQuickView={(r, close) => (<Tabs tabs={[
        { id: 'user', label: 'User', content: <StatusPanel u={r} canEdit={canUsers} close={close} /> },
        { id: 'roles', label: 'Roles', content: <RolesPanel u={r} canEdit={canRoles} close={close} /> },
        { id: 'scope', label: 'Scope', content: <ScopePanel u={r} canEdit={canUsers} close={close} /> },
        { id: 'audit', label: 'History', content: <AuditTab table="app_user" id={r.id} /> }]} />)}
      actions={canUsers ? <Button onClick={() => setInviting(true)}>Invite user</Button> : undefined} />
    <Dialog open={inviting} onClose={() => setInviting(false)} title="Invite user">{inviting && <InviteForm onDone={() => setInviting(false)} />}</Dialog>
  </div>)
}
