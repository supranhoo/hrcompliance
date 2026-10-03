/** Structured, whitelisted applicability conditions (the same AST the database evaluates with app.rule_eval). No SQL, no scripting: only
 *  {op, field, value} leaves under one and/or group, over a fixed list of location/entity facts. app.rule_is_valid re-validates on save. */
export type FactType = 'text' | 'number'
export const FACTS: Array<{ key: string; label: string; type: FactType }> = [
  { key: 'location.employee_headcount', label: 'Employees at the location', type: 'number' },
  { key: 'location.contractor_headcount', label: 'Contractor headcount', type: 'number' },
  { key: 'location.state', label: 'State', type: 'text' },
  { key: 'location.district', label: 'District', type: 'text' },
  { key: 'location.establishment_type', label: 'Establishment type', type: 'text' },
  { key: 'location.code', label: 'Location code', type: 'text' },
  { key: 'entity.industry', label: 'Entity industry', type: 'text' },
  { key: 'entity.code', label: 'Entity code', type: 'text' },
]
export const OPS: Record<FactType, Array<{ op: string; label: string }>> = {
  number: [{ op: 'gte', label: 'is at least' }, { op: 'gt', label: 'is more than' }, { op: 'lte', label: 'is at most' }, { op: 'lt', label: 'is less than' }, { op: 'eq', label: 'equals' }, { op: 'neq', label: 'does not equal' }, { op: 'is_blank', label: 'is unknown' }, { op: 'is_not_blank', label: 'is known' }],
  text: [{ op: 'eq', label: 'is' }, { op: 'neq', label: 'is not' }, { op: 'in', label: 'is one of' }, { op: 'not_in', label: 'is none of' }, { op: 'contains', label: 'contains' }, { op: 'is_blank', label: 'is unknown' }, { op: 'is_not_blank', label: 'is known' }],
}
export type Leaf = { field: string; op: string; value: string }
export type Draft = { join: 'and' | 'or'; leaves: Leaf[] }
export type Ast = { op: 'and' | 'or'; args: Array<{ op: string; field: string; value?: string | number | string[] }> }
const factOf = (key: string) => FACTS.find((f) => f.key === key)
const noValue = (op: string) => op === 'is_blank' || op === 'is_not_blank'

export const emptyDraft = (): Draft => ({ join: 'and', leaves: [{ field: FACTS[0].key, op: 'gte', value: '' }] })
export function leafError(l: Leaf): string | undefined {
  const f = factOf(l.field); if (!f) return 'Choose what to test'
  if (!OPS[f.type].some((o) => o.op === l.op)) return 'Choose a comparison'
  if (noValue(l.op)) return undefined
  if (l.value.trim() === '') return 'Enter a value'
  if (f.type === 'number' && !/^-?\d+(\.\d+)?$/.test(l.value.trim())) return 'Enter a number'
  return undefined
}
export function draftErrors(d: Draft): string[] { return d.leaves.map((l) => leafError(l) ?? '') }
export function toAst(d: Draft): Ast {
  return { op: d.join, args: d.leaves.map((l) => {
    const f = factOf(l.field)!
    if (noValue(l.op)) return { op: l.op, field: l.field }
    if (l.op === 'in' || l.op === 'not_in') return { op: l.op, field: l.field, value: l.value.split(',').map((x) => x.trim()).filter(Boolean) }
    return { op: l.op, field: l.field, value: f.type === 'number' ? Number(l.value.trim()) : l.value.trim() }
  }) }
}
/** Mirror of app.rule_is_valid for what this builder can produce (used as a guard before sending). */
export function isValidAst(a: unknown): boolean {
  const g = a as Ast | null; if (!g || (g.op !== 'and' && g.op !== 'or') || !Array.isArray(g.args) || g.args.length === 0) return false
  return g.args.every((x) => { const f = factOf(x.field); return !!f && OPS[f.type].some((o) => o.op === x.op) && (noValue(x.op) ? !('value' in x) : x.op === 'in' || x.op === 'not_in' ? Array.isArray(x.value) && x.value.length > 0 : x.value !== undefined && x.value !== '') })
}
/** Reads back a stored condition into builder rows (null if it was not authored by this builder: shown read-only instead). */
export function fromAst(a: unknown): Draft | null {
  if (!isValidAst(a)) return null
  const g = a as Ast
  return { join: g.op, leaves: g.args.map((x) => ({ field: x.field, op: x.op, value: x.value === undefined ? '' : Array.isArray(x.value) ? x.value.join(', ') : String(x.value) })) }
}
export function describeAst(a: unknown): string {
  const g = a as Ast | null; if (!g || !Array.isArray(g.args)) return '—'
  const word = g.op === 'or' ? ' OR ' : ' AND '
  return g.args.map((x) => {
    const f = factOf(x.field); const o = f && OPS[f.type].find((p) => p.op === x.op)
    const v = x.value === undefined ? '' : Array.isArray(x.value) ? ` ${x.value.join(', ')}` : ` ${x.value}`
    return `${f?.label ?? x.field} ${o?.label ?? x.op}${v}`
  }).join(word)
}
