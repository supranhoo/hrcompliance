import { describe, expect, it } from 'vitest'
import { formatSetting, formatSla, parseSetting, SETTINGS } from './settings'

const def = (key: string) => SETTINGS.find((s) => s.key === key)!
describe('settings catalogue', () => {
  it('whole-day settings are bounded exactly like the database guard', () => {
    expect(parseSetting(def('compliance.due_soon_days'), '7')).toEqual({ ok: true, value: 7 })
    expect(parseSetting(def('compliance.due_soon_days'), '-1')).toMatchObject({ ok: false }); expect(parseSetting(def('compliance.due_soon_days'), '3.5')).toMatchObject({ ok: false }); expect(parseSetting(def('compliance.due_soon_days'), 'x')).toMatchObject({ ok: false })
    expect(parseSetting(def('compliance.generation_horizon_days'), '0')).toMatchObject({ ok: false, error: 'Must be at least 1' }); expect(parseSetting(def('compliance.generation_horizon_days'), '500')).toMatchObject({ ok: false, error: 'Must be at most 400' })
    expect(parseSetting(def('ui.page_size'), '1000')).toMatchObject({ ok: false }); expect(parseSetting(def('ui.page_size'), '50')).toEqual({ ok: true, value: 50 })
  })
  it('thresholds: whole days, descending, bounded count', () => {
    expect(parseSetting(def('licence.expiry_thresholds'), '90, 60, 30, 15, 7')).toEqual({ ok: true, value: [90, 60, 30, 15, 7] })
    expect(parseSetting(def('licence.expiry_thresholds'), '30, 60')).toMatchObject({ ok: false, error: expect.stringMatching(/descending/) })
    expect(parseSetting(def('licence.expiry_thresholds'), '30, 30')).toMatchObject({ ok: false }); expect(parseSetting(def('licence.expiry_thresholds'), '')).toMatchObject({ ok: false })
    expect(parseSetting(def('licence.expiry_thresholds'), '30, 7.5')).toMatchObject({ ok: false }); expect(parseSetting(def('licence.expiry_thresholds'), '30, 0')).toMatchObject({ ok: false })
    expect(parseSetting(def('licence.expiry_thresholds'), Array.from({ length: 13 }, (_, i) => 100 - i).join(','))).toMatchObject({ ok: false })
  })
  it('SLA per severity must cover every configured severity (from the LOV, not hardcoded)', () => {
    const sev = ['critical', 'high', 'medium', 'low']
    expect(parseSetting(def('exception.target_days'), 'critical=1, high=3, medium=7, low=14', sev)).toEqual({ ok: true, value: { critical: 1, high: 3, medium: 7, low: 14 } })
    expect(parseSetting(def('exception.target_days'), 'critical=1, high=3', sev)).toMatchObject({ ok: false, error: expect.stringMatching(/medium/) })
    expect(parseSetting(def('exception.target_days'), 'critical=0, high=3, medium=7, low=14', sev)).toMatchObject({ ok: false })
    expect(parseSetting(def('exception.target_days'), 'critical:1; high=3', sev)).toMatchObject({ ok: false })
    expect(parseSetting(def('exception.target_days'), 'urgent=1, critical=1, high=3, medium=7, low=14', ['urgent', ...sev])).toMatchObject({ ok: true })
  })
  it('formats stored values back to text; integration keys are not editable here', () => {
    expect(formatSetting(def('licence.expiry_thresholds'), [90, 60])).toBe('90, 60'); expect(formatSetting(def('compliance.due_soon_days'), 7)).toBe('7')
    expect(formatSla({ low: 14, critical: 1, high: 3, medium: 7 }, ['critical', 'high', 'medium', 'low'])).toBe('critical=1, high=3, medium=7, low=14')
    expect(SETTINGS.some((s) => s.key.startsWith('integration.'))).toBe(false); expect(new Set(SETTINGS.map((s) => s.key)).size).toBe(SETTINGS.length)
  })
})
