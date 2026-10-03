import type { Tone } from '../components/ui'

export const dueStateBadge: Record<string, { label: string; tone: Tone }> = {
  completed: { label: 'Completed', tone: 'ok' }, due_soon: { label: 'Due soon', tone: 'warn' }, overdue: { label: 'Overdue', tone: 'crit' },
  upcoming: { label: 'Upcoming', tone: 'info' }, not_applicable: { label: 'Not applicable', tone: 'neutral' },
}
export const expiryBadge = (cat: string): { label: string; tone: Tone } => {
  if (cat === 'expired') return { label: 'Expired', tone: 'crit' }
  if (cat.startsWith('within_')) { const n = Number(cat.slice(7)); return { label: `Expires ≤ ${n}d`, tone: n <= 15 ? 'crit' : 'warn' } }
  if (cat === 'valid') return { label: 'Valid', tone: 'ok' }
  if (cat === 'no_expiry') return { label: 'No expiry', tone: 'neutral' }
  return { label: cat.replace(/_/g, ' '), tone: 'neutral' }
}
export const severityTone = (s: string): Tone => (s === 'critical' || s === 'high' ? 'crit' : s === 'medium' ? 'warn' : s === 'low' ? 'ok' : 'neutral')
export const evidenceBadge: Record<string, { label: string; tone: Tone }> = {
  verified: { label: 'Verified', tone: 'ok' }, pending_review: { label: 'Pending review', tone: 'info' }, rejected: { label: 'Rejected', tone: 'crit' },
  missing: { label: 'Missing', tone: 'crit' }, expired: { label: 'Expired', tone: 'warn' },
}
export const titleCase = (s: string) => s.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase())
