import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { Register } from '../components/table/Register'
import { Badge, Button, Dialog, EmptyState, ErrorState, Field, Input, Select, Skeleton, Tabs, Textarea, DatePicker, type Tone } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { AuditTab } from '../pages/quickviews'
import { describeError } from './errors'
import { useLookup } from './lookups'
import { buildDefinition, CHANNELS, describeRecipient, ESCALATION_CODE, formatOffsets, offsetLabel, parseOffsets, validateRule, type Applies, type Channel } from './alertRule'

export type AlertRuleRow = { id: string; code: string; name: string; version: number; status: string; applies: Applies; offsets: number[]; channels: Channel[]; recipients: string[]; critical: boolean; definition: Record<string, unknown>; effective_from: string | null; effective_to: string | null; change_reason: string | null; row_version: number; is_latest: boolean }
const SELECT = 'id,code,name,version,status,applies,offsets,channels,recipients,critical,definition,effective_from,effective_to,change_reason,row_version,is_latest'
const TONE: Record<string, Tone> = { active: 'ok', retired: 'neutral', draft: 'warn' }

function RecipientPicker({ value, onChange, error, allowOwner = true }: { value: string[]; onChange: (v: string[]) => void; error?: string; allowOwner?: boolean }) {
  const roles = useLookup({ table: 'role', value: 'code', label: 'name' }); const users = useLookup({ table: 'app_user', value: 'id', label: 'email', filter: { status: 'active' } })
  const [role, setRole] = useState(''); const [user, setUser] = useState(''); const rn = Object.fromEntries((roles.data ?? []).map((o) => [o.value, o.label])); const un = Object.fromEntries((users.data ?? []).map((o) => [o.value, o.label]))
  const add = (t: string) => { if (!value.includes(t)) onChange([...value, t]) }
  return (
    <fieldset className="space-y-2 rounded border border-line p-3" aria-describedby={error ? 'rec-err' : undefined}>
      <legend className="px-1 text-sm font-medium">Recipients</legend>
      <ul className="flex flex-wrap gap-2">{value.map((t) => <li key={t} className="flex items-center gap-1 rounded-full bg-blue/10 px-2 py-1 text-xs">{describeRecipient(t, rn, un)}<button type="button" aria-label={`Remove ${t}`} onClick={() => onChange(value.filter((x) => x !== t))}>✕</button></li>)}</ul>
      <div className="grid gap-2 sm:grid-cols-3">
        {allowOwner ? <Button variant="secondary" disabled={value.includes('owner')} onClick={() => add('owner')}>Add owner</Button> : <p className="self-center text-xs text-muted">Name roles or users: there is no owner for an unroutable alert.</p>}
        <div className="flex gap-1"><Select aria-label="Role" value={role} placeholder="Role…" options={roles.data ?? []} onChange={(e) => setRole(e.target.value)} /><Button variant="secondary" disabled={!role} onClick={() => { add(`role:${role}`); setRole('') }}>Add</Button></div>
        <div className="flex gap-1"><Select aria-label="User" value={user} placeholder="User…" options={users.data ?? []} onChange={(e) => setUser(e.target.value)} /><Button variant="secondary" disabled={!user} onClick={() => { add(`user:${user}`); setUser('') }}>Add</Button></div>
      </div>
      {error && <p id="rec-err" role="alert" className="text-xs text-status-crit">{error}</p>}
    </fieldset>
  )
}

/** Creates the next version of a rule (or the first version of a new code). The database activates it and retires the previous one; every version is kept. */
export function AlertRuleForm({ previous, code: fixedCode, onDone }: { previous?: AlertRuleRow; code?: string; onDone: () => void }) {
  const { notify } = useToast(); const qc = useQueryClient(); const isNew = !previous
  const [code, setCode] = useState(previous?.code ?? fixedCode ?? ''); const [name, setName] = useState(previous?.name ?? (fixedCode === ESCALATION_CODE ? 'Unroutable alert escalation' : ''))
  const [applies, setApplies] = useState<Applies>(previous?.applies ?? 'compliance'); const [offsets, setOffsets] = useState(previous ? formatOffsets(previous.offsets) : fixedCode === ESCALATION_CODE ? '0' : '-7, -3, 0, 1')
  const [channels, setChannels] = useState<Channel[]>(previous?.channels ?? ['in_app']); const [recipients, setRecipients] = useState<string[]>(previous?.recipients ?? [])
  const [critical, setCritical] = useState(previous?.critical ?? fixedCode === ESCALATION_CODE); const [from, setFrom] = useState(''); const [reason, setReason] = useState('')
  const [errors, setErrors] = useState<Record<string, string>>({}); const [busy, setBusy] = useState(false)
  async function submit(e: React.FormEvent) {
    e.preventDefault(); const errs = validateRule({ code, name, offsets, channels, recipients, reason, isNew, effectiveFrom: from }); setErrors(errs); if (Object.keys(errs).length || !supabase) return
    const o = parseOffsets(offsets); if (!o.ok) return
    setBusy(true)
    try {
      const def = buildDefinition({ applies, offsets: o.value, channels, recipients, critical }, previous?.definition)
      const { error } = await supabase.rpc('config_new_version', { p_kind: 'alert_rule', p_code: code, p_name: name.trim(), p_definition: def, p_reason: reason.trim(), p_effective_from: from || null })
      if (error) return notify(describeError(error), 'crit')
      notify(`${code} v${(previous?.version ?? 0) + 1} is now active`, 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); void qc.invalidateQueries({ queryKey: ['alert-admin'] }); void qc.invalidateQueries({ queryKey: ['system-health'] }); onDone()
    } finally { setBusy(false) }
  }
  return (
    <form className="space-y-3" onSubmit={(e) => void submit(e)} noValidate>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Rule code" required error={errors.code} help={isNew ? undefined : 'A code never changes; new versions are added'}>{(f) => <Input {...f} value={code} disabled={!isNew || !!fixedCode} onChange={(e) => setCode(e.target.value.toUpperCase())} />}</Field>
        <Field label="Name" required error={errors.name}>{(f) => <Input {...f} value={name} onChange={(e) => setName(e.target.value)} />}</Field>
        <Field label="Applies to">{(f) => <Select {...f} value={applies} options={[{ value: 'compliance', label: 'Compliance obligations' }, { value: 'licence', label: 'Licences' }]} onChange={(e) => setApplies(e.target.value as Applies)} />}</Field>
        <Field label="Offsets (days)" required error={errors.offsets} help="Negative = before the due/expiry date, 0 = on the day, positive = after. e.g. -7, -3, 0, 1">{(f) => <Input {...f} value={offsets} onChange={(e) => setOffsets(e.target.value)} />}</Field>
      </div>
      <fieldset className="space-y-1"><legend className="text-sm font-medium">Channels</legend>{CHANNELS.map((c) => <label key={c.value} className="mr-4 inline-flex items-center gap-2 text-sm"><input type="checkbox" checked={channels.includes(c.value)} onChange={(e) => setChannels(e.target.checked ? [...channels, c.value] : channels.filter((x) => x !== c.value))} />{c.label}</label>)}{errors.channels && <p role="alert" className="text-xs text-status-crit">{errors.channels}</p>}</fieldset>
      <RecipientPicker value={recipients} onChange={setRecipients} error={errors.recipients} allowOwner={(previous?.code ?? fixedCode ?? code) !== ESCALATION_CODE} />
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={critical} onChange={(e) => setCritical(e.target.checked)} /> Critical rule — routing problems block production activation</label>
      <div className="grid gap-3 sm:grid-cols-2"><Field label="Effective from" error={errors.effectiveFrom} help="Blank = today">{(f) => <DatePicker {...f} value={from} onChange={(e) => setFrom(e.target.value)} />}</Field></div>
      <Field label="Change reason" required error={errors.reason} help="Recorded in the audit history">{(f) => <Textarea {...f} rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />}</Field>
      <p className="text-xs text-muted">Saving creates a new version and activates it immediately; the previous version is retired, never overwritten. “Owner” falls back to Head HR in scope when an item has no active owner.</p>
      <div className="flex justify-end gap-2"><Button variant="secondary" onClick={onDone}>Cancel</Button><Button type="submit" loading={busy}>{isNew ? 'Create rule' : 'Save as new version'}</Button></div>
    </form>
  )
}

function Detail({ row, canEdit, close }: { row: AlertRuleRow; canEdit: boolean; close: () => void }) {
  const [edit, setEdit] = useState(false)
  const hist = useQuery({ queryKey: ['alert-admin', 'history', row.code], enabled: !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('v_alert_rule').select('version,status,offsets,recipients,change_reason,effective_from').eq('code', row.code).order('version', { ascending: false }); if (error) throw error; return (data ?? []) as Array<Pick<AlertRuleRow, 'version' | 'status' | 'offsets' | 'recipients' | 'change_reason' | 'effective_from'>> } })
  return (
    <Tabs tabs={[
      { id: 'rule', label: 'Rule', content: edit ? <AlertRuleForm previous={row} onDone={() => { setEdit(false); close() }} /> : (
        <div className="space-y-3 text-sm">
          <div className="flex items-center gap-2"><Badge tone={TONE[row.status] ?? 'neutral'}>{row.status}</Badge> v{row.version} {row.critical && <Badge tone="crit">Critical</Badge>}</div>
          <dl className="grid grid-cols-3 gap-x-3 gap-y-2"><dt className="text-muted">Applies to</dt><dd className="col-span-2">{row.applies}</dd><dt className="text-muted">Timing</dt><dd className="col-span-2">{row.offsets.map(offsetLabel).join(' · ')}</dd>
            <dt className="text-muted">Channels</dt><dd className="col-span-2">{row.channels.join(', ')}</dd><dt className="text-muted">Recipients</dt><dd className="col-span-2">{row.recipients.map((r) => describeRecipient(r)).join('; ')}</dd><dt className="text-muted">Reason</dt><dd className="col-span-2">{row.change_reason ?? '—'}</dd></dl>
          {canEdit && row.is_latest && row.status === 'active' ? <Button onClick={() => setEdit(true)}>Create new version…</Button> : <p className="text-xs text-muted">{row.status === 'retired' ? 'Earlier versions are history.' : ''}</p>}
        </div>) },
      { id: 'history', label: 'Versions', content: hist.isLoading ? <Skeleton rows={2} /> : hist.error ? <ErrorState message={(hist.error as Error).message} /> : (
        <ul className="space-y-2 text-sm">{(hist.data ?? []).map((h) => <li key={h.version} className="rounded border border-line p-2"><strong>v{h.version}</strong> <Badge tone={TONE[h.status] ?? 'neutral'}>{h.status}</Badge> {h.offsets.map(offsetLabel).join(' · ')} → {h.recipients.join(', ')}<div className="text-xs text-muted">{h.change_reason ?? ''}</div></li>)}</ul>) },
      { id: 'audit', label: 'History', content: <AuditTab table="config_definition" id={row.id} /> },
    ]} />
  )
}

type Issue = { rule_code: string; severity: string; problem: string }
function RoutingPanel({ canEdit, onConfigure }: { canEdit: boolean; onConfigure: () => void }) {
  const issues = useQuery({ queryKey: ['alert-admin', 'issues'], enabled: !!supabase, queryFn: async (): Promise<Issue[]> => { const { data, error } = await supabase!.from('v_alert_routing_issue').select('rule_code,severity,problem'); if (error) throw error; return (data ?? []) as Issue[] } })
  const esc = useQuery({ queryKey: ['alert-admin', 'escalation'], enabled: !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('v_alert_rule').select('recipients,version').eq('code', ESCALATION_CODE).eq('status', 'active').maybeSingle(); if (error) throw error; return data as { recipients: string[]; version: number } | null } })
  const health = useQuery({ queryKey: ['system-health'], enabled: !!supabase, retry: false, queryFn: async () => { const { data, error } = await supabase!.rpc('system_health'); if (error) throw error; return data as { environment?: string; unroutable_alerts?: number } } })
  const errors = (issues.data ?? []).filter((i) => i.severity === 'error').length
  return (
    <section aria-label="Alert routing" className="space-y-3 rounded-lg border border-line bg-white p-4">
      <div className="flex flex-wrap items-center justify-between gap-2"><h2 className="text-base font-semibold">Routing & escalation</h2>
        <div className="flex gap-2 text-sm"><Link className="text-blue hover:underline" to="/admin/system-health">System Health</Link><Link className="text-blue hover:underline" to="/notifications">Notification Centre</Link></div></div>
      <p className="text-sm text-muted">When an alert rule resolves to nobody, the alert goes to the <strong>escalation recipients</strong> below so it is never lost{health.data?.environment === 'development' ? ' (development: Super Admin is also used as a fallback — never in production)' : ''}. If nobody can be told, an <strong>alert_unroutable</strong> exception is raised and shown in System Health.</p>
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <Badge tone={esc.data ? 'ok' : 'crit'}>{esc.data ? `Escalation configured (v${esc.data.version})` : 'No escalation recipients configured'}</Badge>
        {esc.data && <span>{esc.data.recipients.map((r) => describeRecipient(r)).join('; ')}</span>}
        <Badge tone={errors ? 'crit' : 'ok'}>{errors ? `${errors} routing error(s)` : 'Routing valid'}</Badge>
        {typeof health.data?.unroutable_alerts === 'number' && <Badge tone={health.data.unroutable_alerts ? 'crit' : 'ok'}>{health.data.unroutable_alerts} unroutable alert(s)</Badge>}
        {canEdit && <Button onClick={onConfigure}>{esc.data ? 'Change escalation recipients' : 'Configure escalation recipients'}</Button>}
      </div>
      {(issues.data ?? []).length > 0 && <ul className="space-y-1 text-sm" aria-label="Routing issues">{issues.data!.map((i, k) => <li key={k} className={i.severity === 'error' ? 'text-status-crit' : 'text-status-warn'}><strong>{i.rule_code}</strong>: {i.problem}</li>)}</ul>}
    </section>
  )
}

const cols: ColumnDef<AlertRuleRow, unknown>[] = [
  { accessorKey: 'code', header: 'Rule', cell: (c) => <span><span className="font-medium">{c.getValue<string>()}</span> <span className="text-muted">v{c.row.original.version}</span></span> },
  { accessorKey: 'name', header: 'Name' }, { accessorKey: 'applies', header: 'Applies to' },
  { accessorKey: 'offsets', header: 'Timing', cell: (c) => (c.getValue<number[]>() ?? []).map(offsetLabel).join(' · ') },
  { accessorKey: 'recipients', header: 'Recipients', cell: (c) => (c.getValue<string[]>() ?? []).map((r) => describeRecipient(r)).join('; ') },
  { accessorKey: 'status', header: 'State', cell: (c) => <Badge tone={TONE[c.getValue<string>()] ?? 'neutral'}>{c.getValue<string>()}</Badge> },
]
export function AlertRulesPage() {
  const { access } = useAuth(); const canEdit = can(access, 'config.write'); const [form, setForm] = useState<{ code?: string } | null>(null)
  return (<div className="space-y-4">
    <RoutingPanel canEdit={canEdit} onConfigure={() => setForm({ code: ESCALATION_CODE })} />
    <Register<AlertRuleRow> id="alert-rules" title="Alert Rules" table="v_alert_rule" select={SELECT} columns={cols} getRowId={(r) => r.id} searchColumns={['code', 'name']} defaultSort={{ id: 'code', desc: false }} searchPlaceholder="Search alert rules…"
      filterDefs={[{ key: 'status', label: 'State', options: [{ value: 'active', label: 'Active' }, { value: 'retired', label: 'Retired (history)' }] }, { key: 'applies', label: 'Applies to', options: [{ value: 'compliance', label: 'Compliance' }, { value: 'licence', label: 'Licence' }] }]}
      quickViewTitle={(r) => `${r.code} · v${r.version}`} renderQuickView={(r, close) => <Detail row={r} canEdit={canEdit} close={close} />}
      actions={canEdit ? <Button onClick={() => setForm({})}>New alert rule</Button> : undefined} />
    <Dialog open={!!form} onClose={() => setForm(null)} title={form?.code === ESCALATION_CODE ? 'Escalation recipients for unroutable alerts' : 'New alert rule'}>
      {form && <EscalationOrNew code={form.code} onDone={() => setForm(null)} />}
    </Dialog>
    {!canEdit && <EmptyState title="Read-only" description="Changing alert rules needs the configuration permission." />}
  </div>)
}
function EscalationOrNew({ code, onDone }: { code?: string; onDone: () => void }) {
  const cur = useQuery({ queryKey: ['alert-admin', 'current', code], enabled: !!code && !!supabase, queryFn: async () => { const { data, error } = await supabase!.from('v_alert_rule').select(SELECT).eq('code', code!).eq('status', 'active').maybeSingle(); if (error) throw error; return data as AlertRuleRow | null } })
  if (code && cur.isLoading) return <Skeleton rows={4} />
  return <AlertRuleForm code={code} previous={cur.data ?? undefined} onDone={onDone} />
}
