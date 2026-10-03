import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useToast } from '../app/Toasts'
import { CONFLICT_MESSAGE, describeError } from './errors'
import { toPayload, validate, type FieldSpec, type Mode, type Values } from './spec'

/** Create/update through PostgREST: RLS, triggers, constraints and audit apply exactly as for every other path.
 *  Updates are guarded by row_version (optimistic locking). Returns the saved row, or null after showing the error. */
export function useSave(table: string, fields: FieldSpec[], opts: { extra?: (v: Values, mode: Mode) => string | undefined; invalidate?: string[][] } = {}) {
  const qc = useQueryClient(); const { notify } = useToast()
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  async function save(values: Values, mode: Mode, current?: { id: string; row_version: number }, extraPayload: Record<string, unknown> = {}): Promise<Record<string, unknown> | null> {
    const e = validate(fields, values, mode); const x = opts.extra?.(values, mode)
    if (x) e._form = x
    setErrors(e); if (Object.keys(e).length) return null
    if (!supabase) { notify('Supabase is not configured', 'crit'); return null }
    setBusy(true)
    try {
      const payload = { ...toPayload(fields, values, mode), ...extraPayload }
      const res = mode === 'create'
        ? await supabase.from(table).insert(payload).select().single()
        : await supabase.from(table).update(payload).eq('id', current!.id).eq('row_version', current!.row_version).select().maybeSingle()
      if (res.error) { notify(describeError(res.error), 'crit'); return null }
      if (!res.data) { notify(CONFLICT_MESSAGE, 'crit'); return null }
      notify(mode === 'create' ? 'Created' : 'Saved', 'ok')
      void qc.invalidateQueries({ queryKey: ['page'] }); void qc.invalidateQueries({ queryKey: ['lookup'] }); void qc.invalidateQueries({ queryKey: ['lov'] })
      for (const k of opts.invalidate ?? []) void qc.invalidateQueries({ queryKey: k })
      return res.data as Record<string, unknown>
    } finally { setBusy(false) }
  }
  return { save, errors, setErrors, busy }
}
