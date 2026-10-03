import { forwardRef, useId, useRef, useState, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes } from 'react'
import { cx } from './cx'

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger'
const variants: Record<Variant, string> = {
  primary: 'bg-navy text-white hover:bg-blue',
  secondary: 'border border-line bg-white text-ink hover:bg-canvas',
  ghost: 'text-ink hover:bg-canvas',
  danger: 'bg-status-crit text-white hover:opacity-90',
}
export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; loading?: boolean }>(
  ({ variant = 'primary', loading, disabled, className, children, ...p }, ref) => (
    <button ref={ref} type="button" disabled={disabled || loading} aria-busy={loading || undefined}
      className={cx('inline-flex items-center justify-center gap-2 rounded px-3 py-1.5 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue disabled:cursor-not-allowed disabled:opacity-50', variants[variant], className)} {...p}>
      {loading && <span aria-hidden className="size-3 animate-spin rounded-full border-2 border-current border-t-transparent" />}
      {children}
    </button>
  ))
Button.displayName = 'Button'

const control = 'w-full rounded border border-line bg-white px-3 py-1.5 text-sm text-ink placeholder:text-muted focus-visible:outline-2 focus-visible:outline-blue disabled:bg-canvas aria-[invalid=true]:border-status-crit'

/** Label + control + help/error wiring (aria-describedby, aria-invalid). */
export function Field({ label, error, help, required, children }: { label: string; error?: string; help?: string; required?: boolean; children: (p: { id: string; 'aria-describedby'?: string; 'aria-invalid'?: boolean }) => ReactNode }) {
  const id = useId(); const hid = `${id}-h`
  return (
    <div className="space-y-1">
      <label htmlFor={id} className="block text-sm font-medium text-ink">{label}{required && <span aria-hidden className="text-status-crit"> *</span>}</label>
      {children({ id, 'aria-describedby': error || help ? hid : undefined, 'aria-invalid': error ? true : undefined })}
      {(error || help) && <p id={hid} role={error ? 'alert' : undefined} className={cx('text-xs', error ? 'text-status-crit' : 'text-muted')}>{error ?? help}</p>}
    </div>
  )
}
export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(({ className, ...p }, ref) => <input ref={ref} className={cx(control, className)} {...p} />)
Input.displayName = 'Input'
export const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(({ className, rows = 4, ...p }, ref) => <textarea ref={ref} rows={rows} className={cx(control, className)} {...p} />)
Textarea.displayName = 'Textarea'
export type Option = { value: string; label: string; disabled?: boolean }
export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement> & { options: Option[]; placeholder?: string }>(({ options, placeholder, className, ...p }, ref) => (
  <select ref={ref} className={cx(control, className)} {...p}>
    {placeholder !== undefined && <option value="">{placeholder}</option>}
    {options.map((o) => <option key={o.value} value={o.value} disabled={o.disabled}>{o.label}</option>)}
  </select>
))
Select.displayName = 'Select'

/** Native date / datetime inputs: accessible, localised and keyboard-friendly without an extra dependency (D-006). */
export const DatePicker = forwardRef<HTMLInputElement, Omit<InputHTMLAttributes<HTMLInputElement>, 'type'>>((p, ref) => <Input ref={ref} type="date" {...p} />)
DatePicker.displayName = 'DatePicker'
export const DateTimePicker = forwardRef<HTMLInputElement, Omit<InputHTMLAttributes<HTMLInputElement>, 'type'>>((p, ref) => <Input ref={ref} type="datetime-local" {...p} />)
DateTimePicker.displayName = 'DateTimePicker'

/** Accessible multi-select: a disclosure button + checkbox group. Controlled. */
export function MultiSelect({ label, options, value, onChange, placeholder = 'Select…' }: { label: string; options: Option[]; value: string[]; onChange: (v: string[]) => void; placeholder?: string }) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const id = useId()
  const summary = value.length === 0 ? placeholder : options.filter((o) => value.includes(o.value)).map((o) => o.label).join(', ')
  return (
    <div ref={ref} className="relative" onKeyDown={(e) => { if (e.key === 'Escape') setOpen(false) }}>
      <button type="button" aria-haspopup="true" aria-expanded={open} aria-controls={id} aria-label={label} onClick={() => setOpen((o) => !o)}
        className={cx(control, 'truncate text-left')}>{summary}</button>
      {open && (
        <fieldset id={id} className="absolute z-20 mt-1 max-h-60 w-full overflow-auto rounded border border-line bg-white p-2 shadow-lg">
          <legend className="sr-only">{label}</legend>
          {options.map((o) => (
            <label key={o.value} className="flex items-center gap-2 rounded px-2 py-1 text-sm hover:bg-canvas">
              <input type="checkbox" checked={value.includes(o.value)} disabled={o.disabled}
                onChange={(e) => onChange(e.target.checked ? [...value, o.value] : value.filter((v) => v !== o.value))} />
              {o.label}
            </label>
          ))}
        </fieldset>
      )}
    </div>
  )
}
