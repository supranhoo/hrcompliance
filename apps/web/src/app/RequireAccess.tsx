import { Navigate, Outlet } from 'react-router-dom'
import { Button, ErrorState, Skeleton } from '../components/ui'
import { useAuth } from './AuthProvider'
import { can } from '../lib/access'
import { UnauthorizedPage } from '../pages/Pages'

export function RequireAuth() {
  const { status, retryAccess, errorMessage, signOut } = useAuth()
  if (status === 'loading') return <div className="grid h-full place-items-center p-4"><div className="w-48"><Skeleton rows={3} /></div></div>
  if (status === 'signed_out') return <Navigate to="/login" replace />
  if (status === 'unauthorized') return <Navigate to="/no-access" replace />
  if (status === 'error') return (
    <div className="grid h-full place-items-center p-4"><div className="w-full max-w-md space-y-3">
      <ErrorState title="Could not load your access profile" message={errorMessage ?? 'Please retry or contact the administrator.'} onRetry={retryAccess} />
      <Button variant="secondary" onClick={() => void signOut()}>Sign out</Button>
    </div></div>)
  return <Outlet />
}

/** Route-level UX guard. The database re-checks every read/write via RLS. */
export function RequirePermission({ perm }: { perm: string }) {
  const { access } = useAuth()
  return can(access, perm) ? <Outlet /> : <UnauthorizedPage />
}
