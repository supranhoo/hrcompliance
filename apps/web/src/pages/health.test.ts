import { expect, it } from 'vitest'
import { healthSchema, integrationTone } from './SystemHealthPage'

const sample = { database: { connected: true, server_time: '2026-10-03T00:00:00Z', postgres_major: 17 }, schema_version: null, integrations: { google_drive: 'NOT_CONFIGURED', gmail: 'NOT_CONFIGURED' }, latest_job: null, latest_failed_job: null, jobs_failed_24h: 0 }
it('parses the system_health RPC payload', () => { expect(healthSchema.parse(sample).database.connected).toBe(true) })
it('rejects a malformed payload instead of rendering garbage', () => { expect(() => healthSchema.parse({ ...sample, jobs_failed_24h: 'x' })).toThrow() })
it('maps integration state to tone', () => { expect(integrationTone('CONFIGURED')).toBe('ok'); expect(integrationTone('ERROR')).toBe('crit'); expect(integrationTone('NOT_CONFIGURED')).toBe('warn') })
it('accepts an older payload (before D-001) and defaults the new fields', () => {
  const h = healthSchema.parse(sample); expect(h.unroutable_alerts).toBe(0); expect(h.alert_routing).toEqual({ errors: 0, warnings: 0 }); expect(h.latest_job_warning).toBeNull()
})
it('parses the unroutable / routing fields added by migration 0023', () => {
  const h = healthSchema.parse({ ...sample, unroutable_alerts: 2, unroutable_notifications_7d: 5, alert_routing: { errors: 1, warnings: 3 }, latest_job_warning: { job_code: 'alert_generation', started_at: '2026-10-03T00:00:00Z', message: 'x' }, environment: 'development' })
  expect(h.unroutable_alerts).toBe(2); expect(h.alert_routing.errors).toBe(1); expect(h.latest_job_warning?.job_code).toBe('alert_generation')
})
