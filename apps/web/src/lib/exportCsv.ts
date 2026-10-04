import Papa from 'papaparse'
import type { SupabaseClient } from '@supabase/supabase-js'
import { fetchPage, type PageQuery } from './query'

export type ExportColumn = { key: string; header: string }
/** Hard cap for one export; larger sets are truncated and the log says so. */
export const EXPORT_MAX_ROWS = 10_000
const CHUNK = 200                                   // fetchPage caps a page at 200 rows

/**
 * Spreadsheet formula injection: a text cell that starts with = + - @ (or a tab / carriage return) is executed as a formula by Excel and Sheets.
 * Such text is prefixed with an apostrophe so it stays text. Real numbers and booleans are never altered, so negative numbers keep their sign.
 */
export function safeCell(v: unknown): string | number | boolean {
  if (v === null || v === undefined) return ''
  if (typeof v === 'number' || typeof v === 'boolean') return v
  const s = Array.isArray(v) ? v.join('; ') : typeof v === 'object' ? JSON.stringify(v) : String(v)
  return /^[=+\-@\t\r]/.test(s) ? `'${s}` : s
}

/** RFC 4180 CSV with a UTF-8 byte-order mark so Excel opens non-ASCII text correctly. */
export function buildCsv(rows: Array<Record<string, unknown>>, cols: ExportColumn[]): string {
  const data = rows.map((r) => cols.map((c) => safeCell(r[c.key])))
  return '﻿' + Papa.unparse({ fields: cols.map((c) => safeCell(c.header) as string), data }, { newline: '\r\n' })
}

export type ExportResult = { rows: Array<Record<string, unknown>>; total: number; truncated: boolean }
/** Reads every page of the same server query (same RLS, filters, search and sort as the screen) up to the cap. */
export async function fetchAllRows(client: SupabaseClient, table: string, select: string, q: PageQuery, max = EXPORT_MAX_ROWS): Promise<ExportResult> {
  const rows: Array<Record<string, unknown>> = []; let total = 0
  for (let page = 0; rows.length < max; page++) {
    const r = await fetchPage<Record<string, unknown>>(client, table, select, { ...q, page, pageSize: CHUNK })
    total = r.total; rows.push(...r.rows)
    if (r.rows.length < CHUNK || rows.length >= total) break
  }
  const truncated = total > max
  return { rows: rows.slice(0, max), total, truncated }
}

export function exportFileName(register: string, now = new Date()): string {
  return `${register.replace(/[^a-z0-9_-]/gi, '-')}-${now.toISOString().slice(0, 10)}.csv`
}
export function downloadCsv(name: string, csv: string): void {
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); const a = document.createElement('a')
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000)
}
