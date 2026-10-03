import { Navigate } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'
import { envErrors } from '../lib/supabase'

export function LoginPage() {
  const { status, signInWithGoogle } = useAuth()
  if (status === 'ready') return <Navigate to="/" replace />
  return (
    <div className="grid h-full place-items-center">
      <div className="w-full max-w-sm rounded-lg border border-line bg-white p-8 shadow-sm">
        <h1 className="text-lg font-semibold text-navy">BFCL HR Compliance &amp; Governance</h1>
        <p className="mt-1 text-sm text-muted">Sign in with your authorised BFCL Google account.</p>
        {envErrors.length > 0 && (
          <div role="alert" className="mt-4 rounded border border-status-crit p-3 text-sm text-status-crit">
            Application is not configured: {envErrors.join('; ')}
          </div>
        )}
        <button disabled={envErrors.length > 0} onClick={() => void signInWithGoogle()}
          className="mt-6 w-full rounded bg-navy px-4 py-2 text-sm text-white hover:bg-blue disabled:opacity-50">
          Continue with Google
        </button>
      </div>
    </div>
  )
}

export function NoAccessPage() {
  const { session, signOut } = useAuth()
  return (
    <div className="grid h-full place-items-center">
      <div role="alert" className="max-w-md rounded-lg border border-line bg-white p-8">
        <h1 className="text-lg font-semibold text-navy">Access not provisioned</h1>
        <p className="mt-2 text-sm text-muted">{session?.user.email} is not registered for this application. Ask a Super Admin to add your account.</p>
        <button className="mt-4 rounded border border-line px-3 py-1 text-sm" onClick={() => void signOut()}>Sign out</button>
      </div>
    </div>
  )
}

export function DashboardPage() {
  return (
    <section>
      <h1 className="text-xl font-semibold text-navy">Executive Dashboard</h1>
      <p className="mt-2 text-sm text-muted">No compliance data exists yet. KPIs are built after the compliance core (Phase 6) and show real aggregates only.</p>
    </section>
  )
}

export function SystemHealthPage() {
  return <h1 className="text-xl font-semibold text-navy">System Health</h1>
}
