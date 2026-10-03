import { useEffect, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Button, Dialog, ErrorState, Field, Skeleton } from '../components/ui'
import { DatePicker, Select, Textarea } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { describeError, CONFLICT_MESSAGE } from './errors'
import { EntityForm } from './EntityForm'
import { ACTIVE_OPTIONS, CODE_MESSAGE, CODE_PATTERN, LICENCE_EVENT_TYPES, LICENCE_LIFECYCLE } from './domain'
import { emptyValues, toPayload, validate, valuesFromRow, type FieldSpec, type Values } from './spec'
import type { AdminRow, MasterSpec } from './AdminRegister'

export type LicenceTypeRow = AdminRow & { code: string; name: string; authority_id: string | null; default_renewal_lead_days: number; default_risk: string | null; document_type_id: string | null; has_expiry: boolean }
export const licenceTypeSpec: MasterSpec<LicenceTypeRow> = {
  id: 'licence-types', title: 'Licence & Registration Types', singular: 'licence type', hasActive: true, readTable: 'licence_type', writeTable: 'licence_type', permission: 'compliance.manage',
  select: 'id,code,name,authority_id,default_renewal_lead_days,default_risk,document_type_id,has_expiry,is_active,row_version', searchColumns: ['code', 'name'], defaultSort: { id: 'code', desc: false },
  filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }, { key: 'default_risk', label: 'Risk', lov: 'RISK' }], titleOf: (r) => `${r.code} · ${r.name}`,
  columns: [{ accessorKey: 'code', header: 'Code' }, { accessorKey: 'name', header: 'Name' }, { accessorKey: 'default_renewal_lead_days', header: 'Renewal lead (days)' },
    { accessorKey: 'has_expiry', header: 'Expires', cell: (c) => (c.getValue<boolean>() ? 'Yes' : 'No expiry') }, { accessorKey: 'is_active', header: 'Status', cell: (c) => (c.getValue<boolean>() ? 'Active' : 'Inactive') }],
  fields: [
    { key: 'code', label: 'Code', type: 'text', required: true, immutable: true, pattern: CODE_PATTERN, patternMessage: CODE_MESSAGE, max: 32 }, { key: 'name', label: 'Name', type: 'text', required: true, max: 200 },
    { key: 'authority_id', label: 'Issuing authority', type: 'select', lookup: { table: 'authority', value: 'id', label: 'name', filter: { is_active: true } } },
    { key: 'default_renewal_lead_days', label: 'Renewal lead time (days before expiry)', type: 'number', required: true, min: 0, max: 730, help: 'Default for new licences of this type; each licence can override it' },
    { key: 'default_risk', label: 'Default risk', type: 'select', lov: 'RISK' },
    { key: 'document_type_id', label: 'Certificate document type', type: 'select', lookup: { table: 'document_type', value: 'id', label: 'name', filter: { is_active: true } } },
    { key: 'has_expiry', label: 'Has an expiry date', type: 'boolean', help: 'Untick for registrations that never expire' }, { key: 'is_active', label: 'Active', type: 'boolean' },
  ],
  defaults: { default_renewal_lead_days: '60', has_expiry: true, is_active: true },
}

const LFIELDS: FieldSpec[] = [
  { key: 'licence_type_id', label: 'Licence / registration type', type: 'select', required: true, lookup: { table: 'licence_type', value: 'id', label: 'name', filter: { is_active: true } } },
  { key: 'entity_id', label: 'Legal entity', type: 'select', required: true, immutable: true, lookup: { table: 'entity', value: 'id', label: 'name', filter: { is_active: true } } },
  { key: 'location_id', label: 'Location', type: 'select', lookup: { table: 'location', value: 'id', label: 'code', filter: { is_active: true } }, help: 'Blank = entity-wide' },
  { key: 'authority_id', label: 'Issuing authority', type: 'select', lookup: { table: 'authority', value: 'id', label: 'name', filter: { is_active: true } } },
  { key: 'licence_number', label: 'Number issued by the authority', type: 'text', max: 100, help: 'As printed on the certificate — never invented' },
  { key: 'issue_date', label: 'Issue date', type: 'date' }, { key: 'effective_date', label: 'Effective date', type: 'date' }, { key: 'expiry_date', label: 'Expiry date', type: 'date' },
  { key: 'renewal_lead_days', label: 'Renewal lead time (days)', type: 'number', required: true, min: 0, max: 730, help: 'Starts the renewal window; defaults from the type' },
  { key: 'owner_user_id', label: 'Owner', type: 'select', lookup: { table: 'app_user', value: 'id', label: 'email', filter: { status: 'active' } } },
  { key: 'risk_level', label: 'Risk', type: 'select', lov: 'RISK' }, { key: 'renewal_status', label: 'Renewal status', type: 'select', lov: 'LICENCE_RENEWAL_STATUS' },
  { key: 'lifecycle_status', label: 'Lifecycle', type: 'select', options: LICENCE_LIFECYCLE },
  { key: 'is_new_application', label: 'New application (not yet issued)', type: 'boolean' },
  { key: 'remarks', label: 'Remarks', type: 'textarea', max: 2000 },
]
import { useLicenceTypes, type TypeInfo } from './lookups'
/** Pure rule shared with the tests: what a licence needs given its type. */
export function licenceProblems(v: Values, type: Pick<TypeInfo, 'has_expiry'> | undefined): Record<string, string> {
  const e: Record<string, string> = {}
  const str = (k: string) => (typeof v[k] === 'string' ? (v[k] as string) : '')
  if (type?.has_expiry && !str('expiry_date') && v.is_new_application !== true && v.lifecycle_status === 'active') e.expiry_date = 'Expiry date is required for this type of licence'
  const [i, f, x] = [str('issue_date'), str('effective_date'), str('expiry_date')]
  if (i && x && x < i) e.expiry_date = 'Expiry cannot be before the issue date'
  if (f && x && x < f) e.expiry_date = 'Expiry cannot be before the effective date'
  return e
}

export function LicenceForm({ mode, id, onDone }: { mode: 'create' | 'edit'; id?: string; onDone: () => void }) {
  const base = useQuery({ queryKey: ['licence-edit', id], enabled: mode === 'edit' && !!id && !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('licence').select('*').eq('id', id!).maybeSingle(); if (error) throw error; return data as (Record<string, unknown> & { row_version: number }) | null } })
  if (mode === 'edit' && base.isLoading) return <Skeleton rows={4} />
  if (mode === 'edit' && (base.error || !base.data)) return <ErrorState message={base.error ? (base.error as Error).message : 'The licence was not found or is outside your scope.'} />
  return <LicenceFormBody mode={mode} row={base.data ?? undefined} onDone={onDone} />
}
function LicenceFormBody({ mode, row, onDone }: { mode: 'create' | 'edit'; row?: Record<string, unknown> & { row_version: number; id?: string }; onDone: () => void }) {
  const types = useLicenceTypes(); const { notify } = useToast(); const qc = useQueryClient()
  const [values, setValues] = useState<Values>(() => ({ ...emptyValues(LFIELDS), renewal_lead_days: '60', renewal_status: 'not_started', lifecycle_status: 'active', is_new_application: false, ...(row ? valuesFromRow(LFIELDS, row) : {}) }))
  const [errors, setErrors] = useState<Record<string, string>>({}); const [busy, setBusy] = useState(false); const leadTouched = useRef(mode === 'edit')
  const type = types.data?.find((t) => t.id === values.licence_type_id)
  useEffect(() => { if (mode === 'create' && type && !leadTouched.current) setValues((s) => ({ ...s, renewal_lead_days: String(type.default_renewal_lead_days), risk_level: s.risk_level || type.default_risk || '' })) }, [type?.id])   // eslint-disable-line react-hooks/exhaustive-deps
  const set = (k: string, v: string | boolean) => { if (k === 'renewal_lead_days') leadTouched.current = true; setValues((s) => ({ ...s, [k]: v })) }
  async function submit(e: React.FormEvent) {
    e.preventDefault(); const errs = { ...validate(LFIELDS, values, mode), ...licenceProblems(values, type) }; setErrors(errs); if (Object.keys(errs).length || !supabase) return
    setBusy(true)
    try {
      const payload = toPayload(LFIELDS, values, mode)
      const r = mode === 'create' ? await supabase.from('licence').insert(payload).select().single() : await supabase.from('licence').update(payload).eq('id', row!.id as string).eq('row_version', row!.row_version).select().maybeSingle()
      if (r.error) return notify(describeError(r.error), 'crit'); if (!r.data) return notify(CONFLICT_MESSAGE, 'crit')
      notify(mode === 'create' ? 'Licence created' : 'Licence saved', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); void qc.invalidateQueries({ queryKey: ['dashboard'] }); onDone()
    } finally { setBusy(false) }
  }
  return (
    <form className="space-y-4" onSubmit={(e) => void submit(e)} noValidate>
      <EntityForm fields={LFIELDS} values={values} errors={errors} mode={mode} onChange={set} />
      <p className="text-xs text-muted">The expiry state (valid, within 90/60/30/15/7 days, expired) is derived from the expiry date and the configured thresholds; it is never typed in.</p>
      <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button type="submit" loading={busy}>{mode === 'create' ? 'Create licence' : 'Save changes'}</Button></div>
    </form>
  )
}

export function LicenceEventForm({ licenceId, onDone }: { licenceId: string; onDone: () => void }) {
  const [type, setType] = useState('note'); const [date, setDate] = useState(new Date().toISOString().slice(0, 10)); const [desc, setDesc] = useState(''); const [busy, setBusy] = useState(false)
  const { notify } = useToast(); const qc = useQueryClient()
  async function go() { setBusy(true); const { error } = await supabase!.from('licence_event').insert({ licence_id: licenceId, event_type: type, event_date: date, description: desc.trim() || null }); setBusy(false)
    if (error) return notify(describeError(error), 'crit'); notify('Event logged', 'ok'); void qc.invalidateQueries({ queryKey: ['quick'] }); onDone() }
  return (
    <div className="space-y-3">
      <Field label="Event" required>{(f) => <Select {...f} value={type} options={LICENCE_EVENT_TYPES} onChange={(e) => setType(e.target.value)} />}</Field>
      <Field label="Date" required>{(f) => <DatePicker {...f} value={date} onChange={(e) => setDate(e.target.value)} />}</Field>
      <Field label="Description">{(f) => <Textarea {...f} rows={2} value={desc} onChange={(e) => setDesc(e.target.value)} />}</Field>
      <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button disabled={!date} loading={busy} onClick={() => void go()}>Log event</Button></div>
    </div>
  )
}

/** Buttons shown under the licence quick view for users with licence.write. RLS enforces scope; the form only guides. */
export function LicenceActions({ id, close }: { id: string; close: () => void }) {
  const { access } = useAuth(); const [mode, setMode] = useState<'edit' | 'event' | null>(null)
  if (!can(access, 'licence.write')) return null
  return (<>
    <div className="mt-4 flex gap-2 border-t border-line pt-3"><Button onClick={() => setMode('edit')}>Edit licence</Button><Button variant="secondary" onClick={() => setMode('event')}>Log event</Button></div>
    <Dialog open={mode === 'edit'} onClose={() => setMode(null)} title="Edit licence">{mode === 'edit' && <LicenceForm mode="edit" id={id} onDone={() => { setMode(null); close() }} />}</Dialog>
    <Dialog open={mode === 'event'} onClose={() => setMode(null)} title="Log licence event">{mode === 'event' && <LicenceEventForm licenceId={id} onDone={() => setMode(null)} />}</Dialog>
  </>)
}
export function NewLicenceButton() {
  const { access } = useAuth(); const [open, setOpen] = useState(false)
  if (!can(access, 'licence.write')) return null
  return (<><Button onClick={() => setOpen(true)}>New licence</Button><Dialog open={open} onClose={() => setOpen(false)} title="New licence / registration">{open && <LicenceForm mode="create" onDone={() => setOpen(false)} />}</Dialog></>)
}
