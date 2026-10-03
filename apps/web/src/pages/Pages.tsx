import { Link, Navigate } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'
import { envErrors } from '../lib/supabase'
import { Button, EmptyState } from '../components/ui'

export function LoginPage() {
  const { status, signInWithGoogle } = useAuth()
  if (status === 'ready') return <Navigate to="/" replace />
  return (
    <div className="grid h-full place-items-center p-4">
      <div className="w-full max-w-sm rounded-lg border border-line bg-white p-8 shadow-sm">
        <h1 className="text-lg font-semibold text-navy">BFCL HR Compliance &amp; Governance</h1>
        <p className="mt-1 text-sm text-muted">Sign in with your authorised Google account.</p>
        {envErrors.length > 0 && <div role="alert" className="mt-4 rounded border border-status-crit p-3 text-sm text-status-crit">Application is not configured: {envErrors.join('; ')}</div>}
        <Button className="mt-6 w-full" disabled={envErrors.length > 0} onClick={() => void signInWithGoogle()}>Continue with Google</Button>
      </div>
    </div>
  )
}

export function NoAccessPage() {
  const { session, signOut } = useAuth()
  return (
    <div className="grid h-full place-items-center p-4">
      <div role="alert" className="max-w-md rounded-lg border border-line bg-white p-8">
        <h1 className="text-lg font-semibold text-navy">Access not provisioned</h1>
        <p className="mt-2 text-sm text-muted">{session?.user.email} is not registered for this application. Ask a Super Admin to add your account.</p>
        <Button variant="secondary" className="mt-4" onClick={() => void signOut()}>Sign out</Button>
      </div>
    </div>
  )
}

export function UnauthorizedPage() {
  return <EmptyState title="You do not have permission to view this page" description="Ask a Super Admin if you need access." action={<Link className="text-sm text-blue underline" to="/">Back to dashboard</Link>} />
}

export function NotFoundPage() {
  return <div className="grid min-h-[50vh] place-items-center"><EmptyState title="Page not found" description="The page you requested does not exist." action={<Link className="text-sm text-blue underline" to="/">Go to dashboard</Link>} /></div>
}

export function DashboardPage() {
  return (
    <section>
      <h1 className="text-xl font-semibold text-navy">Executive Dashboard</h1>
      <div className="mt-4"><EmptyState title="No compliance data yet" description="KPIs are computed server-side from authoritative data once the compliance core exists (Phase 6). Nothing is shown until then rather than placeholder numbers." /></div>
    </section>
  )
}
