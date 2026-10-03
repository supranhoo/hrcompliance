import { z } from 'zod'

/** Row shape of public.notification as the Notification Centre reads it (RLS: a user sees only their own rows). */
export const notificationSchema = z.object({
  id: z.string(),
  category: z.enum(['compliance_reminder', 'compliance_escalation', 'licence_expiry', 'alert_unroutable']),
  title: z.string(),
  body: z.string().nullable(),
  link_kind: z.enum(['compliance_instance', 'licence', 'exception']),
  link_id: z.string(),
  created_at: z.string(),
  read_at: z.string().nullable(),
})
export type AppNotification = z.infer<typeof notificationSchema>
export const NOTIFICATION_COLUMNS = 'id,category,title,body,link_kind,link_id,created_at,read_at'

export const categoryLabel: Record<AppNotification['category'], string> = {
  compliance_reminder: 'Reminder', compliance_escalation: 'Escalation', licence_expiry: 'Licence expiry', alert_unroutable: 'Unrouted alert',
}
export const categoryTone = (c: AppNotification['category']): 'warn' | 'crit' | 'neutral' =>
  c === 'alert_unroutable' || c === 'compliance_escalation' ? 'crit' : c === 'licence_expiry' ? 'warn' : 'neutral'
/** Where the notification's record lives. Registers are server-filtered by URL, so only whitelisted keys are used. */
export const linkFor = (n: Pick<AppNotification, 'link_kind' | 'body'>): string =>
  n.link_kind === 'licence' ? '/licences' : n.link_kind === 'exception' ? '/exceptions' : '/compliance'
export const unreadLabel = (n: number) => (n <= 0 ? 'Notifications' : `Notifications (${n > 99 ? '99+' : n} unread)`)

export const unroutableRowSchema = z.object({ id: z.string(), exception_no: z.string(), description: z.string(), severity: z.string(), detected_at: z.string() })
export type UnroutableRow = z.infer<typeof unroutableRowSchema>
