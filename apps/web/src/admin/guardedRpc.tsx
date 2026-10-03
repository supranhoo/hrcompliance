import { useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { ConfirmDialog } from '../components/ui'
import { useToast } from '../app/Toasts'
import { supabase } from '../lib/supabase'
import { describeError, isSelfLockout } from './errors'

/**
 * Calls an administration RPC. If the database says the change would remove the caller's own admin access (AD002) the person must confirm explicitly,
 * and only then is the call repeated with p_confirm_self = true. The database still refuses to remove the last role administrator.
 */
export function useGuardedRpc(invalidate: string[] = []): { run: (fn: string, args: Record<string, unknown>, success: string) => Promise<boolean>; dialog: ReactNode; busy: boolean } {
  const { notify } = useToast(); const qc = useQueryClient(); const [busy, setBusy] = useState(false)
  const [pending, setPending] = useState<{ fn: string; args: Record<string, unknown>; success: string; resolve: (ok: boolean) => void; message: string } | null>(null)
  async function exec(fn: string, args: Record<string, unknown>, success: string): Promise<{ ok: boolean; selfLock?: string }> {
    if (!supabase) return { ok: false }
    const { error } = await supabase.rpc(fn, args)
    if (error) { if (isSelfLockout(error) && !args.p_confirm_self) return { ok: false, selfLock: describeError(error) }; notify(describeError(error), 'crit'); return { ok: false } }
    notify(success, 'ok'); void qc.invalidateQueries({ queryKey: ['page'] }); for (const k of invalidate) void qc.invalidateQueries({ queryKey: [k] }); return { ok: true }
  }
  async function run(fn: string, args: Record<string, unknown>, success: string): Promise<boolean> {
    setBusy(true)
    try {
      const r = await exec(fn, args, success); if (r.ok || !r.selfLock) return r.ok
      return await new Promise<boolean>((resolve) => setPending({ fn, args, success, resolve, message: r.selfLock! }))
    } finally { setBusy(false) }
  }
  const dialog = (
    <ConfirmDialog open={!!pending} danger title="This removes your own administrative access" confirmLabel="Yes, remove my access"
      message={<p>{pending?.message}. You may not be able to reverse this yourself. Another administrator would have to restore it.</p>}
      onCancel={() => { pending?.resolve(false); setPending(null) }}
      onConfirm={() => { const p = pending; setPending(null); if (!p) return; setBusy(true); void exec(p.fn, { ...p.args, p_confirm_self: true }, p.success).then((r) => p.resolve(r.ok)).finally(() => setBusy(false)) }} />
  )
  return { run, dialog, busy }
}
