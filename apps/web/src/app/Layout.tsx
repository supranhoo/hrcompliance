import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from './AuthProvider'
import { can } from '../lib/access'
import { appEnv } from '../lib/supabase'

const nav = [
  { to: '/', label: 'Executive Dashboard', perm: null },
  { to: '/admin/system-health', label: 'System Health', perm: 'config.read' },
]

export function Layout() {
  const { access, signOut } = useAuth()
  return (
    <div className="flex h-full">
      <aside className="hidden w-60 shrink-0 flex-col bg-navy text-white md:flex" aria-label="Primary">
        <div className="px-5 py-4 text-sm font-semibold tracking-wide">BFCL HR Compliance</div>
        <nav className="flex-1 space-y-1 px-2">
          {nav.filter((n) => !n.perm || can(access, n.perm)).map((n) => (
            <NavLink key={n.to} to={n.to} end className={({ isActive }) => `block rounded px-3 py-2 text-sm ${isActive ? 'bg-blue' : 'hover:bg-white/10'}`}>{n.label}</NavLink>
          ))}
        </nav>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-line bg-white px-4 py-2 text-sm">
          <span className="rounded bg-canvas px-2 py-0.5 text-xs uppercase text-muted">{appEnv}</span>
          <span className="flex items-center gap-3">
            <span className="text-muted">{access?.fullName ?? access?.email}</span>
            <button className="rounded border border-line px-2 py-1 hover:bg-canvas" onClick={() => void signOut()}>Sign out</button>
          </span>
        </header>
        <main className="min-w-0 flex-1 overflow-auto p-4 md:p-6"><Outlet /></main>
      </div>
    </div>
  )
}
