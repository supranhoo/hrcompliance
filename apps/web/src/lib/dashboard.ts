import { z } from 'zod'

const counts = z.record(z.string(), z.number())
/** Mirrors public.compliance_dashboard() (migration 0021). Parsing rejects malformed payloads instead of rendering guesses. */
export const dashboardSchema = z.object({
  generated_at: z.string(),
  has_data: z.boolean(),
  obligations: z.object({
    total: z.number(), completed: z.number(), open: z.number(), overdue: z.number(), due_soon: z.number(), upcoming_30_days: z.number(),
    completed_late: z.number(), due_so_far: z.number(), compliance_pct: z.number().nullable(), on_time_pct: z.number().nullable(), overdue_by_risk: counts,
  }),
  exceptions: z.object({ open: z.number(), critical_open: z.number(), target_breached: z.number(), by_severity: counts, by_age: counts, by_category: counts }),
  evidence: z.object({ missing: z.number(), pending_review: z.number(), rejected: z.number(), expired: z.number() }),
  licences: z.object({ active: z.number(), expired: z.number(), renewal_window_open: z.number(), by_category: counts }),
  by_location: z.array(z.object({ location_code: z.string(), overdue: z.number(), due_soon: z.number(), open: z.number() })),
  next_due: z.array(z.object({ instance_no: z.string(), compliance_code: z.string(), compliance_name: z.string(), location_code: z.string(), due_date: z.string(), risk_level: z.string(), due_state: z.string() })),
  definitions: z.record(z.string(), z.string()),
})
export type Dashboard = z.infer<typeof dashboardSchema>
export const fmtPct = (v: number | null) => (v === null ? '—' : `${v}%`)   // never show 0% when nothing is measurable

/** Where each tile drills to. Kept in one place so tests can pin the contract. */
export const drill = {
  overdue: '/compliance?due_state=overdue',
  dueSoon: '/compliance?due_state=due_soon',
  next30: '/compliance?due_within=30',
  open: '/compliance?status=open',
  completed: '/compliance?status=completed',
  criticalExceptions: '/exceptions?severity=critical&status=open',
  openExceptions: '/exceptions?status=open',
  breached: '/exceptions?target_breached=true',
  licenceExpired: '/licences?expiry_category=expired',
  renewalWindow: '/licences?renewal_window_open=true',
  evidenceMissing: '/evidence?evidence_state=missing',
  evidenceRejected: '/evidence?evidence_state=rejected',
  evidenceExpired: '/evidence?evidence_state=expired',
  evidencePending: '/evidence?evidence_state=pending_review',
  location: (code: string) => `/compliance?location_code=${encodeURIComponent(code)}`,
  exceptionAge: (bucket: string) => `/exceptions?status=open&age_bucket=${encodeURIComponent(bucket)}`,
  exceptionSeverity: (sev: string) => `/exceptions?status=open&severity=${encodeURIComponent(sev)}`,
  licenceBucket: (cat: string) => `/licences?expiry_category=${encodeURIComponent(cat)}`,
} as const
