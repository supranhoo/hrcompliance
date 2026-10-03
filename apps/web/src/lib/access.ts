import { z } from 'zod'

/** Shape returned by the `my_access()` RPC. Empty object = signed in with Google but not provisioned. */
export const accessSchema = z.union([
  z.object({
    user_id: z.string(),
    email: z.string(),
    full_name: z.string().nullable(),
    scope_all: z.boolean(),
    roles: z.array(z.string()),
    permissions: z.array(z.string()),
    scopes: z.array(z.object({ type: z.enum(['entity', 'location', 'department']), id: z.string() })),
  }),
  z.object({}).strict(),
])
export type Access = {
  userId: string; email: string; fullName: string | null; scopeAll: boolean
  roles: string[]; permissions: ReadonlySet<string>
}

export function parseAccess(raw: unknown): Access | null {
  const r = accessSchema.parse(raw)
  if (!('user_id' in r)) return null
  return { userId: r.user_id, email: r.email, fullName: r.full_name, scopeAll: r.scope_all, roles: r.roles, permissions: new Set(r.permissions) }
}

/** UI convenience only. Real enforcement is RLS in PostgreSQL; hiding a button is never authorization. */
export const can = (a: Access | null, perm: string) => !!a && a.permissions.has(perm)
