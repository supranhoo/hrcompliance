import { useEffect, useRef, useState } from 'react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from './AuthProvider'
import { can } from '../lib/access'
import { appEnv } from '../lib/supabase'
import { breadcrumbsFor, NAV } from './navigation'
import { ErrorBoundary } from './ErrorBoundary'
import { cx } from '../components/ui'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { unreadLabel } from '../lib/notifications'
import { UNREAD_KEY } from '../pages/NotificationsPage'

function Bell() {
  const q = useQuery({
    queryKey: UNREAD_KEY, refetchInterval: 60_000,
    queryFn: async () => {
      if (!supabase) return 0
      const { count, error } = await supabase.from('notification').select('id', { count: 'exact', head: true }).eq('channel', 'in_app').is('read_at', null)
      if (error) throw error
      return count ?? 0
    },
  })
  const n = q.data ?? 0
  return (
    <Link to="/notifications" aria-label={unreadLabel(n)} title={unreadLabel(n)} className="relative rounded px-2 py-1 text-muted hover:bg-canvas">
      🔔{n > 0 && <span className="absolute -right-0.5 -top-0.5 min-w-4 rounded-full bg-status-crit px-1 text-center text-[10px] font-semibold leading-4 text-white">{n > 99 ? '99+' : n}</span>}
    </Link>
  )
}

function Sidebar({ collapsed, onNavigate }: { collapsed: boolean; onNavigate?: () => void }) {
  const { access } = useAuth()
  const groups = ['Overview', 'Compliance', 'Master Data', 'Administration'] as const
  return (
    <nav aria-label="Primary" className="flex-1 space-y-4 overflow-y-auto px-2 py-2">
      {groups.map((g) => {
        const items = NAV.filter((n) => n.group === g && (!n.perm || can(access, n.perm)))
        if (items.length === 0) return null
        return (
          <div key={g}>
            {!collapsed && <div className="px-3 pb-1 text-[11px] uppercase tracking-wider text-white/50">{g}</div>}
            {items.map((n) => (
              <NavLink key={n.path} to={n.path} end onClick={onNavigate} title={collapsed ? n.title : undefined}
                className={({ isActive }) => cx('block truncate rounded px-3 py-2 text-sm', isActive ? 'bg-blue text-white' : 'text-white/85 hover:bg-white/10')}>
                {collapsed ? n.title.slice(0, 2) : n.title}
              </NavLink>
            ))}
          </div>
        )
      })}
    </nav>
  )
}

function ProfileMenu() {
  const { access, session, signOut } = useAuth()
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const close = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false) }
    document.addEventListener('mousedown', close); return () => document.removeEventListener('mousedown', close)
  }, [])
  const name = access?.fullName ?? access?.email ?? session?.user.email ?? ''
  return (
    <div ref={ref} className="relative" onKeyDown={(e) => { if (e.key === 'Escape') setOpen(false) }}>
      <button type="button" aria-haspopup="menu" aria-expanded={open} aria-label={`Account menu for ${name}`} onClick={() => setOpen((o) => !o)} className="flex items-center gap-2 rounded px-2 py-1 hover:bg-canvas">
        <span aria-hidden className="grid size-7 place-items-center rounded-full bg-navy text-xs text-white">{name.slice(0, 1).toUpperCase()}</span>
        <span className="hidden max-w-40 truncate text-sm sm:inline">{name}</span>
      </button>
      {open && (
        <div role="menu" className="absolute right-0 z-30 mt-1 w-60 rounded border border-line bg-white p-2 text-sm shadow-lg">
          <div className="px-2 py-1"><div className="truncate font-medium">{name}</div><div className="truncate text-xs text-muted">{access?.roles.join(', ') || 'No role'}</div></div>
          <button role="menuitem" type="button" className="mt-1 w-full rounded px-2 py-1 text-left hover:bg-canvas" onClick={() => void signOut()}>Sign out</button>
        </div>
      )}
    </div>
  )
}

export function Layout() {
  const [collapsed, setCollapsed] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)
  const { pathname } = useLocation()
  const crumbs = breadcrumbsFor(pathname)
  return (
    <div className="flex h-full">
      <aside className={cx('hidden shrink-0 flex-col bg-navy text-white transition-[width] md:flex', collapsed ? 'w-16' : 'w-60')} aria-label="Sidebar">
        <div className="flex items-center justify-between px-3 py-4"><span className="truncate text-sm font-semibold">{collapsed ? 'BF' : 'BFCL HR Compliance'}</span></div>
        <Sidebar collapsed={collapsed} />
        <button type="button" aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'} onClick={() => setCollapsed((c) => !c)} className="m-2 rounded px-2 py-1 text-xs text-white/70 hover:bg-white/10">{collapsed ? '»' : '« Collapse'}</button>
      </aside>

      {mobileOpen && (
        <div className="fixed inset-0 z-40 md:hidden" role="dialog" aria-modal="true" aria-label="Navigation">
          <div className="absolute inset-0 bg-navy/50" onClick={() => setMobileOpen(false)} />
          <div className="relative flex h-full w-64 flex-col bg-navy text-white"><div className="px-3 py-4 text-sm font-semibold">BFCL HR Compliance</div><Sidebar collapsed={false} onNavigate={() => setMobileOpen(false)} /></div>
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center gap-3 border-b border-line bg-white px-3 py-2">
          <button type="button" className="rounded px-2 py-1 hover:bg-canvas md:hidden" aria-label="Open navigation" onClick={() => setMobileOpen(true)}>☰</button>
          <nav aria-label="Breadcrumb" className="min-w-0 flex-1 truncate text-sm text-muted">
            <ol className="flex items-center gap-1">
              {crumbs.map((c, i) => (
                <li key={c.path} className="flex items-center gap-1 truncate">
                  {i > 0 && <span aria-hidden>/</span>}
                  {i === crumbs.length - 1 ? <span aria-current="page" className="truncate text-ink">{c.title}</span> : <Link to={c.path} className="hover:underline">{c.title}</Link>}
                </li>
              ))}
            </ol>
          </nav>
          <span className="rounded bg-canvas px-2 py-0.5 text-xs uppercase text-muted">{appEnv}</span>
          <Bell />
          <ProfileMenu />
        </header>
        <main tabIndex={0} aria-label="Page content" className="min-w-0 flex-1 overflow-auto p-4 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-blue md:p-6"><ErrorBoundary><Outlet /></ErrorBoundary></main>
      </div>
    </div>
  )
}
