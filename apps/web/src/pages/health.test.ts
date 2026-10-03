import { expect, it } from 'vitest'
import { healthSchema, integrationTone } from './SystemHealthPage'

const sample = { database: { connected: true, server_time: '2026-10-03T00:00:00Z', postgres_major: 17 }, schema_version: null, integrations: { google_drive: 'NOT_CONFIGURED', gmail: 'NOT_CONFIGURED' }, latest_job: null, latest_failed_job: null, jobs_failed_24h: 0 }
it('parses the system_health RPC payload', () => { expect(healthSchema.parse(sample).database.connected).toBe(true) })
it('rejects a malformed payload instead of rendering garbage', () => { expect(() => healthSchema.parse({ ...sample, jobs_failed_24h: 'x' })).toThrow() })
it('maps integration state to tone', () => { expect(integrationTone('CONFIGURED')).toBe('ok'); expect(integrationTone('ERROR')).toBe('crit'); expect(integrationTone('NOT_CONFIGURED')).toBe('warn') })
