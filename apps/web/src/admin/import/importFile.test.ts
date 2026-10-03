import { describe, expect, it } from 'vitest'
import { applyMapping, autoMap, errorsCsv, parseCsv, quickCheck, sha256Hex, templateCsv, templateGuide, toCsv, unmappedRequired, type TemplateColumn } from './importFile'

const cols: TemplateColumn[] = [
  { key: 'code', label: 'Code', type: 'text', required: true, max: 10, pattern: '^[A-Z0-9-]+$', pattern_message: 'must be capital letters or digits' },
  { key: 'name', label: 'Name', type: 'text', required: true }, { key: 'days', label: 'Renewal lead (days)', type: 'int', min: 0, max: 730 },
  { key: 'valid_from', label: 'Valid from', type: 'date' }, { key: 'active', label: 'Active', type: 'boolean' }, { key: 'law_code', label: 'Law code', type: 'ref' },
]
describe('import file helpers', () => {
  it('sha256 of the file bytes is the idempotency key', async () => { expect(await sha256Hex(new TextEncoder().encode('abc'))).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') })
  it('parses CSV with BOM, quotes, embedded commas/newlines and blank lines', () => {
    const t = parseCsv('\uFEFFCode,Name\r\n"A,1","Line1\nLine2"\r\n\r\nB2,"He said ""hi"""\r\n')
    expect(t.headers).toEqual(['Code', 'Name']); expect(t.rows).toEqual([['A,1', 'Line1\nLine2'], ['B2', 'He said "hi"']])
    expect(parseCsv('')).toEqual({ headers: [], rows: [] })
  })
  it('maps columns automatically by key or friendly label, ignoring case and punctuation', () => {
    const m = autoMap(['code', 'NAME', 'Renewal lead (days)', 'law_code', 'Extra'], cols)
    expect(m).toEqual({ code: 0, name: 1, days: 2, valid_from: null, active: null, law_code: 3 })
    expect(unmappedRequired(cols, { ...m, name: null }).map((c) => c.key)).toEqual(['name'])
  })
  it('applies the mapping, ignoring unmapped columns and short rows', () => {
    expect(applyMapping([['A1', 'Alpha', '30', 'x'], ['B2']], cols, { code: 0, name: 1, days: 2, valid_from: null, active: null, law_code: null })).toEqual([{ code: 'A1', name: 'Alpha', days: '30' }, { code: 'B2', name: '', days: '' }])
  })
  it('quick check mirrors the server parsing rules', () => {
    expect(quickCheck({ code: 'A1', name: 'Alpha', days: '30', valid_from: '2026-02-28', active: 'yes' }, cols)).toEqual([])
    const e = quickCheck({ code: 'a 1', name: '', days: '1.5', valid_from: '2026-02-30', active: 'maybe' }, cols).map((x) => x.column)
    expect(e).toEqual(['code', 'name', 'days', 'valid_from', 'active'])
    expect(quickCheck({ code: 'A1', name: 'x', days: '900' }, cols)[0].message).toMatch(/at most 730/); expect(quickCheck({ code: 'A'.repeat(11), name: 'x' }, cols)[0].message).toMatch(/at most 10/)
  })
  it('template CSV is the header of friendly labels; the guide explains each column', () => {
    expect(templateCsv(cols)).toBe('Code,Name,Renewal lead (days),Valid from,Active,Law code\r\n')
    expect(templateGuide(cols).find((g) => g.column === 'Law code')).toMatchObject({ type: 'code of an existing record', required: false }); expect(templateGuide(cols)[0].required).toBe(true)
    expect(autoMap(parseCsv(templateCsv(cols)).headers, cols).code).toBe(0)       // a downloaded template maps itself
  })
  it('row-error CSV carries the problem and the original values so it can be corrected and re-uploaded', () => {
    const csv = errorsCsv([{ row_no: 3, status: 'error', errors: [{ column: 'code', message: 'Code is required' }], warnings: [{ column: null, message: 'already exists: this row will be skipped' }], raw: { name: 'Alpha, Inc' } }], cols)
    expect(csv.split('\r\n')[0]).toBe('Row,Status,Column,Problem,Code,Name,Renewal lead (days),Valid from,Active,Law code')
    expect(csv).toContain('3,Error,code,Code is required,,"Alpha, Inc"'); expect(csv).toContain('3,Warning,,already exists: this row will be skipped')
    expect(toCsv([['a"b', 'c\nd']])).toBe('"a""b","c\nd"\r\n')
  })
})
