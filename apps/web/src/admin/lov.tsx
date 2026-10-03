import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Badge, Button, EmptyState, ErrorState, Input, Select, Skeleton } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { describeError } from './errors'
import { ACTIVE_OPTIONS } from './domain'
import type { AdminRow, MasterSpec } from './AdminRegister'

export const LOV_COLORS = ['green', 'amber', 'red', 'blue', 'grey'].map((v) => ({ value: v, label: v[0].toUpperCase() + v.slice(1) }))
export const LOV_VALUE_CODE = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$/
type ValueRow = { id: string; code: string; label: string; sort_order: number; color: string | null; is_active: boolean; meta: { protected?: boolean } | null; row_version: number }

export function LovValues({ setId, setCode, isSystem }: { setId: string; setCode: string; isSystem: boolean }) {
  const { access } = useAuth(); const canEdit = can(access, 'config.write'); const qc = useQueryClient(); const { notify } = useToast()
  const q = useQuery({ queryKey: ['lov-values-admin', setId], enabled: !!supabase, queryFn: async (): Promise<ValueRow[]> => {
    const { data, error } = await supabase!.from('lov_value').select('id,code,label,sort_order,color,is_active,meta,row_version').eq('set_id', setId).order('sort_order').order('code'); if (error) throw error; return (data ?? []) as ValueRow[] } })
  const [nv, setNv] = useState({ code: '', label: '', sort_order: '', color: '' }); const [err, setErr] = useState('')
  const done = () => { void qc.invalidateQueries({ queryKey: ['lov-values-admin', setId] }); void qc.invalidateQueries({ queryKey: ['lov'] }) }
  const update = useMutation({ mutationFn: async (v: { row: ValueRow; patch: Partial<ValueRow> }) => {
    const { data, error } = await supabase!.from('lov_value').update(v.patch).eq('id', v.row.id).eq('row_version', v.row.row_version).select().maybeSingle(); if (error) throw error
    if (!data) throw new Error('This value was changed by someone else. Reload and try again.') }, onSuccess: done, onError: (e) => notify(describeError(e), 'crit') })
  const add = useMutation({ mutationFn: async () => {
    const code = nv.code.trim(), label = nv.label.trim(); if (!LOV_VALUE_CODE.test(code)) throw new Error('Code: letters, digits, dot, dash or underscore (max 40)'); if (!label) throw new Error('Label is required')
    const order = nv.sort_order.trim() === '' ? ((q.data ?? []).reduce((m, r) => Math.max(m, r.sort_order), 0) + 10) : Number(nv.sort_order); if (!Number.isInteger(order)) throw new Error('Order must be a whole number')
    const { error } = await supabase!.from('lov_value').insert({ set_id: setId, code, label, sort_order: order, color: nv.color || null }); if (error) throw error },
    onSuccess: () => { setNv({ code: '', label: '', sort_order: '', color: '' }); setErr(''); notify('Value added', 'ok'); done() }, onError: (e) => setErr(describeError(e)) })
  if (q.isLoading) return <Skeleton rows={3} />; if (q.error) return <ErrorState message={(q.error as Error).message} />
  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">Values of {setCode}</h3>
      {(q.data ?? []).length === 0 ? <EmptyState title="No values yet" description="Add the first value below." /> : (
        <ul className="space-y-2">{q.data!.map((r) => {
          const prot = r.meta?.protected === true
          return (
            <li key={r.id} className="grid grid-cols-1 gap-2 rounded border border-line p-2 text-sm sm:grid-cols-[1fr_1.4fr_5rem_6rem_auto]">
              <span className="self-center font-mono text-xs">{r.code}{prot && <Badge tone="neutral">system</Badge>}</span>
              <Input aria-label={`Label for ${r.code}`} defaultValue={r.label} disabled={!canEdit} onBlur={(e) => { const v = e.target.value.trim(); if (v && v !== r.label) update.mutate({ row: r, patch: { label: v } }) }} />
              <Input aria-label={`Order for ${r.code}`} inputMode="numeric" defaultValue={String(r.sort_order)} disabled={!canEdit} onBlur={(e) => { const n = Number(e.target.value); if (Number.isInteger(n) && n !== r.sort_order) update.mutate({ row: r, patch: { sort_order: n } }) }} />
              <Select aria-label={`Colour for ${r.code}`} value={r.color ?? ''} placeholder="No colour" options={LOV_COLORS} disabled={!canEdit} onChange={(e) => update.mutate({ row: r, patch: { color: e.target.value || null } })} />
              <Button variant="secondary" disabled={!canEdit || (prot && r.is_active)} title={prot ? 'Used by system logic: cannot be deactivated' : undefined} onClick={() => update.mutate({ row: r, patch: { is_active: !r.is_active } })}>{r.is_active ? 'Deactivate' : 'Activate'}</Button>
            </li>)
        })}</ul>)}
      {canEdit && (
        <form className="grid grid-cols-1 gap-2 rounded border border-dashed border-line p-2 sm:grid-cols-[1fr_1.4fr_5rem_6rem_auto]" onSubmit={(e) => { e.preventDefault(); add.mutate() }}>
          <Input aria-label="New value code" placeholder="CODE" value={nv.code} onChange={(e) => setNv({ ...nv, code: e.target.value })} />
          <Input aria-label="New value label" placeholder="Label" value={nv.label} onChange={(e) => setNv({ ...nv, label: e.target.value })} />
          <Input aria-label="New value order" placeholder="Order" inputMode="numeric" value={nv.sort_order} onChange={(e) => setNv({ ...nv, sort_order: e.target.value })} />
          <Select aria-label="New value colour" value={nv.color} placeholder="No colour" options={LOV_COLORS} onChange={(e) => setNv({ ...nv, color: e.target.value })} />
          <Button type="submit" loading={add.isPending}>Add value</Button>
          {err && <p role="alert" className="text-xs text-status-crit sm:col-span-5">{err}</p>}
        </form>)}
      <p className="text-xs text-muted">Codes never change once created (records refer to them). Values are deactivated, never deleted{isSystem ? '. Values marked “system” are used by platform logic: edit their labels, colour or order only.' : '.'}</p>
    </div>
  )
}

export type LovSetRow = AdminRow & { code: string; name: string; description: string | null; is_system: boolean }
export const lovSetSpec: MasterSpec<LovSetRow> = {
  id: 'lov-sets', title: 'Lists (LOV)', singular: 'list', hasActive: true, readTable: 'lov_set', writeTable: 'lov_set', permission: 'config.write',
  select: 'id,code,name,description,is_system,is_active,row_version', searchColumns: ['code', 'name'], defaultSort: { id: 'code', desc: false }, searchPlaceholder: 'Search lists…',
  filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }, { key: 'is_system', label: 'Kind', options: [{ value: 'true', label: 'System' }, { value: 'false', label: 'Custom' }] }],
  titleOf: (r) => `${r.code} · ${r.name}`, canToggle: (r) => !r.is_system,
  columns: [{ accessorKey: 'code', header: 'Code' }, { accessorKey: 'name', header: 'Name' }, { accessorKey: 'is_system', header: 'Kind', cell: (c) => <Badge tone="neutral">{c.getValue<boolean>() ? 'System' : 'Custom'}</Badge> },
    { accessorKey: 'is_active', header: 'Status', cell: (c) => <Badge tone={c.getValue<boolean>() ? 'ok' : 'neutral'}>{c.getValue<boolean>() ? 'Active' : 'Inactive'}</Badge> }],
  fields: [{ key: 'code', label: 'Code', type: 'text', required: true, immutable: true, pattern: /^[A-Z][A-Z0-9_]*$/, patternMessage: 'Capital letters, digits and underscore, starting with a letter', max: 60 },
    { key: 'name', label: 'Name', type: 'text', required: true, max: 200 }, { key: 'description', label: 'Description', type: 'textarea', max: 500 }, { key: 'is_active', label: 'Active', type: 'boolean' }],
  extraDetail: (r) => <LovValues setId={r.id} setCode={r.code} isSystem={r.is_system} />,
}
