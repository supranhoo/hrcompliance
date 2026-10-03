import { useState, type ReactNode } from 'react'
import { useAuth } from '../../app/AuthProvider'
import { can } from '../../lib/access'

export type TabDef = { id: string; label: string; content: ReactNode }
/** WAI-ARIA tabs with arrow-key navigation. */
export function Tabs({ tabs, initial }: { tabs: TabDef[]; initial?: string }) {
  const [active, setActive] = useState(initial ?? tabs[0]?.id)
  const move = (dir: number) => { const i = tabs.findIndex((t) => t.id === active); setActive(tabs[(i + dir + tabs.length) % tabs.length].id) }
  return (
    <div>
      <div role="tablist" className="flex gap-1 border-b border-line"
        onKeyDown={(e) => { if (e.key === 'ArrowRight') move(1); if (e.key === 'ArrowLeft') move(-1) }}>
        {tabs.map((t) => (
          <button key={t.id} role="tab" id={`tab-${t.id}`} aria-selected={t.id === active} aria-controls={`panel-${t.id}`} tabIndex={t.id === active ? 0 : -1}
            onClick={() => setActive(t.id)}
            className={`-mb-px border-b-2 px-3 py-2 text-sm ${t.id === active ? 'border-blue font-medium text-navy' : 'border-transparent text-muted hover:text-ink'}`}>{t.label}</button>
        ))}
      </div>
      {tabs.map((t) => <div key={t.id} role="tabpanel" id={`panel-${t.id}`} aria-labelledby={`tab-${t.id}`} hidden={t.id !== active} className="pt-4">{t.id === active && t.content}</div>)}
    </div>
  )
}

/** UX only: hides/disables an action the user lacks permission for. The database still enforces it via RLS. */
export function PermissionGate({ perm, children, fallback = null, mode = 'hide' }: { perm: string; children: ReactNode; fallback?: ReactNode; mode?: 'hide' | 'fallback' }) {
  const { access } = useAuth()
  if (can(access, perm)) return <>{children}</>
  return <>{mode === 'fallback' ? fallback : null}</>
}
