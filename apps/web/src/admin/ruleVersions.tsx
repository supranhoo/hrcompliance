import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../components/table/Register'
import { Badge, Button, ConfirmDialog, Dialog, EmptyState, ErrorState, Field, Input, Select, Skeleton, Tabs, Textarea, DatePicker, type Tone } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { titleCase } from '../lib/badges'
import { AuditTab } from '../pages/quickviews'
import { describeError, CONFLICT_MESSAGE } from './errors'
import { EntityForm } from './EntityForm'
import { useLookup } from './lookups'
import { FREQUENCIES, MONTHS } from './domain'
import { defaultRule, describeDueRule, RULE_TYPE_LABEL, ruleTypesFor, validateDueRule, type DueRule, type DueRuleType } from './dueRule'
import { validate, toPayload, valuesFromRow, emptyValues, type FieldSpec, type Values } from './spec'
import type { AdminRow } from './AdminRegister'

export type RuleVersionRow = AdminRow & {
  compliance_id: string; compliance_code: string; compliance_name: string; version: number; status: 'draft' | 'active' | 'retired'; compliance_type: string; frequency: string
  period_start_month: number; due_rule: DueRule; risk_level: string; criticality: string; evidence_required: boolean; alert_rule_code: string | null; escalation_rule_code: string | null
  effective_from: string; effective_to: string | null; change_reason: string | null; evidence_count: number; obligation_count: number
}
export const RV_SELECT = 'id,compliance_id,compliance_code,compliance_name,version,status,compliance_type,frequency,period_start_month,due_rule,risk_level,criticality,evidence_required,alert_rule_code,escalation_rule_code,effective_from,effective_to,change_reason,row_version,evidence_count,obligation_count'
export const STATUS_TONE: Record<string, Tone> = { active: 'ok', draft: 'warn', retired: 'neutral' }
export const STATUS_HELP: Record<string, string> = {
  draft: 'Draft — not in effect. It can be edited or discarded. Activating it retires the current version from the day before its effective date.',
  active: 'Active — this is the rule in force. It can never be edited; create a new version to change it.',
  retired: 'Retired — historical. Obligations created under it keep this rule.',
}

const FIELDS: FieldSpec[] = [
  { key: 'compliance_type', label: 'Compliance type', type: 'select', required: true, lov: 'COMPLIANCE_TYPE' },
  { key: 'frequency', label: 'Frequency', type: 'select', required: true, options: FREQUENCIES },
  { key: 'risk_level', label: 'Risk', type: 'select', required: true, lov: 'RISK' },
  { key: 'criticality', label: 'Criticality', type: 'select', required: true, lov: 'CRITICALITY' },
  { key: 'alert_rule_code', label: 'Reminder rule', type: 'select', lookup: { table: 'config_definition', value: 'code', label: 'name', filter: { kind: 'alert_rule', status: 'active' } }, help: 'Blank = default reminders' },
  { key: 'escalation_rule_code', label: 'Escalation rule', type: 'select', lookup: { table: 'config_definition', value: 'code', label: 'name', filter: { kind: 'alert_rule', status: 'active' } }, help: 'Blank = default escalation' },
  { key: 'effective_from', label: 'Effective from', type: 'date', required: true },
  { key: 'evidence_required', label: 'Evidence required', type: 'boolean', help: 'Documents are configured on the Evidence tab' },
]

export function DueRuleEditor({ frequency, value, onChange, error }: { frequency: string; value: DueRule | null; onChange: (r: DueRule | null) => void; error?: string }) {
  const types = ruleTypesFor(frequency); const r = value && types.includes(value.type) ? value : null
  const num = (k: string, v: string) => onChange({ ...(r as DueRule), [k]: v === '' ? NaN : Number(v) } as DueRule)
  if (types.length === 0) return <p className="text-sm text-muted">Choose a frequency first.</p>
  return (
    <fieldset className="space-y-2 rounded border border-line p-3" aria-describedby={error ? 'due-err' : undefined}>
      <legend className="px-1 text-sm font-medium">Due date rule</legend>
      <Select aria-label="Due date rule type" value={r?.type ?? ''} placeholder="Select…" options={types.map((t) => ({ value: t, label: RULE_TYPE_LABEL[t] }))} onChange={(e) => onChange(e.target.value ? defaultRule(e.target.value as DueRuleType) : null)} />
      {r?.type === 'day_of_month' && <div className="grid grid-cols-2 gap-2"><Field label="Day of month">{(f) => <Input {...f} inputMode="numeric" value={Number.isNaN(r.day) ? '' : r.day} onChange={(e) => num('day', e.target.value)} />}</Field><Field label="Months after period end">{(f) => <Input {...f} inputMode="numeric" value={Number.isNaN(r.month_offset) ? '' : r.month_offset} onChange={(e) => num('month_offset', e.target.value)} />}</Field></div>}
      {(r?.type === 'days_after_period_end' || r?.type === 'days_after_event') && <Field label="Days">{(f) => <Input {...f} inputMode="numeric" value={Number.isNaN(r.days) ? '' : r.days} onChange={(e) => num('days', e.target.value)} />}</Field>}
      {r?.type === 'fixed_date' && <div className="grid grid-cols-3 gap-2"><Field label="Month">{(f) => <Select {...f} options={MONTHS} value={String(r.month)} onChange={(e) => num('month', e.target.value)} />}</Field><Field label="Day">{(f) => <Input {...f} inputMode="numeric" value={Number.isNaN(r.day) ? '' : r.day} onChange={(e) => num('day', e.target.value)} />}</Field><Field label="Years after">{(f) => <Input {...f} inputMode="numeric" value={Number.isNaN(r.year_offset) ? '' : r.year_offset} onChange={(e) => num('year_offset', e.target.value)} />}</Field></div>}
      {r?.type === 'absolute_date' && <Field label="Date">{(f) => <DatePicker {...f} value={r.date} onChange={(e) => onChange({ type: 'absolute_date', date: e.target.value })} />}</Field>}
      {r && !error && <p className="text-xs text-muted">Reads as: due {describeDueRule(r)}</p>}
      {error && <p id="due-err" role="alert" className="text-xs text-status-crit">{error}</p>}
    </fieldset>
  )
}

/** Create the FIRST version of a compliance, or edit a DRAFT. Published versions are never edited (the database refuses). */
export function RuleVersionForm({ mode, row, complianceId, onDone }: { mode: 'create' | 'edit'; row?: RuleVersionRow; complianceId?: string; onDone: () => void }) {
  const [values, setValues] = useState<Values>(() => ({ ...emptyValues(FIELDS), evidence_required: false, ...(row ? valuesFromRow(FIELDS, row as unknown as Record<string, unknown>) : {}) }))
  const [rule, setRule] = useState<DueRule | null>(row?.due_rule ?? null); const [month, setMonth] = useState(String(row?.period_start_month ?? 1))
  const [errors, setErrors] = useState<Record<string, string>>({}); const [busy, setBusy] = useState(false)
  const { notify } = useToast(); const qc = useQueryClient()
  const frequency = String(values.frequency)
  const needsMonth = ['quarterly', 'half_yearly', 'annual'].includes(frequency)
  const set = (k: string, v: string | boolean) => { setValues((s) => ({ ...s, [k]: v })); if (k === 'frequency') setRule(null) }
  async function submit(e: React.FormEvent) {
    e.preventDefault()
    const errs = validate(FIELDS, values, mode); const dueErr = validateDueRule(rule, frequency); if (dueErr) errs.due_rule = dueErr
    setErrors(errs); if (Object.keys(errs).length || !supabase) return
    setBusy(true)
    try {
      const payload = { ...toPayload(FIELDS, values, mode), due_rule: rule, period_start_month: needsMonth ? Number(month) : 1 }
      const res = mode === 'create'
        ? await supabase.from('compliance_rule_version').insert({ ...payload, compliance_id: complianceId }).select().single()
        : await supabase.from('compliance_rule_version').update(payload).eq('id', row!.id).eq('row_version', row!.row_version).select().maybeSingle()
      if (res.error) return notify(describeError(res.error), 'crit'); if (!res.data) return notify(CONFLICT_MESSAGE, 'crit')
      notify(mode === 'create' ? 'Draft version created' : 'Draft saved', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); onDone()
    } finally { setBusy(false) }
  }
  return (
    <form className="space-y-4" onSubmit={(e) => void submit(e)} noValidate>
      <EntityForm fields={FIELDS} values={values} errors={errors} mode={mode} onChange={set} />
      {needsMonth && <Field label="Year starts in">{(f) => <Select {...f} options={MONTHS} value={month} onChange={(e) => setMonth(e.target.value)} />}</Field>}
      <DueRuleEditor frequency={frequency} value={rule} onChange={setRule} error={errors.due_rule} />
      <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button type="submit" loading={busy}>{mode === 'create' ? 'Create draft' : 'Save draft'}</Button></div>
    </form>
  )
}

type EvRow = { document_type_id: string; is_mandatory: boolean; document_type: { name: string; code: string } | null }
function EvidenceTab({ row, canEdit }: { row: RuleVersionRow; canEdit: boolean }) {
  const qc = useQueryClient(); const { notify } = useToast(); const [add, setAdd] = useState('')
  const q = useQuery({ queryKey: ['rule-evidence', row.id], enabled: !!supabase, queryFn: async (): Promise<EvRow[]> => {
    const { data, error } = await supabase!.from('compliance_rule_evidence').select('document_type_id,is_mandatory,document_type(name,code)').eq('rule_version_id', row.id); if (error) throw error
    return (data ?? []) as unknown as EvRow[] } })
  const docs = useLookup({ table: 'document_type', value: 'id', label: 'name', filter: { is_active: true } })
  const mut = useMutation({ mutationFn: async (fn: () => PromiseLike<{ error: unknown }>) => { const { error } = await fn(); if (error) throw error },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['rule-evidence', row.id] }); void qc.invalidateQueries({ queryKey: ['page'] }); setAdd('') }, onError: (e) => notify(describeError(e), 'crit') })
  if (q.isLoading) return <Skeleton rows={2} />; if (q.error) return <ErrorState message={(q.error as Error).message} />
  const used = new Set((q.data ?? []).map((r) => r.document_type_id))
  return (
    <div className="space-y-3">
      {!row.evidence_required && <p className="text-sm text-muted">This version does not require evidence. Tick “Evidence required” on the draft to enforce these documents.</p>}
      {(q.data ?? []).length === 0 ? <EmptyState title="No documents configured" description={row.status === 'draft' ? 'Add the documents that must support each obligation.' : undefined} /> : (
        <ul className="space-y-2 text-sm">{q.data!.map((r) => (
          <li key={r.document_type_id} className="flex items-center justify-between gap-2 rounded border border-line p-2">
            <span>{r.document_type?.name ?? r.document_type_id} <Badge tone={r.is_mandatory ? 'crit' : 'neutral'}>{r.is_mandatory ? 'Mandatory' : 'Optional'}</Badge></span>
            {canEdit && <span className="flex gap-2">
              <Button variant="secondary" onClick={() => mut.mutate(() => supabase!.from('compliance_rule_evidence').update({ is_mandatory: !r.is_mandatory }).eq('rule_version_id', row.id).eq('document_type_id', r.document_type_id))}>{r.is_mandatory ? 'Make optional' : 'Make mandatory'}</Button>
              <Button variant="ghost" onClick={() => mut.mutate(() => supabase!.from('compliance_rule_evidence').delete().eq('rule_version_id', row.id).eq('document_type_id', r.document_type_id))}>Remove</Button></span>}
          </li>))}</ul>)}
      {canEdit && <div className="flex items-end gap-2"><div className="flex-1"><Field label="Add document type">{(f) => <Select {...f} value={add} placeholder="Select…" options={(docs.data ?? []).filter((o) => !used.has(o.value))} onChange={(e) => setAdd(e.target.value)} />}</Field></div>
        <Button disabled={!add} onClick={() => mut.mutate(() => supabase!.from('compliance_rule_evidence').insert({ rule_version_id: row.id, document_type_id: add, is_mandatory: true }))}>Add</Button></div>}
      {row.status !== 'draft' && <p className="text-xs text-muted">Evidence requirements of a published version are immutable. Create a new version to change them.</p>}
    </div>
  )
}

function ActivateDialog({ row, open, onClose, onDone }: { row: RuleVersionRow; open: boolean; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState(''); const { notify } = useToast(); const qc = useQueryClient()
  const m = useMutation({ mutationFn: async () => { const { error } = await supabase!.rpc('compliance_activate_rule_version', { p_version_id: row.id, p_reason: reason.trim() }); if (error) throw error },
    onSuccess: () => { notify('Version activated. Future untouched obligations were moved to the new rule; actioned ones stay on their original rule.', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); setReason(''); onDone() }, onError: (e) => notify(describeError(e), 'crit') })
  return (
    <Dialog open={open} onClose={onClose} title={`Activate v${row.version} of ${row.compliance_code}`} footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!reason.trim()} loading={m.isPending} onClick={() => m.mutate()}>Activate version</Button></>}>
      <div className="space-y-3 text-sm">
        <p>Effective from <strong>{row.effective_from}</strong>. The current version (if any) is retired the day before. Obligations that are completed, in progress or otherwise actioned keep their original rule; future untouched system-generated obligations from that date move to this rule. Every change is audited.</p>
        <Field label="Change reason" required help="Recorded in the audit history">{(f) => <Textarea {...f} rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />}</Field>
      </div>
    </Dialog>
  )
}

function NewVersionDialog({ row, open, onClose, onDone }: { row: RuleVersionRow; open: boolean; onClose: () => void; onDone: () => void }) {
  const [from, setFrom] = useState(''); const { notify } = useToast(); const qc = useQueryClient()
  const m = useMutation({ mutationFn: async () => { const { error } = await supabase!.rpc('compliance_rule_new_draft', { p_compliance: row.compliance_id, p_effective_from: from || null }); if (error) throw error },
    onSuccess: () => { notify('Draft created from the latest version', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); onDone() }, onError: (e) => notify(describeError(e), 'crit') })
  return (
    <Dialog open={open} onClose={onClose} title={`New version of ${row.compliance_code}`} footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={m.isPending} onClick={() => m.mutate()}>Create draft</Button></>}>
      <div className="space-y-3 text-sm"><p>An effective rule is never edited. This copies the latest version (including its documents) into a new draft you can change, then activate.</p>
        <Field label="Effective from" help="Leave blank for the day after the current version started (or today, if later)">{(f) => <DatePicker {...f} value={from} onChange={(e) => setFrom(e.target.value)} />}</Field></div>
    </Dialog>
  )
}

function Detail({ row, canManage, close }: { row: RuleVersionRow; canManage: boolean; close: () => void }) {
  const [editing, setEditing] = useState(false); const [activate, setActivate] = useState(false); const [discard, setDiscard] = useState(false); const [nv, setNv] = useState(false)
  const { notify } = useToast(); const qc = useQueryClient()
  async function doDiscard() { setDiscard(false); const { error } = await supabase!.rpc('compliance_rule_discard_draft', { p_version: row.id }); if (error) return notify(describeError(error), 'crit'); notify('Draft discarded', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); close() }
  const facts: Array<[string, React.ReactNode]> = [['Compliance', `${row.compliance_code} · ${row.compliance_name}`], ['Type', titleCase(row.compliance_type)], ['Frequency', titleCase(row.frequency)],
    ['Due', describeDueRule(row.due_rule)], ['Risk / criticality', `${titleCase(row.risk_level)} / ${titleCase(row.criticality)}`], ['Effective', `${row.effective_from} → ${row.effective_to ?? 'open-ended'}`],
    ['Evidence', row.evidence_required ? `Required (${row.evidence_count} document type${row.evidence_count === 1 ? '' : 's'})` : 'Not required'], ['Reminder / escalation', `${row.alert_rule_code ?? 'default'} / ${row.escalation_rule_code ?? 'default'}`],
    ['Obligations created', row.obligation_count], ['Change reason', row.change_reason ?? '—']]
  return (
    <>
      <Tabs tabs={[
        { id: 'summary', label: 'Summary', content: editing ? <RuleVersionForm mode="edit" row={row} onDone={() => { setEditing(false); close() }} /> : (
          <div className="space-y-4">
            <p className={`rounded border p-2 text-sm ${row.status === 'active' ? 'border-status-ok' : 'border-line'}`}><Badge tone={STATUS_TONE[row.status]}>{titleCase(row.status)}</Badge> v{row.version} — {STATUS_HELP[row.status]}</p>
            <dl className="grid grid-cols-3 gap-x-3 gap-y-2 text-sm">{facts.map(([k, v]) => <div key={k} className="contents"><dt className="text-muted">{k}</dt><dd className="col-span-2 break-words">{v}</dd></div>)}</dl>
            <Link className="text-sm text-blue hover:underline" to={`/compliance?q=${encodeURIComponent(row.compliance_code)}`}>View obligations →</Link>
            {canManage && <div className="flex flex-wrap gap-2">
              {row.status === 'draft' ? <><Button onClick={() => setEditing(true)}>Edit draft</Button><Button onClick={() => setActivate(true)}>Activate…</Button><Button variant="danger" onClick={() => setDiscard(true)}>Discard draft</Button></>
                : <Button onClick={() => setNv(true)}>Create new version from this</Button>}</div>}
          </div>) },
        { id: 'evidence', label: 'Evidence', content: <EvidenceTab row={row} canEdit={canManage && row.status === 'draft'} /> },
        { id: 'history', label: 'History', content: <AuditTab table="compliance_rule_version" id={row.id} /> },
      ]} />
      <ActivateDialog row={row} open={activate} onClose={() => setActivate(false)} onDone={() => { setActivate(false); close() }} />
      <NewVersionDialog row={row} open={nv} onClose={() => setNv(false)} onDone={() => { setNv(false); close() }} />
      <ConfirmDialog open={discard} title="Discard draft" message="The draft and its document requirements are deleted. Published versions are never affected." confirmLabel="Discard" danger onConfirm={() => void doDiscard()} onCancel={() => setDiscard(false)} />
    </>
  )
}

const cols: ColumnDef<RuleVersionRow, unknown>[] = [
  { accessorKey: 'compliance_code', header: 'Compliance', cell: (c) => <span><span className="font-medium">{c.getValue<string>()}</span> <span className="text-muted">{c.row.original.compliance_name}</span></span> },
  { accessorKey: 'version', header: 'Version', cell: (c) => `v${c.getValue<number>()}` },
  { accessorKey: 'status', header: 'State', cell: (c) => <Badge tone={STATUS_TONE[c.getValue<string>()] ?? 'neutral'}>{titleCase(c.getValue<string>())}</Badge> },
  { accessorKey: 'frequency', header: 'Frequency', cell: (c) => titleCase(c.getValue<string>()) },
  { accessorKey: 'risk_level', header: 'Risk', cell: (c) => titleCase(c.getValue<string>()) },
  { accessorKey: 'effective_from', header: 'Effective', cell: (c) => `${c.getValue<string>()} → ${c.row.original.effective_to ?? 'open'}` },
  { accessorKey: 'obligation_count', header: 'Obligations' },
]

function NewRuleDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [comp, setComp] = useState(''); const [first, setFirst] = useState(false); const { notify } = useToast(); const qc = useQueryClient()
  const list = useLookup({ table: 'compliance_master', value: 'id', label: 'code', filter: { is_active: true } })
  async function go() {
    const { count } = await supabase!.from('compliance_rule_version').select('id', { count: 'exact', head: true }).eq('compliance_id', comp)
    if ((count ?? 0) === 0) { setFirst(true); return }
    const { error } = await supabase!.rpc('compliance_rule_new_draft', { p_compliance: comp, p_effective_from: null })
    if (error) return notify(describeError(error), 'crit'); notify('Draft created from the latest version', 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); onClose()
  }
  return (<>
    <Dialog open={open && !first} onClose={onClose} title="New rule version" footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!comp} onClick={() => void go()}>Continue</Button></>}>
      <Field label="Compliance" required help="An existing rule is never edited: this copies the latest version into a draft, or starts the first version.">{(f) => <Select {...f} value={comp} placeholder="Select…" options={list.data ?? []} onChange={(e) => setComp(e.target.value)} />}</Field>
    </Dialog>
    <Dialog open={open && first} onClose={() => { setFirst(false); onClose() }} title="First rule version">{first && <RuleVersionForm mode="create" complianceId={comp} onDone={() => { setFirst(false); onClose() }} />}</Dialog>
  </>)
}

export function RuleVersionsPage() {
  const { access } = useAuth(); const canManage = can(access, 'compliance.manage'); const [open, setOpen] = useState(false)
  const [params] = useSearchParams(); void params
  return (<>
    <Register<RuleVersionRow> id="rule-versions" title="Rule Versions" table="v_compliance_rule_version" select={RV_SELECT} columns={cols} getRowId={(r) => r.id}
      searchColumns={['compliance_code', 'compliance_name']} defaultSort={{ id: 'compliance_code', desc: false }} extraKeys={['compliance_code']} searchPlaceholder="Search compliance…"
      filterDefs={[{ key: 'status', label: 'State', options: [{ value: 'draft', label: 'Draft' }, { value: 'active', label: 'Active' }, { value: 'retired', label: 'Retired' }] }, { key: 'frequency', label: 'Frequency', options: FREQUENCIES }, { key: 'risk_level', label: 'Risk', lov: 'RISK' }]}
      quickViewTitle={(r) => `${r.compliance_code} · v${r.version}`} renderQuickView={(r, close) => <Detail row={r} canManage={canManage} close={close} />}
      actions={canManage ? <Button onClick={() => setOpen(true)}>New rule version</Button> : undefined} />
    <NewRuleDialog open={open} onClose={() => setOpen(false)} />
  </>)
}
