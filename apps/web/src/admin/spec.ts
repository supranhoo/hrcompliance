import type { Option } from '../components/ui'

/** Declarative description of an admin form. The same spec drives rendering, frontend validation and the payload sent to PostgREST;
 *  the database re-validates everything (constraints, triggers, RLS) - this is convenience and early feedback, never authority. */
export type FieldType = 'text' | 'textarea' | 'number' | 'date' | 'boolean' | 'select' | 'list'
export type Lookup = { table: string; value: string; label: string; filter?: Record<string, string | boolean>; order?: string }
export type FieldSpec = {
  key: string; label: string; type: FieldType; required?: boolean; help?: string
  lov?: string; lookup?: Lookup; options?: Option[]
  pattern?: RegExp; patternMessage?: string; max?: number; min?: number
  /** For type 'list' (comma separated): each item must match; max = maximum number of items. */
  itemPattern?: RegExp
  /** Cannot be changed once the record exists (e.g. a business code). Shown read-only on edit. */
  immutable?: boolean
  /** Stored by the backend (never sent), shown read-only. */
  readOnly?: boolean
  placeholder?: string
}
export type Values = Record<string, string | boolean>
export type Mode = 'create' | 'edit'

export const emptyValues = (fields: FieldSpec[]): Values => Object.fromEntries(fields.map((f) => [f.key, f.type === 'boolean' ? (f.key === 'is_active') : '']))
export function valuesFromRow(fields: FieldSpec[], row: Record<string, unknown>): Values {
  return Object.fromEntries(fields.map((f) => {
    const v = row[f.key]
    return [f.key, f.type === 'boolean' ? Boolean(v) : Array.isArray(v) ? v.join(', ') : v === null || v === undefined ? '' : String(v)]
  }))
}

const isBlank = (v: string | boolean | undefined) => v === undefined || v === '' || (typeof v === 'string' && v.trim() === '')

/** Frontend validation. Returns key -> message; empty object = valid. */
export function validate(fields: FieldSpec[], values: Values, mode: Mode): Record<string, string> {
  const errors: Record<string, string> = {}
  for (const f of fields) {
    if (f.readOnly || (mode === 'edit' && f.immutable)) continue
    const v = values[f.key]
    if (f.type === 'boolean') continue
    if (isBlank(v)) { if (f.required) errors[f.key] = `${f.label} is required`; continue }
    const s = String(v).trim()
    if (f.type === 'number') {
      if (!/^-?\d+(\.\d+)?$/.test(s)) { errors[f.key] = `${f.label} must be a number`; continue }
      if (f.min !== undefined && Number(s) < f.min) errors[f.key] = `${f.label} must be at least ${f.min}`
      else if (f.max !== undefined && Number(s) > f.max) errors[f.key] = `${f.label} must be at most ${f.max}`
    } else if (f.type === 'list') {
      const items = s.split(',').map((x) => x.trim()).filter(Boolean)
      if (items.length === 0) errors[f.key] = `${f.label} is required`
      else if (f.max !== undefined && items.length > f.max) errors[f.key] = `${f.label}: at most ${f.max} items`
      else if (f.itemPattern && items.some((i) => !f.itemPattern!.test(i))) errors[f.key] = f.patternMessage ?? `${f.label} has an invalid item`
    } else if (f.type === 'date') {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(s) || Number.isNaN(Date.parse(s))) errors[f.key] = `${f.label} must be a valid date`
    } else {
      if (f.max !== undefined && s.length > f.max) errors[f.key] = `${f.label} must be at most ${f.max} characters`
      if (f.pattern && !f.pattern.test(s)) errors[f.key] = f.patternMessage ?? `${f.label} has an invalid format`
    }
  }
  return errors
}

/** Cross-field rule shared by every "valid from / valid to" pair. */
export function validatePeriod(values: Values, fromKey: string, toKey: string, label = 'Effective to'): string | undefined {
  const a = String(values[fromKey] ?? ''), b = String(values[toKey] ?? '')
  return a && b && b < a ? `${label} cannot be before the start date` : undefined
}

/** Payload for PostgREST: blanks become null, numbers become numbers, immutable/read-only fields are omitted on edit. */
export function toPayload(fields: FieldSpec[], values: Values, mode: Mode): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const f of fields) {
    if (f.readOnly || (mode === 'edit' && f.immutable)) continue
    const v = values[f.key]
    if (f.type === 'boolean') out[f.key] = Boolean(v)
    else if (isBlank(v)) out[f.key] = null
    else if (f.type === 'number') out[f.key] = Number(String(v).trim())
    else if (f.type === 'list') out[f.key] = String(v).split(',').map((x) => x.trim()).filter(Boolean)
    else out[f.key] = String(v).trim()
  }
  return out
}
