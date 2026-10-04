/** Turns a PostgREST / Postgres error into a sentence a business user can act on. The database message is kept when it already explains the rule. */
export type DbErrorLike = { code?: string; message?: string; details?: string; hint?: string }

export function describeError(e: unknown): string {
  const err = (e ?? {}) as DbErrorLike
  const msg = (err.message ?? (e instanceof Error ? e.message : '') ?? '').trim()
  switch (err.code) {
    case '23505': return /draft|already uploaded/i.test(msg) ? msg : 'A record with the same code or key already exists.'
    case '23503': return 'This record is referenced by other data, or refers to something that does not exist.'
    case '23502': return 'A required value is missing.'
    case '23514': return msg || 'A value does not satisfy a data rule.'
    case '42501': return /RLS|row-level|row level/i.test(msg) ? 'You do not have permission for this action (or the record is outside your scope).' : msg || 'You do not have permission for this action.'
    case 'PGRST116': return 'The record was not found or is outside your scope.'
    case 'AD001': case 'AD002': return msg
    case '22023': return msg || 'A value is not allowed.'
    default: return msg || 'Something went wrong. Please try again.'
  }
}
/** Optimistic locking: update ... where row_version = n returned nothing. */
export const CONFLICT_MESSAGE = 'This record was changed by someone else since you opened it. Close and reopen it to see the latest version.'

/** AD002 = the change would remove the caller's own admin access; the user must confirm explicitly and the call is repeated with the flag. */
export const isSelfLockout = (e: unknown) => (e as DbErrorLike | null)?.code === 'AD002'
