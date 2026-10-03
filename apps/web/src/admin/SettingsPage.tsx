import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button, ErrorState, Field, Input, Skeleton } from '../components/ui'
import { useAuth } from '../app/AuthProvider'
import { useToast } from '../app/Toasts'
import { can } from '../lib/access'
import { supabase } from '../lib/supabase'
import { useLovOptions } from '../hooks/useLookups'
import { describeError, CONFLICT_MESSAGE } from './errors'
import { formatSetting, formatSla, parseSetting, SETTINGS, type SettingDef } from './settings'

type Row = { key: string; value: unknown; description: string | null; row_version: number }

function SettingEditor({ def, row, severities, canEdit, onSaved }: { def: SettingDef; row: Row; severities: string[]; canEdit: boolean; onSaved: () => void }) {
  const initial = def.kind === 'severity_days' ? formatSla(row.value, severities) : formatSetting(def, row.value)
  const [text, setText] = useState(initial); const [error, setError] = useState(''); const { notify } = useToast()
  const save = useMutation({
    mutationFn: async () => {
      const p = parseSetting(def, text, severities); if (!p.ok) { setError(p.error); throw new Error(p.error) }; setError('')
      const { data, error: e } = await supabase!.from('system_config').update({ value: p.value }).eq('key', def.key).eq('row_version', row.row_version).select().maybeSingle()
      if (e) throw e; if (!data) throw new Error(CONFLICT_MESSAGE)
    },
    onSuccess: () => { notify(`${def.label} saved`, 'ok'); onSaved() }, onError: (e) => { if (!error) setError(describeError(e)) },
  })
  const dirty = text.trim() !== initial.trim()
  return (
    <form className="grid gap-2 rounded border border-line bg-white p-3 sm:grid-cols-[1fr_auto]" onSubmit={(e) => { e.preventDefault(); save.mutate() }}>
      <Field label={def.label} help={def.help} error={error || undefined}>{(f) => <Input {...f} value={text} disabled={!canEdit} onChange={(e) => { setText(e.target.value); setError('') }} />}</Field>
      {canEdit && <div className="self-end"><Button type="submit" disabled={!dirty} loading={save.isPending}>Save</Button></div>}
    </form>
  )
}

/** Runtime settings stored in system_config - the only place thresholds, windows and SLAs live. Validated here and again by the database. */
export function SettingsPage() {
  const { access } = useAuth(); const canEdit = can(access, 'config.write'); const qc = useQueryClient()
  const sev = useLovOptions('SEVERITY'); const severities = (sev.data ?? []).map((o) => o.value)
  const q = useQuery({ queryKey: ['settings-admin'], enabled: !!supabase, queryFn: async (): Promise<Row[]> => {
    const { data, error } = await supabase!.from('system_config').select('key,value,description,row_version').in('key', SETTINGS.map((s) => s.key)); if (error) throw error; return (data ?? []) as Row[] } })
  if (q.isLoading || sev.isLoading) return <Skeleton rows={6} />; if (q.error) return <ErrorState message={(q.error as Error).message} onRetry={() => void q.refetch()} />
  const rows = new Map((q.data ?? []).map((r) => [r.key, r])); const sections = [...new Set(SETTINGS.map((s) => s.section))]
  return (
    <section className="space-y-6">
      <div><h1 className="text-xl font-semibold text-navy">Settings</h1><p className="text-sm text-muted">Thresholds, windows and service levels. Changes apply from the next engine run and are recorded in the audit history. Defaults shown at installation are development values, not BFCL policy.</p></div>
      {sections.map((sec) => (
        <div key={sec} className="space-y-2"><h2 className="text-sm font-semibold uppercase tracking-wide text-muted">{sec}</h2>
          {SETTINGS.filter((s) => s.section === sec).map((def) => rows.has(def.key)
            ? <SettingEditor key={def.key + rows.get(def.key)!.row_version} def={def} row={rows.get(def.key)!} severities={severities} canEdit={canEdit} onSaved={() => { void qc.invalidateQueries({ queryKey: ['settings-admin'] }) }} />
            : <p key={def.key} className="rounded border border-line bg-white p-3 text-sm text-muted">{def.label}: not present in this environment.</p>)}
        </div>))}
    </section>
  )
}
