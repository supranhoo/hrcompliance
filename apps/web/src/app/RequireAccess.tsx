import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from './AuthProvider'
import { can } from '../lib/access'

export function RequireAuth() {
  const { status } = useAuth()
  if (status === 'loading') return <p role="status" className="p-8 text-muted">Loading…</p>
  if (status === 'signed_out') return <Navigate to="/login" replace />
  if (status === 'unauthorized') return <Navigate to="/no-access" replace />
  if (status === 'error') return <p role="alert" className="p-8 text-status-crit">Could not load your access profile. Please retry or contact the administrator.</p>
  return <Outlet />
}

/** Route-level UX guard. The database re-checks every read/write via RLS. */
export function RequirePermission({ perm }: { perm: string }) {
  const { access } = useAuth()
  return can(access, perm) ? <Outlet /> : <p role="alert" className="p-8 text-status-crit">You do not have permission to view this page.</p>
}
