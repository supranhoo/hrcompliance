import { createContext, useCallback, useContext, useState, type ReactNode } from 'react'

type Toast = { id: number; tone: 'ok' | 'crit' | 'info'; message: string }
const Ctx = createContext<{ notify: (message: string, tone?: Toast['tone']) => void } | null>(null)

/** Notification shell: transient toasts now; persistent in-app notifications (alerts table) plug into the header bell later. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const notify = useCallback((message: string, tone: Toast['tone'] = 'info') => {
    const id = Date.now() + Math.random()
    setToasts((t) => [...t, { id, tone, message }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 6000)
  }, [])
  return (
    <Ctx.Provider value={{ notify }}>
      {children}
      <div aria-live="polite" className="fixed bottom-4 right-4 z-50 space-y-2">
        {toasts.map((t) => (
          <div key={t.id} role={t.tone === 'crit' ? 'alert' : 'status'}
            className={`rounded border bg-white px-4 py-2 text-sm shadow-lg ${t.tone === 'crit' ? 'border-status-crit text-status-crit' : t.tone === 'ok' ? 'border-status-ok text-status-ok' : 'border-line text-ink'}`}>{t.message}</div>
        ))}
      </div>
    </Ctx.Provider>
  )
}
export function useToast() {
  const v = useContext(Ctx)
  if (!v) throw new Error('useToast must be used inside ToastProvider')
  return v
}
