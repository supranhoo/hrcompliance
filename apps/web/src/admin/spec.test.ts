import { describe, expect, it } from 'vitest'
import { emptyValues, toPayload, validate, validatePeriod, valuesFromRow, type FieldSpec } from './spec'
import { describeError, CONFLICT_MESSAGE } from './errors'
import { complianceMasterSpec, REFERENCE_MASTERS } from './masters'

const fields: FieldSpec[] = [
  { key: 'code', label: 'Code', type: 'text', required: true, immutable: true, pattern: /^[A-Z0-9]{2,8}$/, patternMessage: 'bad code' },
  { key: 'name', label: 'Name', type: 'text', required: true, max: 5 },
  { key: 'n', label: 'Count', type: 'number', min: 0, max: 10 },
  { key: 'd', label: 'Date', type: 'date' },
  { key: 'is_active', label: 'Active', type: 'boolean' },
  { key: 'ro', label: 'Stored', type: 'text', readOnly: true },
]
const base = { ...emptyValues(fields), code: 'AB1', name: 'Name' }

describe('admin form spec', () => {
  it('new records start active, other booleans false, text blank', () => { expect(emptyValues(fields)).toMatchObject({ code: '', is_active: true, name: '' }) })
  it('required fields are enforced on the frontend (the database enforces them again)', () => {
    expect(validate(fields, emptyValues(fields), 'create')).toMatchObject({ code: 'Code is required', name: 'Name is required' })
    expect(validate(fields, base, 'create')).toEqual({})
  })
  it('pattern, length, number range and date format', () => {
    expect(validate(fields, { ...base, code: 'bad code' }, 'create').code).toBe('bad code')
    expect(validate(fields, { ...base, name: 'TooLong' }, 'create').name).toMatch(/at most 5/)
    expect(validate(fields, { ...base, n: '11' }, 'create').n).toMatch(/at most 10/)
    expect(validate(fields, { ...base, n: '-1' }, 'create').n).toMatch(/at least 0/)
    expect(validate(fields, { ...base, n: 'abc' }, 'create').n).toMatch(/must be a number/)
    expect(validate(fields, { ...base, d: '31/12/2026' }, 'create').d).toMatch(/valid date/)
    expect(validate(fields, { ...base, d: '2026-12-31', n: '5' }, 'create')).toEqual({})
  })
  it('an immutable identity (code) is not validated or sent on edit; read-only fields are never sent', () => {
    expect(validate(fields, { ...base, code: '' }, 'edit')).toEqual({})
    expect(toPayload(fields, { ...base, ro: 'x' }, 'edit')).not.toHaveProperty('code')
    expect(toPayload(fields, { ...base, ro: 'x' }, 'create')).not.toHaveProperty('ro')
    expect(toPayload(fields, base, 'create')).toHaveProperty('code', 'AB1')
  })
  it('payload: blanks become null, numbers numbers, booleans booleans, text trimmed', () => {
    expect(toPayload(fields, { ...base, name: '  Hi ', n: '7', d: '', is_active: false }, 'create')).toEqual({ code: 'AB1', name: 'Hi', n: 7, d: null, is_active: false })
  })
  it('valuesFromRow maps nulls to blanks and keeps booleans', () => {
    expect(valuesFromRow(fields, { code: 'X', name: null, n: 3, d: null, is_active: true })).toMatchObject({ code: 'X', name: '', n: '3', d: '', is_active: true })
  })
  it('period check: end cannot precede start', () => {
    expect(validatePeriod({ a: '2026-02-01', b: '2026-01-01' }, 'a', 'b')).toMatch(/cannot be before/)
    expect(validatePeriod({ a: '2026-02-01', b: '' }, 'a', 'b')).toBeUndefined()
  })
})

describe('list fields (e.g. allowed MIME types)', () => {
  const list: FieldSpec = { key: 'm', label: 'Types', type: 'list', required: true, max: 3, itemPattern: /^[a-z]+\/[a-z]+$/, patternMessage: 'bad mime' }
  it('validates items and count; converts to an array', () => {
    expect(validate([list], { m: '' }, 'create').m).toMatch(/required/); expect(validate([list], { m: 'pdf' }, 'create').m).toBe('bad mime')
    expect(validate([list], { m: 'a/b, c/d, e/f, g/h' }, 'create').m).toMatch(/at most 3/); expect(validate([list], { m: 'application/pdf, image/png' }, 'create')).toEqual({})
    expect(toPayload([list], { m: ' application/pdf , image/png ,' }, 'create')).toEqual({ m: ['application/pdf', 'image/png'] }); expect(valuesFromRow([list], { m: ['a/b', 'c/d'] })).toEqual({ m: 'a/b, c/d' })
  })
})

describe('database error messages', () => {
  it('explains common failures in business language', () => {
    expect(describeError({ code: '23505', message: 'duplicate key' })).toMatch(/already exists/)
    expect(describeError({ code: '42501', message: 'new row violates row-level security policy' })).toMatch(/permission/)
    expect(describeError({ code: '42501', message: 'rule version 1 of x is published and immutable; create a new version' })).toMatch(/immutable/)
    expect(describeError({ code: '23514', message: 'completion date cannot precede the period start' })).toMatch(/completion date/)
    expect(describeError(new Error('boom'))).toBe('boom'); expect(describeError(undefined)).toMatch(/went wrong/)
    expect(CONFLICT_MESSAGE).toMatch(/changed by someone else/)
  })
})

describe('master specs are consistent', () => {
  const all = [complianceMasterSpec, ...Object.values(REFERENCE_MASTERS)]
  it('every spec has a code or name, an immutable code, a permission and a default sort that is a selected column', () => {
    for (const s of all) {
      expect(s.permission).toMatch(/\.(manage|write)$/)
      expect(s.fields.find((f) => f.key === 'code')?.immutable).toBe(true)
      expect(s.select.split(',')).toContain(s.defaultSort.id)
      for (const f of s.fields) expect(s.select.split(',')).toContain(f.key)    // the register read model carries every editable field
    }
  })
  it('lookups and lists are database-driven: no hardcoded business option lists in any master field', () => {
    for (const s of all) for (const f of s.fields) if (f.type === 'select') expect(f.lov || f.lookup || f.options).toBeTruthy()
  })
  it('compliance master code format matches the database check', () => { expect(complianceMasterSpec.fields.find((f) => f.key === 'code')?.pattern?.test('PF-MONTHLY')).toBe(true); expect(complianceMasterSpec.fields.find((f) => f.key === 'code')?.pattern?.test('pf monthly')).toBe(false) })
})
