import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../components/table/Register'
import { Badge, Button, ConfirmDialog, DatePicker, Dialog, Field, Input, Select, Tabs, Textarea, type Tone } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { titleCase } from '../lib/badges'
import { AuditTab } from '../pages/quickviews'
import { describeError, CONFLICT_MESSAGE } from './errors'
import { EntityForm } from './EntityForm'
import { APPLICABILITY_STATUS } from './domain'
import { describeAst, draftErrors, emptyDraft, fromAst, FACTS, OPS, toAst, type Draft } from './condition'
import { emptyValues, toPayload, validate, validatePeriod, valuesFromRow, type FieldSpec, type Values } from './spec'
import type { AdminRow } from './AdminRegister'

export type ApplicabilityRow = AdminRow & {
  compliance_id: string; compliance_code: string; compliance_name: string; entity_id: string | null; entity_code: string | null; location_id: string | null; location_code: string | null; location_name: string | null
  business_unit_id: string | null; business_unit_name: string | null; state: string | null; establishment_type: string | null; industry: string | null
  employee_headcount_min: number | null; employee_headcount_max: number | null; contractor_headcount_min: number | null; contractor_headcount_max: number | null
  status: 'applicable' | 'not_applicable' | 'conditional'; condition: unknown; reason: string | null; source_reference: string | null; effective_from: string; effective_to: string | null; in_effect: boolean
}
export const AP_SELECT = 'id,compliance_id,compliance_code,compliance_name,entity_id,entity_code,location_id,location_code,location_name,business_unit_id,business_unit_name,state,establishment_type,industry,employee_headcount_min,employee_headcount_max,contractor_headcount_min,contractor_headcount_max,status,condition,reason,source_reference,effective_from,effective_to,is_active,row_version,in_effect'
const TONE: Record<string, Tone> = { applicable: 'ok', not_applicable: 'neutral', conditional: 'warn' }
export const SPECIFICITY_HELP = 'The most specific matching row wins: location, then business unit, then entity, then state, establishment type, industry and headcount. If equally specific rows disagree, “applicable” wins and the conflict is flagged under Coverage & gaps.'

export function scopeSummary(r: Pick<ApplicabilityRow, 'entity_code' | 'location_code' | 'business_unit_name' | 'state' | 'establishment_type' | 'industry' | 'employee_headcount_min' | 'employee_headcount_max' | 'contractor_headcount_min' | 'contractor_headcount_max'>): string {
  const p: string[] = []
  if (r.location_code) p.push(`Location ${r.location_code}`); if (r.business_unit_name) p.push(`Unit ${r.business_unit_name}`); if (r.entity_code) p.push(`Entity ${r.entity_code}`)
  if (r.state) p.push(`State ${r.state}`); if (r.establishment_type) p.push(`Type ${r.establishment_type}`); if (r.industry) p.push(`Industry ${r.industry}`)
  const range = (a: number | null, b: number | null) => `${a ?? 0}–${b ?? '∞'}`
  if (r.employee_headcount_min != null || r.employee_headcount_max != null) p.push(`Employees ${range(r.employee_headcount_min, r.employee_headcount_max)}`)
  if (r.contractor_headcount_min != null || r.contractor_headcount_max != null) p.push(`Contractors ${range(r.contractor_headcount_min, r.contractor_headcount_max)}`)
  return p.length ? p.join(' · ') : 'Everywhere (global)'
}

const FIELDS: FieldSpec[] = [
  { key: 'compliance_id', label: 'Compliance', type: 'select', required: true, immutable: true, lookup: { table: 'compliance_master', value: 'id', label: 'code', filter: { is_active: true } } },
  { key: 'entity_id', label: 'Legal entity', type: 'select', lookup: { table: 'entity', value: 'id', label: 'name', filter: { is_active: true } }, help: 'Blank = any entity' },
  { key: 'location_id', label: 'Location', type: 'select', lookup: { table: 'location', value: 'id', label: 'code', filter: { is_active: true } }, help: 'Blank = any location' },
  { key: 'business_unit_id', label: 'Business unit', type: 'select', lookup: { table: 'business_unit', value: 'id', label: 'name', filter: { is_active: true } } },
  { key: 'state', label: 'State', type: 'text', max: 80 }, { key: 'establishment_type', label: 'Establishment type', type: 'text', max: 80 }, { key: 'industry', label: 'Industry', type: 'text', max: 120 },
  { key: 'employee_headcount_min', label: 'Employees — at least', type: 'number', min: 0 }, { key: 'employee_headcount_max', label: 'Employees — at most', type: 'number', min: 0 },
  { key: 'contractor_headcount_min', label: 'Contractors — at least', type: 'number', min: 0 }, { key: 'contractor_headcount_max', label: 'Contractors — at most', type: 'number', min: 0 },
  { key: 'status', label: 'Decision', type: 'select', required: true, options: APPLICABILITY_STATUS },
  { key: 'reason', label: 'Reason', type: 'textarea', max: 1000 }, { key: 'source_reference', label: 'Source reference', type: 'text', max: 500, help: 'As supplied by BFCL — never invented' },
  { key: 'effective_from', label: 'Effective from', type: 'date', required: true }, { key: 'effective_to', label: 'Effective to', type: 'date' },
]

export function ConditionBuilder({ value, onChange, errors }: { value: Draft; onChange: (d: Draft) => void; errors: string[] }) {
  const upd = (i: number, patch: Partial<Draft['leaves'][number]>) => onChange({ ...value, leaves: value.leaves.map((l, k) => k === i ? { ...l, ...patch } : l) })
  return (
    <fieldset className="space-y-2 rounded border border-line p-3">
      <legend className="px-1 text-sm font-medium">Condition</legend>
      <div className="flex items-center gap-2 text-sm"><span>Applies when</span>
        <Select aria-label="Match" className="w-40" value={value.join} options={[{ value: 'and', label: 'ALL of these' }, { value: 'or', label: 'ANY of these' }]} onChange={(e) => onChange({ ...value, join: e.target.value as 'and' | 'or' })} /></div>
      {value.leaves.map((l, i) => {
        const fact = FACTS.find((f) => f.key === l.field) ?? FACTS[0]; const ops = OPS[fact.type]; const blank = l.op === 'is_blank' || l.op === 'is_not_blank'
        return (
          <div key={i} className="grid grid-cols-1 gap-2 sm:grid-cols-[1.4fr_1fr_1fr_auto]">
            <Select aria-label={`Fact ${i + 1}`} value={l.field} options={FACTS.map((f) => ({ value: f.key, label: f.label }))} onChange={(e) => { const nf = FACTS.find((f) => f.key === e.target.value)!; upd(i, { field: nf.key, op: OPS[nf.type][0].op, value: '' }) }} />
            <Select aria-label={`Comparison ${i + 1}`} value={l.op} options={ops.map((o) => ({ value: o.op, label: o.label }))} onChange={(e) => upd(i, { op: e.target.value })} />
            {blank ? <span /> : <Input aria-label={`Value ${i + 1}`} value={l.value} placeholder={l.op === 'in' || l.op === 'not_in' ? 'comma separated' : ''} aria-invalid={errors[i] ? true : undefined} onChange={(e) => upd(i, { value: e.target.value })} />}
            <Button variant="ghost" disabled={value.leaves.length === 1} aria-label={`Remove condition ${i + 1}`} onClick={() => onChange({ ...value, leaves: value.leaves.filter((_, k) => k !== i) })}>✕</Button>
            {errors[i] && <p role="alert" className="text-xs text-status-crit sm:col-span-4">{errors[i]}</p>}
          </div>)
      })}
      <Button variant="secondary" onClick={() => onChange({ ...value, leaves: [...value.leaves, { field: FACTS[0].key, op: OPS.number[0].op, value: '' }] })}>Add condition</Button>
      <p className="text-xs text-muted">Facts come from the location and entity masters. An unknown fact makes a comparison false and is reported under Coverage & gaps — never silently assumed.</p>
    </fieldset>
  )
}

type Mode = 'create' | 'edit' | 'replace'
export function ApplicabilityForm({ mode, row, initial, onDone }: { mode: Mode; row?: ApplicabilityRow; initial?: Partial<Values>; onDone: () => void }) {
  const [values, setValues] = useState<Values>(() => {
    const v = { ...emptyValues(FIELDS), ...(row ? valuesFromRow(FIELDS, row as unknown as Record<string, unknown>) : {}), ...(initial as Values) }
    if (mode === 'replace') { v.effective_from = ''; v.effective_to = '' }
    return v
  })
  const [cond, setCond] = useState<Draft>(() => (row && fromAst(row.condition)) || emptyDraft())
  const [reason, setReason] = useState(''); const [errors, setErrors] = useState<Record<string, string>>({}); const [condErrs, setCondErrs] = useState<string[]>([]); const [busy, setBusy] = useState(false)
  const { notify } = useToast(); const qc = useQueryClient(); const fm = mode === 'create' ? 'create' : 'edit'   // replace/edit lock the compliance (identity)
  const set = (k: string, v: string | boolean) => setValues((s) => ({ ...s, [k]: v }))
  const conditional = values.status === 'conditional'
  const legacy = row && row.condition != null && !fromAst(row.condition)
  async function submit(e: React.FormEvent) {
    e.preventDefault()
    const errs = validate(FIELDS, values, fm)
    const p = validatePeriod(values, 'effective_from', 'effective_to'); if (p) errs.effective_to = p
    for (const [a, b, l] of [['employee_headcount_min', 'employee_headcount_max', 'Employees'], ['contractor_headcount_min', 'contractor_headcount_max', 'Contractors']] as const)
      if (values[a] !== '' && values[b] !== '' && Number(values[a]) > Number(values[b])) errs[b] = `${l}: the minimum cannot exceed the maximum`
    if (values.status === 'not_applicable' && !String(values.reason).trim()) errs.reason = 'A reason is required for “not applicable”'
    const ce = conditional ? draftErrors(cond) : []; setCondErrs(ce)
    if (mode === 'replace' && !reason.trim()) errs.change_reason = 'A reason for the change is required'
    setErrors(errs); if (Object.keys(errs).length || ce.some(Boolean) || !supabase) return
    setBusy(true)
    try {
      const payload: Record<string, unknown> = { ...toPayload(FIELDS, values, fm), condition: conditional ? (legacy && !cond.leaves.some((l) => l.value) ? row!.condition : toAst(cond)) : null }
      if (mode === 'create') { const r = await supabase.from('compliance_applicability').insert(payload).select().single(); if (r.error) return notify(describeError(r.error), 'crit') }
      else if (mode === 'edit') { const r = await supabase.from('compliance_applicability').update(payload).eq('id', row!.id).eq('row_version', row!.row_version).select().maybeSingle(); if (r.error) return notify(describeError(r.error), 'crit'); if (!r.data) return notify(CONFLICT_MESSAGE, 'crit') }
      else { const r = await supabase.rpc('applicability_replace', { p_old: row!.id, p_new: payload, p_reason: reason.trim() }); if (r.error) return notify(describeError(r.error), 'crit') }
      notify(mode === 'replace' ? 'Decision replaced; the previous one ends the day before' : 'Saved', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); onDone()
    } finally { setBusy(false) }
  }
  return (
    <form className="space-y-4" onSubmit={(e) => void submit(e)} noValidate>
      {mode === 'replace' && <p className="rounded bg-canvas p-2 text-sm">The current decision stays in history and ends the day before the new one starts. In-effect decisions are never rewritten.</p>}
      <EntityForm fields={FIELDS} values={values} errors={errors} mode={fm} onChange={set} />
      {Object.keys(values).length > 0 && !values.entity_id && !values.location_id && !values.business_unit_id && !values.state && !values.establishment_type && !values.industry && <p className="text-xs text-muted">No scope selected: this decision applies everywhere and needs unrestricted access.</p>}
      {conditional && (legacy && !cond.leaves.some((l) => l.value) ? <p className="rounded border border-line p-2 text-sm">Existing condition (kept as is): {describeAst(row!.condition)}</p> : <ConditionBuilder value={cond} onChange={setCond} errors={condErrs} />)}
      {mode === 'replace' && <Field label="Reason for the change" required error={errors.change_reason}>{(f) => <Textarea {...f} rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />}</Field>}
      <p className="text-xs text-muted">{SPECIFICITY_HELP}</p>
      <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button type="submit" loading={busy}>{mode === 'create' ? 'Add decision' : mode === 'replace' ? 'Replace decision' : 'Save changes'}</Button></div>
    </form>
  )
}

function EndDialog({ row, open, onClose, onDone }: { row: ApplicabilityRow; open: boolean; onClose: () => void; onDone: () => void }) {
  const [to, setTo] = useState(new Date().toISOString().slice(0, 10)); const [reason, setReason] = useState(''); const { notify } = useToast(); const qc = useQueryClient()
  const m = useMutation({ mutationFn: async () => { const { error } = await supabase!.rpc('applicability_end', { p_id: row.id, p_effective_to: to, p_reason: reason.trim() }); if (error) throw error },
    onSuccess: () => { notify('Decision ended', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); onDone() }, onError: (e) => notify(describeError(e), 'crit') })
  return (
    <Dialog open={open} onClose={onClose} title="End this decision" footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!reason.trim() || !to} loading={m.isPending} onClick={() => m.mutate()}>End decision</Button></>}>
      <div className="space-y-3"><Field label="Last day in effect" required>{(f) => <DatePicker {...f} value={to} onChange={(e) => setTo(e.target.value)} />}</Field>
        <Field label="Reason" required>{(f) => <Textarea {...f} rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />}</Field>
        <p className="text-xs text-muted">Obligations already generated are not changed by an applicability change; future generation follows the new matrix.</p></div>
    </Dialog>)
}

function Detail({ row, canManage, close }: { row: ApplicabilityRow; canManage: boolean; close: () => void }) {
  const [mode, setMode] = useState<Mode | null>(null); const [end, setEnd] = useState(false); const [deact, setDeact] = useState(false); const { notify } = useToast(); const qc = useQueryClient()
  const started = row.effective_from <= new Date().toISOString().slice(0, 10)
  async function deactivate() { setDeact(false); const { data, error } = await supabase!.from('compliance_applicability').update({ is_active: false }).eq('id', row.id).eq('row_version', row.row_version).select().maybeSingle(); if (error) return notify(describeError(error), 'crit'); if (!data) return notify(CONFLICT_MESSAGE, 'crit'); notify('Decision deactivated', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); close() }
  const facts: Array<[string, React.ReactNode]> = [['Compliance', `${row.compliance_code} · ${row.compliance_name}`], ['Applies to', scopeSummary(row)], ['Decision', titleCase(row.status)],
    ['Condition', row.condition ? describeAst(row.condition) : '—'], ['Reason', row.reason ?? '—'], ['Source', row.source_reference ?? '—'], ['Effective', `${row.effective_from} → ${row.effective_to ?? 'open-ended'}`], ['In effect today', row.in_effect ? 'Yes' : 'No']]
  return (<>
    <Tabs tabs={[
      { id: 'details', label: 'Details', content: mode === 'edit' || mode === 'replace' ? <ApplicabilityForm mode={mode} row={row} onDone={() => { setMode(null); close() }} /> : (
        <div className="space-y-4">
          <dl className="grid grid-cols-3 gap-x-3 gap-y-2 text-sm">{facts.map(([k, v]) => <div key={k} className="contents"><dt className="text-muted">{k}</dt><dd className="col-span-2 break-words">{v}</dd></div>)}</dl>
          <p className="text-xs text-muted">{SPECIFICITY_HELP}</p>
          {canManage && row.is_active && <div className="flex flex-wrap gap-2">
            {!started && <Button onClick={() => setMode('edit')}>Edit</Button>}
            {started && <Button onClick={() => setMode('replace')}>Replace decision…</Button>}
            {started && !row.effective_to && <Button variant="secondary" onClick={() => setEnd(true)}>End…</Button>}
            {!started && <Button variant="secondary" onClick={() => setDeact(true)}>Deactivate</Button>}</div>}
          {started && <p className="text-xs text-muted">This decision is in effect and cannot be edited: replace it or end it, with a reason.</p>}
        </div>) },
      { id: 'history', label: 'History', content: <AuditTab table="compliance_applicability" id={row.id} /> },
    ]} />
    <EndDialog row={row} open={end} onClose={() => setEnd(false)} onDone={() => { setEnd(false); close() }} />
    <ConfirmDialog open={deact} title="Deactivate decision" message="It stops applying immediately (it had not started yet). History is kept." confirmLabel="Deactivate" danger onConfirm={() => void deactivate()} onCancel={() => setDeact(false)} />
  </>)
}

const cols: ColumnDef<ApplicabilityRow, unknown>[] = [
  { accessorKey: 'compliance_code', header: 'Compliance' },
  { id: 'scope', header: 'Applies to', cell: (c) => scopeSummary(c.row.original) },
  { accessorKey: 'status', header: 'Decision', cell: (c) => <Badge tone={TONE[c.getValue<string>()] ?? 'neutral'}>{titleCase(c.getValue<string>())}</Badge> },
  { accessorKey: 'condition', header: 'Condition', cell: (c) => (c.getValue() ? describeAst(c.getValue()) : '—') },
  { accessorKey: 'effective_from', header: 'Effective', cell: (c) => `${c.getValue<string>()} → ${c.row.original.effective_to ?? 'open'}` },
  { accessorKey: 'in_effect', header: 'Now', cell: (c) => <Badge tone={c.getValue<boolean>() ? 'ok' : 'neutral'}>{c.getValue<boolean>() ? 'In effect' : 'Not in effect'}</Badge> },
]

export function ApplicabilityPage() {
  const { access } = useAuth(); const canManage = can(access, 'compliance.manage'); const [params, setParams] = useSearchParams()
  const [open, setOpen] = useState(params.get('add') === '1')
  const initial: Partial<Values> = { compliance_id: params.get('compliance_id') ?? '', location_id: params.get('location_id') ?? '' }
  const close = () => { setOpen(false); if (params.has('add')) { const n = new URLSearchParams(params); ['add', 'compliance_id', 'location_id'].forEach((k) => n.delete(k)); setParams(n, { replace: true }) } }
  return (<>
    <div className="mb-2 flex gap-3 text-sm"><span className="font-medium">Matrix</span><Link className="text-blue hover:underline" to="/admin/applicability/coverage">Coverage & gaps →</Link></div>
    <Register<ApplicabilityRow> id="applicability" title="Applicability Matrix" table="v_applicability" select={AP_SELECT} columns={cols} getRowId={(r) => r.id}
      searchColumns={['compliance_code', 'compliance_name', 'location_code', 'state']} defaultSort={{ id: 'compliance_code', desc: false }} extraKeys={['compliance_code', 'location_code']} searchPlaceholder="Search compliance, location or state…"
      filterDefs={[{ key: 'status', label: 'Outcome', options: APPLICABILITY_STATUS }, { key: 'in_effect', label: 'Now', options: [{ value: 'true', label: 'In effect' }, { value: 'false', label: 'Not in effect' }] }]}
      quickViewTitle={(r) => `${r.compliance_code} · ${titleCase(r.status)}`} renderQuickView={(r, c) => <Detail row={r} canManage={canManage} close={c} />}
      actions={canManage ? <Button onClick={() => setOpen(true)}>Add decision</Button> : undefined} />
    <Dialog open={open} onClose={close} title="Add applicability decision">{open && <ApplicabilityForm mode="create" initial={initial} onDone={close} />}</Dialog>
  </>)
}

type CoverageRow = { compliance_id: string; compliance_code: string; location_id: string; location_code: string; decision: string; effective_status: string; conflict: boolean; missing_facts: string[]; missing_fact_count: number; is_gap: boolean }
const covTone: Record<string, Tone> = { applicable: 'ok', not_applicable: 'neutral', unmapped: 'crit' }
export function CoveragePage() {
  const { access } = useAuth(); const canManage = can(access, 'compliance.manage');
  const cols2: ColumnDef<CoverageRow, unknown>[] = [
    { accessorKey: 'compliance_code', header: 'Compliance' }, { accessorKey: 'location_code', header: 'Location' },
    { accessorKey: 'effective_status', header: 'Effective decision', cell: (c) => <Badge tone={covTone[c.getValue<string>()] ?? 'neutral'}>{c.getValue<string>() === 'unmapped' ? 'Unmapped — no decision' : titleCase(c.getValue<string>())}</Badge> },
    { accessorKey: 'conflict', header: 'Conflict', cell: (c) => c.getValue<boolean>() ? <Badge tone="warn">Conflicting rows</Badge> : '—' },
    { accessorKey: 'missing_facts', header: 'Unknown facts', cell: (c) => (c.getValue<string[]>() ?? []).join(', ') || '—' },
    { id: 'act', header: '', cell: (c) => canManage && c.row.original.is_gap ? <Link className="text-blue hover:underline" to={`/admin/applicability?add=1&compliance_id=${c.row.original.compliance_id}&location_id=${c.row.original.location_id}`}>Add decision</Link> : null },
  ]
  return (<>
    <div className="mb-2 flex gap-3 text-sm"><Link className="text-blue hover:underline" to="/admin/applicability">← Matrix</Link><span className="font-medium">Coverage & gaps</span></div>
    <Register<CoverageRow> id="coverage" title="Coverage & gaps" table="v_compliance_coverage" select="compliance_id,compliance_code,location_id,location_code,decision,effective_status,conflict,missing_facts,missing_fact_count,is_gap"
      columns={cols2} getRowId={(r) => `${r.compliance_id}:${r.location_id}`} searchColumns={['compliance_code', 'location_code']} defaultSort={{ id: 'compliance_code', desc: false }} searchPlaceholder="Search compliance or location…"
      filterDefs={[{ key: 'effective_status', label: 'Decision', options: [{ value: 'applicable', label: 'Applicable' }, { value: 'not_applicable', label: 'Not applicable' }, { value: 'unmapped', label: 'Unmapped (gap)' }] }, { key: 'conflict', label: 'Conflict', options: [{ value: 'true', label: 'Conflicting rows' }] }]} />
    <p className="mt-2 text-xs text-muted">Only locations inside your scope are listed. A gap means no matrix row covers that compliance at that location; no obligations are generated for it until a decision is added.</p>
  </>)
}
