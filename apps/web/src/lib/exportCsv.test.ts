import { describe, expect, it, vi } from 'vitest'
import { buildCsv, exportFileName, fetchAllRows, safeCell } from './exportCsv'

describe('CSV export', () => {
  it('neutralises spreadsheet formulas in text but keeps real numbers', () => {
    expect(safeCell('=SUM(A1)')).toBe("'=SUM(A1)"); expect(safeCell('+91 98')).toBe("'+91 98"); expect(safeCell('-cmd')).toBe("'-cmd"); expect(safeCell('@x')).toBe("'@x"); expect(safeCell('\tx')).toBe("'\tx")
    expect(safeCell(-5)).toBe(-5); expect(safeCell(0)).toBe(0); expect(safeCell(true)).toBe(true); expect(safeCell(null)).toBe(''); expect(safeCell(undefined)).toBe('')
    expect(safeCell(['a', 'b'])).toBe('a; b'); expect(safeCell({ x: 1 })).toBe('{"x":1}'); expect(safeCell('plain')).toBe('plain')
  })
  it('builds RFC 4180 CSV with BOM, quoting commas, quotes and newlines', () => {
    const csv = buildCsv([{ a: 'x,y', b: 'say "hi"', c: 'l1\nl2', d: 3 }, { a: '=1+1', b: null, c: 'ok', d: -2 }], [{ key: 'a', header: 'A' }, { key: 'b', header: 'B' }, { key: 'c', header: 'C' }, { key: 'd', header: 'D' }])
    expect(csv.startsWith('﻿')).toBe(true); const lines = csv.slice(1).split('\r\n')
    expect(lines[0]).toBe('A,B,C,D'); expect(lines[1]).toBe('"x,y","say ""hi""","l1\nl2",3'); expect(lines[2]).toBe("'=1+1,,ok,-2")
  })
  it('the header row is neutralised too', () => { expect(buildCsv([], [{ key: 'a', header: '=bad' }])).toContain("'=bad") })
  it('file names are safe', () => { expect(exportFileName('Compliance Register/../x', new Date('2026-10-04T10:00:00Z'))).toBe('Compliance-Register----x-2026-10-04.csv') })
})

const client = (total: number) => {
  const calls: Array<[number, number]> = []
  const c = { from: () => { const b: Record<string, unknown> = {}; b.select = () => b; b.order = () => b; b.eq = () => b; b.or = () => b; b.range = async (f: number, t: number) => { calls.push([f, t]); const rows = Array.from({ length: Math.max(0, Math.min(t + 1, total) - f) }, (_, i) => ({ id: f + i })); return { data: rows, error: null, count: total } }; return b } }
  return { c: c as never, calls }
}
describe('fetchAllRows', () => {
  it('pages through the whole result with the same query', async () => { const { c, calls } = client(450); const r = await fetchAllRows(c, 'v_x', 'id', { page: 0, pageSize: 25 }); expect(r.rows).toHaveLength(450); expect(r.truncated).toBe(false); expect(calls).toEqual([[0, 199], [200, 399], [400, 599]]) })
  it('truncates at the cap and says so', async () => { const { c } = client(1000); const r = await fetchAllRows(c, 'v_x', 'id', { page: 0, pageSize: 25 }, 300); expect(r.rows).toHaveLength(300); expect(r.truncated).toBe(true); expect(r.total).toBe(1000) })
  it('an empty result is fine', async () => { const { c } = client(0); const r = await fetchAllRows(c, 'v_x', 'id', { page: 0, pageSize: 25 }); expect(r.rows).toEqual([]); expect(r.truncated).toBe(false) })
  it('propagates errors', async () => { const c = { from: () => { const b: Record<string, unknown> = {}; b.select = () => b; b.range = async () => ({ data: null, error: new Error('rls'), count: null }); return b } }; await expect(fetchAllRows(c as never, 'v_x', 'id', { page: 0, pageSize: 25 })).rejects.toThrow('rls') })
})
void vi
