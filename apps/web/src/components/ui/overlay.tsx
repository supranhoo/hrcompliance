import { useEffect, useRef, type ReactNode } from 'react'
import { Button } from './forms'
import { cx } from './cx'

/** Built on the native <dialog>: focus trap, Esc handling and inertness of the page come from the platform. */
function Modal({ open, onClose, title, children, side, footer }: { open: boolean; onClose: () => void; title: string; children: ReactNode; side?: boolean; footer?: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const d = ref.current; if (!d) return
    if (open && !d.open) { if (typeof d.showModal === 'function') d.showModal(); else d.setAttribute('open', '') }
    if (!open && d.open) { if (typeof d.close === 'function') d.close(); else d.removeAttribute('open') }
  }, [open])
  return (
    <dialog ref={ref} aria-label={title} onClose={onClose} onCancel={(e) => { e.preventDefault(); onClose() }}
      onClick={(e) => { if (e.target === ref.current) onClose() }}
      className={cx('m-auto rounded-lg border border-line bg-white p-0 text-ink shadow-xl backdrop:bg-navy/40', side ? 'ml-auto mr-0 h-full max-h-none w-full max-w-md rounded-none' : 'w-full max-w-lg')}>
      {open && (
        <div className="flex h-full flex-col">
          <header className="flex items-center justify-between border-b border-line px-4 py-3">
            <h2 className="text-base font-semibold text-navy">{title}</h2>
            <button type="button" aria-label="Close" onClick={onClose} className="rounded px-2 py-1 text-muted hover:bg-canvas">✕</button>
          </header>
          <div className="flex-1 overflow-auto p-4">{children}</div>
          {footer && <footer className="flex justify-end gap-2 border-t border-line px-4 py-3">{footer}</footer>}
        </div>
      )}
    </dialog>
  )
}
export const Dialog = (p: Omit<Parameters<typeof Modal>[0], 'side'>) => <Modal {...p} />
/** Right-hand side panel used for quick view. */
export const Drawer = (p: Omit<Parameters<typeof Modal>[0], 'side'>) => <Modal {...p} side />

export function ConfirmDialog({ open, title, message, confirmLabel = 'Confirm', danger, onConfirm, onCancel }: { open: boolean; title: string; message: ReactNode; confirmLabel?: string; danger?: boolean; onConfirm: () => void; onCancel: () => void }) {
  return (
    <Dialog open={open} onClose={onCancel} title={title}
      footer={<><Button variant="secondary" onClick={onCancel}>Cancel</Button><Button variant={danger ? 'danger' : 'primary'} onClick={onConfirm}>{confirmLabel}</Button></>}>
      <div className="text-sm text-ink">{message}</div>
    </Dialog>
  )
}
