import type { ReactNode } from 'react'
import { cx } from './cx'

export type Tone = 'ok' | 'warn' | 'crit' | 'info' | 'neutral'
const tones: Record<Tone, string> = {
  ok: 'bg-status-ok/10 text-status-ok', warn: 'bg-status-warn/10 text-status-warn',
  crit: 'bg-status-crit/10 text-status-crit', info: 'bg-status-info/10 text-status-info', neutral: 'bg-canvas text-muted',
}
/** Colour is never the only signal: the label always carries the meaning. */
export function Badge({ tone = 'neutral', children }: { tone?: Tone; children: ReactNode }) {
  return <span className={cx('inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium', tones[tone])}>{children}</span>
}
const statusTone: Record<string, Tone> = { green: 'ok', amber: 'warn', red: 'crit', blue: 'info', grey: 'neutral' }
/** `color` comes from status_definition.color (configurable), not hardcoded per status. */
export function StatusBadge({ label, color }: { label: string; color?: string | null }) {
  return <Badge tone={statusTone[color ?? 'grey'] ?? 'neutral'}>{label}</Badge>
}
const riskTone: Record<string, Tone> = { low: 'ok', medium: 'warn', high: 'crit', critical: 'crit' }
export function RiskBadge({ level }: { level: string }) {
  return <Badge tone={riskTone[level.toLowerCase()] ?? 'neutral'}>{level}</Badge>
}

export function KpiCard({ label, value, tone = 'neutral', hint, onClick }: { label: string; value: ReactNode; tone?: Tone; hint?: string; onClick?: () => void }) {
  const body = (<>
    <div className="text-xs uppercase tracking-wide text-muted">{label}</div>
    <div className={cx('mt-1 text-2xl font-semibold', tone === 'crit' ? 'text-status-crit' : tone === 'warn' ? 'text-status-warn' : tone === 'ok' ? 'text-status-ok' : 'text-navy')}>{value}</div>
    {hint && <div className="mt-1 text-xs text-muted">{hint}</div>}
  </>)
  const cls = 'block w-full rounded-lg border border-line bg-white p-4 text-left'
  return onClick ? <button type="button" onClick={onClick} className={cx(cls, 'hover:border-blue')}>{body}</button> : <div className={cls}>{body}</div>
}

export function Skeleton({ className, rows = 1 }: { className?: string; rows?: number }) {
  return <div role="status" aria-label="Loading" className="space-y-2">{Array.from({ length: rows }, (_, i) => <div key={i} className={cx('h-4 animate-pulse rounded bg-line', className)} />)}</div>
}

export function EmptyState({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return <div className="rounded-lg border border-dashed border-line bg-white p-10 text-center"><h2 className="text-sm font-semibold text-ink">{title}</h2>{description && <p className="mt-1 text-sm text-muted">{description}</p>}{action && <div className="mt-4">{action}</div>}</div>
}
export function ErrorState({ title = 'Something went wrong', message, onRetry }: { title?: string; message?: string; onRetry?: () => void }) {
  return (
    <div role="alert" className="rounded-lg border border-status-crit/40 bg-white p-6">
      <h2 className="text-sm font-semibold text-status-crit">{title}</h2>
      {message && <p className="mt-1 text-sm text-muted">{message}</p>}
      {onRetry && <button type="button" onClick={onRetry} className="mt-3 rounded border border-line px-3 py-1 text-sm hover:bg-canvas">Retry</button>}
    </div>
  )
}

export type TimelineItem = { id: string; at: string; title: string; description?: string; actor?: string; tone?: Tone }
export function Timeline({ items, empty = 'No activity yet.' }: { items: TimelineItem[]; empty?: string }) {
  if (items.length === 0) return <p className="text-sm text-muted">{empty}</p>
  return (
    <ol className="space-y-4 border-l border-line pl-4">
      {items.map((i) => (
        <li key={i.id} className="relative">
          <span aria-hidden className={cx('absolute -left-[21px] top-1.5 size-2.5 rounded-full', i.tone === 'crit' ? 'bg-status-crit' : i.tone === 'warn' ? 'bg-status-warn' : i.tone === 'ok' ? 'bg-status-ok' : 'bg-blue')} />
          <div className="text-sm font-medium text-ink">{i.title}</div>
          {i.description && <div className="text-sm text-muted">{i.description}</div>}
          <div className="text-xs text-muted"><time dateTime={i.at}>{new Date(i.at).toLocaleString()}</time>{i.actor && ` · ${i.actor}`}</div>
        </li>
      ))}
    </ol>
  )
}

export type AuditEntry = { id: number | string; at: string; action: string; actor?: string | null; changed_fields?: string[] | null; reason?: string | null; old_data?: Record<string, unknown> | null; new_data?: Record<string, unknown> | null }
/** Field-level change history built from audit_log rows. */
export function AuditHistory({ entries }: { entries: AuditEntry[] }) {
  return (
    <Timeline empty="No audit history." items={entries.map((e) => ({
      id: String(e.id), at: e.at, actor: e.actor ?? 'system', tone: e.action === 'DELETE' ? 'crit' : 'info',
      title: e.action === 'UPDATE' ? `Updated ${(e.changed_fields ?? []).join(', ')}` : e.action === 'INSERT' ? 'Created' : 'Deleted',
      description: [e.reason && `Reason: ${e.reason}`, ...(e.action === 'UPDATE' ? (e.changed_fields ?? []).map((f) => `${f}: ${String(e.old_data?.[f] ?? '∅')} → ${String(e.new_data?.[f] ?? '∅')}`) : [])].filter(Boolean).join(' · ') || undefined,
    }))} />
  )
}

/** Placeholder until a DocumentStorageService adapter is configured; shows the real adapter state. */
export function EvidencePlaceholder({ storageState }: { storageState: string }) {
  const ready = storageState === 'CONFIGURED'
  return (
    <div className="rounded-lg border border-dashed border-line bg-white p-6 text-sm">
      <div className="font-medium text-ink">Evidence &amp; documents</div>
      <p className="mt-1 text-muted">{ready ? 'Drop files here to attach.' : `Document storage is ${storageState.replace('_', ' ')}. Evidence upload is disabled until it is connected.`}</p>
    </div>
  )
}
