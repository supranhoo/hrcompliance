/** Pure helpers for user / role / permission administration. Permissions come from the database; nothing here names a role. */
export type PermissionRow = { code: string; module: string; description: string | null }

/** Permissions that, if lost, can lock an administrator out. Shown with a warning in the editor. */
export const CRITICAL_PERMISSIONS = ['user.admin', 'role.admin'] as const

export function groupByModule(perms: PermissionRow[]): Array<{ module: string; items: PermissionRow[] }> {
  const m = new Map<string, PermissionRow[]>()
  for (const p of perms) m.set(p.module, [...(m.get(p.module) ?? []), p])
  return [...m.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([module, items]) => ({ module, items: items.sort((x, y) => x.code.localeCompare(y.code)) }))
}

export type PermissionDiff = { added: string[]; removed: string[] }
export function diffPermissions(before: string[], after: string[]): PermissionDiff {
  const b = new Set(before); const a = new Set(after)
  return { added: after.filter((x) => !b.has(x)).sort(), removed: before.filter((x) => !a.has(x)).sort() }
}
export const touchesCritical = (d: PermissionDiff) => d.removed.some((p) => (CRITICAL_PERMISSIONS as readonly string[]).includes(p))

export function validateRoleForm(f: { code: string; name: string; reason: string }, isNew: boolean): Record<string, string> {
  const e: Record<string, string> = {}
  if (isNew && !/^[A-Z][A-Z0-9_]{1,40}$/.test(f.code)) e.code = 'Use capital letters, digits and underscores, starting with a letter (e.g. PLANT_AUDITOR)'
  if (!f.name.trim()) e.name = 'Name is required'
  if (!f.reason.trim()) e.reason = 'A reason is required; it is recorded in the audit history'
  return e
}
export function validateInvite(f: { email: string; reason: string }): Record<string, string> {
  const e: Record<string, string> = {}
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(f.email.trim())) e.email = 'Enter a valid email address (the same Google account the person signs in with)'
  if (!f.reason.trim()) e.reason = 'A reason is required; it is recorded in the audit history'
  return e
}
export function validateScope(f: { scopeAll: boolean; entities: string[]; locations: string[]; departments: string[]; reason: string }): Record<string, string> {
  const e: Record<string, string> = {}
  if (!f.scopeAll && f.entities.length + f.locations.length === 0) e.scope = f.departments.length > 0
    ? 'A department only narrows an entity or location scope. Also choose at least one legal entity or location, or “All locations”.'
    : 'Choose “All locations” or at least one legal entity or location. A user with no scope sees nothing.'
  if (!f.reason.trim()) e.reason = 'A reason is required; it is recorded in the audit history'
  return e
}

/** Plain-language summary of a user's reach. “All locations” is broad access; otherwise it lists the explicit scope. */
export function describeScope(s: { scopeAll: boolean; entities: number; locations: number; departments: number }): string {
  if (s.scopeAll) return 'All locations (broad access, ignores entity, location and department limits)'
  if (s.entities + s.locations + s.departments === 0) return 'No scope: sees no business data'
  const parts = [s.entities && `${s.entities} ${s.entities === 1 ? 'entity' : 'entities'}`, s.locations && `${s.locations} ${s.locations === 1 ? 'location' : 'locations'}`].filter(Boolean) as string[]
  const where = parts.length ? parts.join(' + ') : 'no entity or location'
  return s.departments ? `${where}, limited to ${s.departments} ${s.departments === 1 ? 'department' : 'departments'} for department-owned items` : `${where}; department-owned items are hidden (no department scope)`
}
