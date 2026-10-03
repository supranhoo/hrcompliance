/** Catalogue of the runtime settings the admin screen edits (system_config). Each entry mirrors the database guard (app.system_config_guard):
 *  the UI validates the same rules for instant feedback; the database is the authority. Unknown / integration keys are never editable here. */
export type SettingKind = 'days' | 'int_list' | 'severity_days' | 'count'
export type SettingDef = { key: string; label: string; section: string; kind: SettingKind; min?: number; max?: number; help: string }
export const SETTINGS: SettingDef[] = [
  { key: 'compliance.due_soon_days', label: 'Due-soon window (days)', section: 'Compliance', kind: 'days', min: 0, max: 365, help: 'An open obligation is “due soon” when it falls due within this many days.' },
  { key: 'compliance.generation_horizon_days', label: 'Generation horizon (days)', section: 'Compliance', kind: 'days', min: 1, max: 400, help: 'How far ahead the nightly generator creates obligations.' },
  { key: 'compliance.generation_lookback_days', label: 'Generation look-back (days)', section: 'Compliance', kind: 'days', min: 0, max: 400, help: '0 = current period only; use a larger value to back-fill after downtime.' },
  { key: 'licence.expiry_thresholds', label: 'Licence expiry thresholds (days)', section: 'Licences', kind: 'int_list', help: 'Descending days-to-expiry buckets, e.g. 90, 60, 30, 15, 7. Drives the derived expiry state and filters.' },
  { key: 'exception.target_days', label: 'Resolution target by severity (days)', section: 'Exceptions', kind: 'severity_days', help: 'Days from detection to the resolution target; ageing and “target breached” use it.' },
  { key: 'exception.overdue_grace_days', label: 'Overdue grace (days)', section: 'Exceptions', kind: 'days', min: 0, max: 365, help: 'Days after the due date before an unfinished obligation raises an overdue exception.' },
  { key: 'alert.catchup_days', label: 'Alert catch-up window (days)', section: 'Alerts', kind: 'days', min: 0, max: 30, help: 'An alert offset reached within this many days is still generated (covers a missed run).' },
  { key: 'ui.page_size', label: 'Default page size', section: 'Display', kind: 'count', min: 5, max: 200, help: 'Rows per page in registers.' },
]
export type Parsed = { ok: true; value: unknown } | { ok: false; error: string }
const WHOLE = /^\d{1,4}$/

export function formatSetting(def: SettingDef, value: unknown): string {
  if (def.kind === 'int_list') return Array.isArray(value) ? value.join(', ') : ''
  if (def.kind === 'severity_days') return value && typeof value === 'object' ? JSON.stringify(value) : ''
  return value === null || value === undefined ? '' : String(value)
}
export function parseSetting(def: SettingDef, text: string, severities: string[] = []): Parsed {
  const t = text.trim()
  if (def.kind === 'days' || def.kind === 'count') {
    if (!WHOLE.test(t)) return { ok: false, error: 'Enter a whole number' }
    const n = Number(t); if (def.min !== undefined && n < def.min) return { ok: false, error: `Must be at least ${def.min}` }; if (def.max !== undefined && n > def.max) return { ok: false, error: `Must be at most ${def.max}` }
    return { ok: true, value: n }
  }
  if (def.kind === 'int_list') {
    const parts = t.split(',').map((x) => x.trim()).filter(Boolean)
    if (parts.length === 0) return { ok: false, error: 'Enter at least one number of days' }; if (parts.length > 12) return { ok: false, error: 'At most 12 thresholds' }
    if (!parts.every((p) => WHOLE.test(p) && Number(p) >= 1)) return { ok: false, error: 'Use whole days of 1 or more, separated by commas' }
    const nums = parts.map(Number); for (let i = 1; i < nums.length; i++) if (nums[i] >= nums[i - 1]) return { ok: false, error: 'Thresholds must be strictly descending (largest first)' }
    return { ok: true, value: nums }
  }
  // severity_days: "critical=1, high=3, medium=7, low=14"
  const out: Record<string, number> = {}
  for (const pair of t.split(',').map((x) => x.trim()).filter(Boolean)) {
    const m = /^([A-Za-z0-9_]+)\s*[=:]\s*(\d{1,3})$/.exec(pair); if (!m) return { ok: false, error: 'Use the form critical=1, high=3, medium=7, low=14' }
    if (Number(m[2]) < 1) return { ok: false, error: `${m[1]}: at least 1 day` }; out[m[1]] = Number(m[2])
  }
  for (const s of severities) if (!(s in out)) return { ok: false, error: `Add a target for “${s}”` }
  return { ok: true, value: out }
}
export const formatSla = (v: unknown, order: string[]): string => (v && typeof v === 'object' ? order.filter((k) => k in (v as object)).map((k) => `${k}=${(v as Record<string, number>)[k]}`).join(', ') : '')
