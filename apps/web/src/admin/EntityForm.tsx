import { Field, Input, Select, Textarea, DatePicker } from '../components/ui'
import { useFieldOptions } from './lookups'
import type { FieldSpec, Mode, Values } from './spec'

function Control({ f, id, values, onChange, mode, aria }: { f: FieldSpec; id: string; values: Values; onChange: (k: string, v: string | boolean) => void; mode: Mode; aria: Record<string, unknown> }) {
  const options = useFieldOptions(f)
  const v = values[f.key]
  const locked = f.readOnly || (mode === 'edit' && f.immutable)
  const common = { id, disabled: locked, ...aria }
  switch (f.type) {
    case 'textarea': return <Textarea {...common} rows={3} value={String(v ?? '')} onChange={(e) => onChange(f.key, e.target.value)} />
    case 'number': return <Input {...common} inputMode="decimal" value={String(v ?? '')} placeholder={f.placeholder} onChange={(e) => onChange(f.key, e.target.value)} />
    case 'date': return <DatePicker {...common} value={String(v ?? '')} onChange={(e) => onChange(f.key, e.target.value)} />
    case 'select': {
      const withCurrent = v && !options.some((o) => o.value === v) ? [...options, { value: String(v), label: String(v) }] : options
      return <Select {...common} value={String(v ?? '')} placeholder="Select…" options={withCurrent} onChange={(e) => onChange(f.key, e.target.value)} />
    }
    case 'boolean': return null
    default: return <Input {...common} value={String(v ?? '')} placeholder={f.placeholder} onChange={(e) => onChange(f.key, f.pattern && f.key === 'code' ? e.target.value.toUpperCase() : e.target.value)} />
  }
}

/** Renders a FieldSpec list as an accessible, responsive form. Controlled; validation messages come from the parent (spec.validate + server errors). */
export function EntityForm({ fields, values, errors, mode, onChange }: { fields: FieldSpec[]; values: Values; errors: Record<string, string>; mode: Mode; onChange: (k: string, v: string | boolean) => void }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {fields.map((f) => f.type === 'boolean' ? (
        <label key={f.key} className="flex items-center gap-2 text-sm sm:col-span-2">
          <input type="checkbox" checked={Boolean(values[f.key])} disabled={f.readOnly} onChange={(e) => onChange(f.key, e.target.checked)} />
          <span>{f.label}</span>{f.help && <span className="text-xs text-muted">— {f.help}</span>}
        </label>
      ) : (
        <div key={f.key} className={f.type === 'textarea' ? 'sm:col-span-2' : undefined}>
          <Field label={f.label} required={f.required && !(mode === 'edit' && f.immutable)} error={errors[f.key]} help={f.help ?? (mode === 'edit' && f.immutable ? 'Cannot be changed after creation' : undefined)}>
            {(a) => <Control f={f} id={a.id} values={values} onChange={onChange} mode={mode} aria={{ 'aria-describedby': a['aria-describedby'], 'aria-invalid': a['aria-invalid'] }} />}
          </Field>
        </div>
      ))}
    </div>
  )
}
