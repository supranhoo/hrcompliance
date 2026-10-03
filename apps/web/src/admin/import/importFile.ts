import Papa from 'papaparse'

/** Column spec as returned by public.import_template_columns() (the database owns the template; the screen renders it). */
export type TemplateColumn = { key: string; label: string; type: 'text' | 'int' | 'number' | 'date' | 'boolean' | 'list' | 'ref'; required?: boolean; max?: number; min?: number; pattern?: string; pattern_message?: string; help?: string; custom?: string }
export type TemplateDef = { code: string; name: string; description: string | null; key_columns: string[]; max_rows: number; columns: TemplateColumn[] }
export type RawTable = { headers: string[]; rows: string[][]; sheet?: string; sheets?: Array<{ name: string }> }
export type Mapping = Record<string, number | null>      // template column key -> index of the file column

export async function sha256Hex(data: ArrayBuffer | Uint8Array): Promise<string> {
  const buf = data instanceof Uint8Array ? data.slice().buffer : data
  const subtle = globalThis.crypto?.subtle
  if (!subtle) throw new Error('This browser cannot compute the file fingerprint (needs a secure https page)')
  const d = await subtle.digest('SHA-256', buf as ArrayBuffer)
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

const clean = (v: unknown): string => {
  if (v === null || v === undefined) return ''
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? '' : `${v.getUTCFullYear()}-${String(v.getUTCMonth() + 1).padStart(2, '0')}-${String(v.getUTCDate()).padStart(2, '0')}`
  return String(v).trim()
}
/** CSV (RFC 4180, quoted commas/newlines, BOM tolerated). The first non-empty row is the header. */
export function parseCsv(text: string): RawTable {
  const res = Papa.parse<string[]>(text.replace(/^\uFEFF/, ''), { skipEmptyLines: 'greedy' })
  const rows = res.data.map((r) => r.map(clean))
  if (rows.length === 0) return { headers: [], rows: [] }
  return { headers: rows[0], rows: rows.slice(1).filter((r) => r.some((c) => c !== '')) }
}
/** Excel (.xlsx): reads one sheet at a time; the library is loaded only when needed. Dates arrive as ISO text. */
export async function parseXlsx(file: Blob, sheet?: string): Promise<RawTable> {
  const read = (await import('read-excel-file/browser')).default
  const all = await read(file)                                         // every sheet, in workbook order
  const sheets = all.map((s) => ({ name: s.sheet }))
  const chosen = all.find((s) => s.sheet === sheet) ?? all[0]
  const rows = (chosen?.data ?? []).map((r) => r.map(clean))
  if (rows.length === 0) return { headers: [], rows: [], sheet: chosen?.sheet, sheets }
  return { headers: rows[0], rows: rows.slice(1).filter((r) => r.some((c) => c !== '')), sheet: chosen.sheet, sheets }
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '')
/** Suggest a mapping by matching file headers to template keys or labels (user can override). */
export function autoMap(headers: string[], columns: TemplateColumn[]): Mapping {
  const idx = new Map<string, number>(); headers.forEach((h, i) => { const n = norm(h); if (n && !idx.has(n)) idx.set(n, i) })
  return Object.fromEntries(columns.map((c) => [c.key, idx.get(norm(c.key)) ?? idx.get(norm(c.label)) ?? null]))
}
export const unmappedRequired = (columns: TemplateColumn[], m: Mapping) => columns.filter((c) => c.required && (m[c.key] === null || m[c.key] === undefined))
export function applyMapping(rows: string[][], columns: TemplateColumn[], m: Mapping): Array<Record<string, string>> {
  return rows.map((r) => Object.fromEntries(columns.filter((c) => m[c.key] !== null && m[c.key] !== undefined).map((c) => [c.key, (r[m[c.key] as number] ?? '').trim()])))
}

/** Early, friendly check that mirrors the server's parsing rules (the server re-validates everything, including the database's own constraints). */
export function quickCheck(row: Record<string, string>, columns: TemplateColumn[]): Array<{ column: string; message: string }> {
  const out: Array<{ column: string; message: string }> = []
  for (const c of columns) {
    const v = (row[c.key] ?? '').trim()
    if (v === '') { if (c.required) out.push({ column: c.key, message: `${c.label} is required` }); continue }
    if (c.type === 'int' && !/^-?\d{1,9}$/.test(v)) out.push({ column: c.key, message: `${c.label} must be a whole number` })
    else if (c.type === 'number' && !/^-?\d{1,15}(\.\d{1,6})?$/.test(v)) out.push({ column: c.key, message: `${c.label} must be a number` })
    else if (c.type === 'date' && !(/^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v)) && new Date(v).toISOString().slice(0, 10) === v)) out.push({ column: c.key, message: `${c.label} must be a date as YYYY-MM-DD` })
    else if (c.type === 'boolean' && !/^(true|false|yes|no|y|n|1|0)$/i.test(v)) out.push({ column: c.key, message: `${c.label} must be yes/no (true/false)` })
    else if (c.type === 'text' && c.max !== undefined && v.length > c.max) out.push({ column: c.key, message: `${c.label} must be at most ${c.max} characters` })
    else if (c.type === 'text' && c.pattern && !new RegExp(c.pattern).test(v)) out.push({ column: c.key, message: `${c.label} ${c.pattern_message ?? 'has an invalid format'}` })
    else if ((c.type === 'int' || c.type === 'number') && c.min !== undefined && Number(v) < c.min) out.push({ column: c.key, message: `${c.label} must be at least ${c.min}` })
    else if ((c.type === 'int' || c.type === 'number') && c.max !== undefined && Number(v) > c.max) out.push({ column: c.key, message: `${c.label} must be at most ${c.max}` })
  }
  return out
}

const csvEscape = (v: unknown) => { const s = v === null || v === undefined ? '' : String(v); return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s }
export const toCsv = (rows: unknown[][]) => rows.map((r) => r.map(csvEscape).join(',')).join('\r\n') + '\r\n'
/** Blank template: one header row of friendly labels, exactly what autoMap recognises. */
export const templateCsv = (columns: TemplateColumn[]) => toCsv([columns.map((c) => c.label)])
export const templateGuide = (columns: TemplateColumn[]) => columns.map((c) => ({ column: c.label, required: !!c.required, type: c.type === 'ref' ? 'code of an existing record' : c.type === 'list' ? 'comma-separated list' : c.type === 'date' ? 'date (YYYY-MM-DD)' : c.type === 'boolean' ? 'yes / no' : c.type === 'int' ? 'whole number' : c.type, help: c.help ?? '' }))
export type ErrRow = { row_no: number; status: string; errors: Array<{ column: string | null; message: string }>; warnings: Array<{ column: string | null; message: string }>; raw: Record<string, string> }
/** Row errors/warnings as a CSV the user can fix and re-upload (original values included). */
export function errorsCsv(rows: ErrRow[], columns: TemplateColumn[]): string {
  const head = ['Row', 'Status', 'Column', 'Problem', ...columns.map((c) => c.label)]
  const body: unknown[][] = []
  for (const r of rows) {
    const items = [...r.errors.map((e) => ({ ...e, kind: 'Error' })), ...r.warnings.map((w) => ({ ...w, kind: 'Warning' }))]
    for (const it of items) body.push([r.row_no, it.kind, it.column ?? '', it.message, ...columns.map((c) => r.raw[c.key] ?? '')])
  }
  return toCsv([head, ...body])
}
export function download(name: string, content: string, mime = 'text/csv;charset=utf-8') {
  const url = URL.createObjectURL(new Blob(['\uFEFF' + content], { type: mime })); const a = document.createElement('a'); a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000)
}
