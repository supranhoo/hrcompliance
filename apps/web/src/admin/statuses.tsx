import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Badge, Button, EmptyState, ErrorState, Select, Skeleton } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { describeError } from './errors'
import { LOV_COLORS } from './lov'
import type { AdminRow, MasterSpec } from './AdminRegister'

export type StatusRow = AdminRow & { module: string; code: string; label: string; category: string; color: string | null; sort_order: number; is_initial: boolean; is_terminal: boolean; is_system: boolean }
/** Structural: mirrors the CHECK on status_definition.category (engines key off it). */
const CATEGORIES = [{ value: 'open', label: 'Open' }, { value: 'in_progress', label: 'In progress' }, { value: 'closed', label: 'Closed' }, { value: 'cancelled', label: 'Cancelled' }]

type TransRow = { id: string; to_status: string; requires_reason: boolean; is_active: boolean; row_version: number }
function Transitions({ module, from }: { module: string; from: string }) {
  const { access } = useAuth(); const canEdit = can(access, 'config.write'); const qc = useQueryClient(); const { notify } = useToast(); const [add, setAdd] = useState('')
  const q = useQuery({ queryKey: ['transitions-admin', module, from], enabled: !!supabase, queryFn: async () => {
    const [t, s] = await Promise.all([
      supabase!.from('status_transition').select('id,to_status,requires_reason,is_active,row_version').eq('module', module).eq('from_status', from).order('to_status'),
      supabase!.from('status_definition').select('code,label').eq('module', module).eq('is_active', true).order('sort_order')])
    if (t.error) throw t.error; if (s.error) throw s.error
    return { rows: (t.data ?? []) as TransRow[], labels: new Map((s.data ?? []).map((r) => [r.code as string, r.label as string])) } } })
  const done = () => { void qc.invalidateQueries({ queryKey: ['transitions-admin', module, from] }); void qc.invalidateQueries({ queryKey: ['transitions'] }) }
  const upd = useMutation({ mutationFn: async (v: { r: TransRow; patch: Partial<TransRow> }) => { const { data, error } = await supabase!.from('status_transition').update(v.patch).eq('id', v.r.id).eq('row_version', v.r.row_version).select().maybeSingle(); if (error) throw error; if (!data) throw new Error('Changed by someone else; reload.') }, onSuccess: done, onError: (e) => notify(describeError(e), 'crit') })
  const ins = useMutation({ mutationFn: async () => { const { error } = await supabase!.from('status_transition').insert({ module, from_status: from, to_status: add, requires_reason: false }); if (error) throw error }, onSuccess: () => { setAdd(''); done() }, onError: (e) => notify(describeError(e), 'crit') })
  if (q.isLoading) return <Skeleton rows={2} />; if (q.error) return <ErrorState message={(q.error as Error).message} />
  const used = new Set(q.data!.rows.map((r) => r.to_status)); used.add(from)
  return (
    <div className="space-y-2">
      <h3 className="text-sm font-semibold">Allowed next statuses from “{q.data!.labels.get(from) ?? from}”</h3>
      {q.data!.rows.length === 0 ? <EmptyState title="No transitions" description="No status change is possible from here." /> : (
        <ul className="space-y-2 text-sm">{q.data!.rows.map((r) => (
          <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 rounded border border-line p-2">
            <span>→ {q.data!.labels.get(r.to_status) ?? r.to_status} {!r.is_active && <Badge tone="neutral">disabled</Badge>}</span>
            {canEdit && <span className="flex gap-2">
              <label className="flex items-center gap-1"><input type="checkbox" checked={r.requires_reason} onChange={(e) => upd.mutate({ r, patch: { requires_reason: e.target.checked } })} /> Reason required</label>
              <Button variant="secondary" onClick={() => upd.mutate({ r, patch: { is_active: !r.is_active } })}>{r.is_active ? 'Disable' : 'Enable'}</Button></span>}
          </li>))}</ul>)}
      {canEdit && <div className="flex items-end gap-2"><div className="flex-1"><Select aria-label="Add next status" value={add} placeholder="Add a next status…" options={[...q.data!.labels].filter(([c]) => !used.has(c)).map(([value, label]) => ({ value, label }))} onChange={(e) => setAdd(e.target.value)} /></div><Button disabled={!add} loading={ins.isPending} onClick={() => ins.mutate()}>Add</Button></div>}
      <p className="text-xs text-muted">Transitions are checked by the database on every status change; a mandatory reason is recorded in the audit history.</p>
    </div>
  )
}

export const statusSpec: MasterSpec<StatusRow> = {
  id: 'statuses', title: 'Statuses & Transitions', singular: 'status', hasActive: true, readTable: 'status_definition', writeTable: 'status_definition', permission: 'config.write',
  select: 'id,module,code,label,category,color,sort_order,is_initial,is_terminal,is_system,is_active,row_version', searchColumns: ['code', 'label', 'module'], defaultSort: { id: 'module', desc: false },
  filterDefs: [{ key: 'module', label: 'Module', lookup: { table: 'module_definition', value: 'code', label: 'name' } }],
  titleOf: (r) => `${r.module} · ${r.label}`, canToggle: (r) => !r.is_system,
  columns: [{ accessorKey: 'module', header: 'Module' }, { accessorKey: 'label', header: 'Status' }, { accessorKey: 'code', header: 'Code' }, { accessorKey: 'category', header: 'Meaning' },
    { accessorKey: 'is_system', header: 'Kind', cell: (c) => <Badge tone="neutral">{c.getValue<boolean>() ? 'System' : 'Custom'}</Badge> }, { accessorKey: 'is_active', header: 'Active', cell: (c) => (c.getValue<boolean>() ? 'Yes' : 'No') }],
  fields: [
    { key: 'module', label: 'Module', type: 'select', required: true, immutable: true, lookup: { table: 'module_definition', value: 'code', label: 'name' } },
    { key: 'code', label: 'Code', type: 'text', required: true, immutable: true, pattern: /^[a-z][a-z0-9_]*$/, patternMessage: 'Lower-case letters, digits and underscore', max: 40 },
    { key: 'label', label: 'Label', type: 'text', required: true, max: 80 },
    { key: 'category', label: 'Meaning', type: 'select', required: true, immutable: true, options: CATEGORIES, help: 'Engines treat open / in progress / closed / cancelled differently' },
    { key: 'color', label: 'Colour', type: 'select', options: LOV_COLORS }, { key: 'sort_order', label: 'Order', type: 'number', min: 0, max: 1000 },
    { key: 'is_terminal', label: 'Final status (no further changes)', type: 'boolean', readOnly: false }, { key: 'is_active', label: 'Active', type: 'boolean' },
  ],
  defaults: { sort_order: '50' },
  extraDetail: (r) => <Transitions module={r.module} from={r.code} />,
}
