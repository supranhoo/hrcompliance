/** Alert-rule helpers. The shape is the one app.alert_rule_guard accepts: {applies, offsets[], channels[], recipients[], critical?, when?}. Data only: no code, no SQL. */
export type Applies = 'compliance' | 'licence'
export type Channel = 'in_app' | 'email'
export const CHANNELS: Array<{ value: Channel; label: string }> = [{ value: 'in_app', label: 'In-app' }, { value: 'email', label: 'Email (when Gmail is connected)' }]
export const RECIPIENT_RE = /^(owner|role:[A-Z][A-Z0-9_]{1,40}|user:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/
export const RULE_CODE_RE = /^[A-Z][A-Z0-9_]{2,63}$/
export type RuleDefinition = { applies?: Applies; offsets: number[]; channels: Channel[]; recipients: string[]; critical?: boolean } & Record<string, unknown>

export function parseOffsets(text: string): { ok: true; value: number[] } | { ok: false; error: string } {
  const parts = text.split(',').map((x) => x.trim()).filter(Boolean)
  if (parts.length === 0) return { ok: false, error: 'Enter at least one offset, e.g. -7, -3, 0, 1' }
  if (parts.length > 20) return { ok: false, error: 'At most 20 offsets' }
  const nums: number[] = []
  for (const p of parts) { if (!/^-?\d{1,3}$/.test(p)) return { ok: false, error: `“${p}” is not a whole number of days` }; const n = Number(p); if (Math.abs(n) > 365) return { ok: false, error: 'Offsets must be between -365 and 365 days' }; nums.push(n) }
  return { ok: true, value: [...new Set(nums)].sort((a, b) => a - b) }
}
export const offsetLabel = (n: number) => (n < 0 ? `T-${-n}` : n === 0 ? 'T0' : `D+${n}`)
export const formatOffsets = (o: number[]) => o.join(', ')

export function validateRule(f: { code: string; name: string; offsets: string; channels: Channel[]; recipients: string[]; reason: string; isNew: boolean; effectiveFrom?: string }): Record<string, string> {
  const e: Record<string, string> = {}
  if (f.isNew && !RULE_CODE_RE.test(f.code)) e.code = 'Capital letters, digits and underscore, starting with a letter (3–64 characters)'
  if (!f.name.trim()) e.name = 'Name is required'
  const o = parseOffsets(f.offsets); if (!o.ok) e.offsets = o.error
  if (f.channels.length === 0) e.channels = 'Choose at least one channel'
  if (f.recipients.length === 0) e.recipients = 'Add at least one recipient'
  else if (f.recipients.some((r) => !RECIPIENT_RE.test(r))) e.recipients = 'A recipient is malformed'
  if (!f.reason.trim()) e.reason = 'A change reason is required'
  if (f.effectiveFrom && !/^\d{4}-\d{2}-\d{2}$/.test(f.effectiveFrom)) e.effectiveFrom = 'Enter a valid date'
  return e
}
/** Builds the stored definition; unknown keys of the previous version (e.g. "when") are carried over untouched. */
export function buildDefinition(f: { applies: Applies; offsets: number[]; channels: Channel[]; recipients: string[]; critical: boolean }, previous?: Record<string, unknown>): RuleDefinition {
  const { applies: _a, offsets: _o, channels: _c, recipients: _r, critical: _k, ...rest } = (previous ?? {}) as Record<string, unknown>; void _a; void _o; void _c; void _r; void _k
  return { ...rest, applies: f.applies, offsets: f.offsets, channels: f.channels, recipients: f.recipients, ...(f.critical ? { critical: true } : {}) }
}
export function describeRecipient(t: string, roleNames: Record<string, string> = {}, userNames: Record<string, string> = {}): string {
  if (t === 'owner') return 'Obligation / licence owner'
  if (t.startsWith('role:')) return `Role: ${roleNames[t.slice(5)] ?? t.slice(5)}`
  if (t.startsWith('user:')) return `User: ${userNames[t.slice(5)] ?? t.slice(5)}`
  return t
}
export const ESCALATION_CODE = 'UNROUTABLE_ESCALATION'
/** Recipients used instead of the owner when an obligation has no active owner. Roles/users only (never 'owner'). */
export const FALLBACK_CODE = 'OWNER_FALLBACK'
/** Rules whose recipient list names who to use when there is no owner, so 'owner' makes no sense in them. */
export const NO_OWNER_CODES: readonly string[] = [ESCALATION_CODE, FALLBACK_CODE]
