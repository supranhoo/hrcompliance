import { useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Register, type FilterDef } from '../components/table/Register'
import { Badge, Button, ConfirmDialog, Dialog, Tabs } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { AuditTab } from '../pages/quickviews'
import { describeError, CONFLICT_MESSAGE } from './errors'
import { EntityForm } from './EntityForm'
import { emptyValues, valuesFromRow, type FieldSpec, type Mode, type Values } from './spec'
import { useSave } from './useSave'

export type AdminRow = { id: string; row_version: number; is_active?: boolean }
export type MasterSpec<T extends AdminRow> = {
  id: string; title: string; singular: string
  readTable: string; writeTable: string; select: string
  columns: ColumnDef<T, unknown>[]; searchColumns: string[]; defaultSort: { id: string; desc: boolean }
  filterDefs: FilterDef[]; extraKeys?: string[]
  fields: FieldSpec[]; permission: string
  titleOf: (r: T) => string
  /** Extra read-only facts shown under Details. */
  facts?: (r: T) => Array<[string, ReactNode]>
  /** Cross-field validation (e.g. effective period). Return a message to block saving. */
  extraValidate?: (v: Values, mode: Mode) => string | undefined
  /** Extra content on the details drawer (links to rule versions, etc.). */
  extraDetail?: (r: T) => ReactNode
  /** Defaults for the create form. */
  defaults?: Values
  /** Records are deactivated, never deleted. */
  hasActive?: boolean
  /** Per-row veto for the activate/deactivate button (e.g. system lists). The database enforces the same rule. */
  canToggle?: (r: T) => boolean
  searchPlaceholder?: string
}

const Dl = ({ rows }: { rows: Array<[string, ReactNode]> }) => <dl className="grid grid-cols-3 gap-x-3 gap-y-2 text-sm">{rows.map(([k, v]) => <div key={k} className="contents"><dt className="text-muted">{k}</dt><dd className="col-span-2 break-words">{v ?? '—'}</dd></div>)}</dl>

function FormBody<T extends AdminRow>({ spec, mode, row, onDone }: { spec: MasterSpec<T>; mode: Mode; row?: T; onDone: () => void }) {
  const [values, setValues] = useState<Values>(() => ({ ...emptyValues(spec.fields), ...(spec.defaults ?? {}), ...(row ? valuesFromRow(spec.fields, row as unknown as Record<string, unknown>) : {}) }))
  const { save, errors, busy } = useSave(spec.writeTable, spec.fields, { extra: spec.extraValidate })
  const set = (k: string, v: string | boolean) => setValues((s) => ({ ...s, [k]: v }))
  return (
    <form className="space-y-4" onSubmit={async (e) => { e.preventDefault(); const r = await save(values, mode, row ? { id: row.id, row_version: row.row_version } : undefined); if (r) onDone() }} noValidate>
      <EntityForm fields={spec.fields} values={values} errors={errors} mode={mode} onChange={set} />
      {errors._form && <p role="alert" className="text-sm text-status-crit">{errors._form}</p>}
      <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button type="submit" loading={busy}>{mode === 'create' ? `Create ${spec.singular}` : 'Save changes'}</Button></div>
    </form>
  )
}

function Detail<T extends AdminRow>({ spec, row, canManage, close }: { spec: MasterSpec<T>; row: T; canManage: boolean; close: () => void }) {
  const [editing, setEditing] = useState(false); const [confirm, setConfirm] = useState(false)
  const { notify } = useToast(); const qc = useQueryClient()
  const facts: Array<[string, ReactNode]> = [...spec.fields.filter((f) => f.type !== 'boolean' && f.type !== 'textarea').map((f) => [f.label, String((row as unknown as Record<string, unknown>)[f.key] ?? '') || '—'] as [string, ReactNode]),
    ...spec.fields.filter((f) => f.type === 'textarea').map((f) => [f.label, String((row as unknown as Record<string, unknown>)[f.key] ?? '') || '—'] as [string, ReactNode]), ...(spec.facts?.(row) ?? [])]
  async function toggle() {
    setConfirm(false)
    const { data, error } = await supabase!.from(spec.writeTable).update({ is_active: !row.is_active }).eq('id', row.id).eq('row_version', row.row_version).select().maybeSingle()
    if (error) return notify(describeError(error), 'crit'); if (!data) return notify(CONFLICT_MESSAGE, 'crit')
    notify(row.is_active ? 'Deactivated' : 'Activated', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); void qc.invalidateQueries({ queryKey: ['lookup'] }); close()
  }
  return (
    <>
      <Tabs tabs={[
        { id: 'details', label: 'Details', content: editing ? <FormBody spec={spec} mode="edit" row={row} onDone={() => { setEditing(false); close() }} /> : (
          <div className="space-y-4">
            {spec.hasActive && <Badge tone={row.is_active ? 'ok' : 'neutral'}>{row.is_active ? 'Active' : 'Inactive'}</Badge>}
            <Dl rows={facts} />
            {spec.extraDetail?.(row)}
            {canManage && <div className="flex gap-2"><Button onClick={() => setEditing(true)}>Edit</Button>{spec.hasActive && (spec.canToggle?.(row) ?? true) && <Button variant="secondary" onClick={() => setConfirm(true)}>{row.is_active ? 'Deactivate' : 'Activate'}</Button>}</div>}
          </div>) },
        { id: 'history', label: 'History', content: <AuditTab table={spec.writeTable} id={row.id} /> },
      ]} />
      <ConfirmDialog open={confirm} title={`${row.is_active ? 'Deactivate' : 'Activate'} ${spec.singular}`} message={row.is_active ? 'It will no longer be offered in pick-lists or generate new work. Existing records are not deleted.' : 'It will be offered in pick-lists again.'} confirmLabel={row.is_active ? 'Deactivate' : 'Activate'} danger={!!row.is_active} onConfirm={() => void toggle()} onCancel={() => setConfirm(false)} />
    </>
  )
}

/** Generic admin register: searchable/filterable server-side register + create dialog + details drawer (view, edit, activate/deactivate, audit history).
 *  Everything is spec-driven; permission checks here only hide buttons - RLS in PostgreSQL is the authority. */
export function AdminRegister<T extends AdminRow>({ spec }: { spec: MasterSpec<T> }) {
  const { access } = useAuth(); const canManage = can(access, spec.permission)
  const [creating, setCreating] = useState(false)
  return (
    <>
      <Register<T> id={spec.id} title={spec.title} table={spec.readTable} select={spec.select} columns={spec.columns} getRowId={(r) => r.id}
        searchColumns={spec.searchColumns} defaultSort={spec.defaultSort} filterDefs={spec.filterDefs} extraKeys={spec.extraKeys} searchPlaceholder={spec.searchPlaceholder}
        quickViewTitle={spec.titleOf} renderQuickView={(r, close) => <Detail spec={spec} row={r} canManage={canManage} close={close} />}
        actions={canManage ? <Button onClick={() => setCreating(true)}>New {spec.singular}</Button> : undefined} />
      <Dialog open={creating} onClose={() => setCreating(false)} title={`New ${spec.singular}`}>
        {creating && <FormBody spec={spec} mode="create" onDone={() => setCreating(false)} />}
      </Dialog>
    </>
  )
}
