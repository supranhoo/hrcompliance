import { describe, expect, it } from 'vitest'
import { buildDefinition, describeRecipient, ESCALATION_CODE, offsetLabel, parseOffsets, RECIPIENT_RE, validateRule } from './alertRule'

describe('alert rule helpers (mirror app.alert_rule_guard)', () => {
  it('offsets: whole days within a year, sorted and de-duplicated', () => {
    expect(parseOffsets('1, -3, -7, 0, -3')).toEqual({ ok: true, value: [-7, -3, 0, 1] })
    expect(parseOffsets('')).toMatchObject({ ok: false }); expect(parseOffsets('1.5')).toMatchObject({ ok: false }); expect(parseOffsets('400')).toMatchObject({ ok: false }); expect(parseOffsets('a')).toMatchObject({ ok: false })
    expect(offsetLabel(-7)).toBe('T-7'); expect(offsetLabel(0)).toBe('T0'); expect(offsetLabel(3)).toBe('D+3')
  })
  it('recipients are limited to owner, role:CODE and user:uuid (no free expressions)', () => {
    for (const ok of ['owner', 'role:HEAD_HR', 'user:59bace57-c19a-4169-901e-e837e871109a']) expect(RECIPIENT_RE.test(ok)).toBe(true)
    for (const bad of ['all', 'role:head hr', 'role:x; drop table y', 'user:123', '*']) expect(RECIPIENT_RE.test(bad)).toBe(false)
  })
  it('validation: code (new), name, offsets, channels, recipients, reason', () => {
    const ok = { code: 'MY_RULE', name: 'My rule', offsets: '-7, 0', channels: ['in_app' as const], recipients: ['owner'], reason: 'initial', isNew: true }
    expect(validateRule(ok)).toEqual({})
    expect(validateRule({ ...ok, code: 'my rule' }).code).toBeDefined(); expect(validateRule({ ...ok, isNew: false, code: 'my rule' }).code).toBeUndefined()
    expect(validateRule({ ...ok, name: ' ' }).name).toBeDefined(); expect(validateRule({ ...ok, offsets: 'x' }).offsets).toBeDefined(); expect(validateRule({ ...ok, channels: [] }).channels).toBeDefined()
    expect(validateRule({ ...ok, recipients: [] }).recipients).toBeDefined(); expect(validateRule({ ...ok, recipients: ['everyone'] }).recipients).toBeDefined(); expect(validateRule({ ...ok, reason: '' }).reason).toBeDefined()
  })
  it('builds the definition and keeps unknown keys of the previous version (e.g. a "when" condition)', () => {
    const prev = { applies: 'compliance', offsets: [1], channels: ['email'], recipients: ['owner'], when: { op: 'eq', field: 'status', value: 'open' }, critical: true }
    expect(buildDefinition({ applies: 'compliance', offsets: [-7, 0], channels: ['in_app'], recipients: ['role:HEAD_HR'], critical: false }, prev)).toEqual({ when: prev.when, applies: 'compliance', offsets: [-7, 0], channels: ['in_app'], recipients: ['role:HEAD_HR'] })
    expect(buildDefinition({ applies: 'licence', offsets: [0], channels: ['in_app'], recipients: ['owner'], critical: true })).toMatchObject({ critical: true })
  })
  it('describes recipients and names the escalation rule code', () => {
    expect(describeRecipient('role:HEAD_HR', { HEAD_HR: 'Head HR' })).toBe('Role: Head HR'); expect(describeRecipient('owner')).toMatch(/owner/i); expect(ESCALATION_CODE).toBe('UNROUTABLE_ESCALATION')
  })
})
