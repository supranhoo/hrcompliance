import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useTransitions } from '../hooks/useLookups'
import { useToast } from '../app/Toasts'
import { Button, Field, Select, Textarea } from './ui'

/** Moves a record along the CONFIGURED status transitions. The reason travels with the change (audit log) via an invoker-rights RPC;
 *  the database re-validates the transition, the reason and the user's scope, so this component is convenience, not authority. */
export function StatusActions({ module, current, recordId, rpc, noteIsResolution, onDone }: {
  module: string; current: string; recordId: string; rpc: 'compliance_set_status' | 'exception_set_status'; noteIsResolution?: boolean; onDone?: () => void
}) {
  const transitions = useTransitions(module, current)
  const [to, setTo] = useState(''); const [note, setNote] = useState('')
  const qc = useQueryClient(); const { notify } = useToast()
  const chosen = transitions.data?.find((t) => t.to === to)
  const needsNote = !!chosen && (chosen.requiresReason || (noteIsResolution && ['resolved', 'waived'].includes(chosen.to)))
  const m = useMutation({
    mutationFn: async () => {
      const args = rpc === 'compliance_set_status' ? { p_instance: recordId, p_status: to, p_reason: note || null } : { p_id: recordId, p_status: to, p_note: note || null }
      const { error } = await supabase!.rpc(rpc, args); if (error) throw error
    },
    onSuccess: () => { notify('Status updated', 'ok'); setTo(''); setNote(''); void qc.invalidateQueries({ queryKey: ['page'] }); void qc.invalidateQueries({ queryKey: ['dashboard'] }); void qc.invalidateQueries({ queryKey: ['quick'] }); onDone?.() },
    onError: (e: Error) => notify(e.message, 'crit'),
  })
  if (transitions.isLoading) return <p className="text-sm text-muted">Loading actions…</p>
  if (!transitions.data?.length) return <p className="text-sm text-muted">No further status changes are configured from here.</p>
  return (
    <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); m.mutate() }}>
      <Field label="Change status to">{(f) => <Select {...f} value={to} onChange={(e) => setTo(e.target.value)} placeholder="Select…" options={transitions.data!.map((t) => ({ value: t.to, label: t.label + (t.requiresReason ? ' (reason required)' : '') }))} />}</Field>
      {needsNote && <Field label={noteIsResolution && ['resolved', 'waived'].includes(to) ? 'Resolution / reason' : 'Reason'} required>{(f) => <Textarea {...f} rows={3} value={note} onChange={(e) => setNote(e.target.value)} />}</Field>}
      <Button type="submit" disabled={!to || (needsNote && note.trim().length === 0)} loading={m.isPending}>Apply</Button>
    </form>
  )
}
