import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Badge, Button, ErrorState, Field, Select, Skeleton } from '../../components/ui'
import { useToast } from '../../app/Toasts'
import { supabase } from '../../lib/supabase'
import { describeError } from '../errors'
import { applyMapping, autoMap, download, parseCsv, parseXlsx, quickCheck, sha256Hex, templateCsv, templateGuide, unmappedRequired, type Mapping, type RawTable, type TemplateDef } from './importFile'
import { useTemplateDef, useTemplates } from './hooks'

const DUP = [{ value: 'skip', label: 'Skip rows that already exist (recommended)' }, { value: 'update', label: 'Update existing records with the values provided' }, { value: 'error', label: 'Treat existing records as errors' }]
const MAX_BYTES = 10 * 1024 * 1024

export function NewImportPage() {
  const tpls = useTemplates(); const [code, setCode] = useState(''); const def = useTemplateDef(code || undefined)
  if (tpls.isLoading) return <Skeleton rows={4} />; if (tpls.error) return <ErrorState message={(tpls.error as Error).message} />
  return (
    <section className="space-y-4">
      <div><Link className="text-sm text-blue hover:underline" to="/admin/imports">← Imports</Link><h1 className="text-xl font-semibold text-navy">New import</h1>
        <p className="text-sm text-muted">Imported rows are written through the same rules as the screens, under your own permissions and scope. Nothing is saved until you review the result and commit.</p></div>
      <Field label="1. What are you importing?" required>{(f) => <Select {...f} value={code} placeholder="Choose a template…" options={(tpls.data ?? []).map((t) => ({ value: t.code, label: t.name }))} onChange={(e) => setCode(e.target.value)} />}</Field>
      {code && def.isLoading && <Skeleton rows={3} />}{code && def.error && <ErrorState message={describeError(def.error)} />}
      {code && def.data && <UploadStep key={code} def={def.data} />}
    </section>
  )
}

function UploadStep({ def }: { def: TemplateDef }) {
  const nav = useNavigate(); const { notify } = useToast()
  const [file, setFile] = useState<File | null>(null); const [hash, setHash] = useState(''); const [table, setTable] = useState<RawTable | null>(null); const [mapping, setMapping] = useState<Mapping>({})
  const [dup, setDup] = useState('skip'); const [busy, setBusy] = useState(false); const [error, setError] = useState('')
  const guide = useMemo(() => templateGuide(def.columns), [def])
  async function load(f: File, sheet?: string) {
    setError(''); setTable(null)
    try {
      if (f.size > MAX_BYTES) throw new Error('The file is larger than 10 MB')
      const buf = await f.arrayBuffer(); setHash(await sha256Hex(buf))
      const isX = /\.xlsx$/i.test(f.name); if (!isX && !/\.csv$/i.test(f.name)) throw new Error('Choose a .csv or .xlsx file')
      const t = isX ? await parseXlsx(new Blob([buf]), sheet) : parseCsv(new TextDecoder('utf-8').decode(buf))
      if (t.headers.length === 0 || t.rows.length === 0) throw new Error('The file has no data rows')
      if (t.rows.length > def.max_rows) throw new Error(`The file has ${t.rows.length} rows; this template accepts at most ${def.max_rows} per file`)
      setTable(t); setMapping(autoMap(t.headers, def.columns))
    } catch (e) { setError((e as Error).message) }
  }
  const objects = useMemo(() => (table ? applyMapping(table.rows, def.columns, mapping) : []), [table, mapping, def])
  const missing = unmappedRequired(def.columns, mapping); const problems = useMemo(() => objects.reduce((n, r) => n + (quickCheck(r, def.columns).length > 0 ? 1 : 0), 0), [objects, def])
  async function submit() {
    if (!supabase || !file || !table) return; setBusy(true); setError('')
    try {
      const st = await supabase.rpc('import_stage', { p_template: def.code, p_file_name: file.name, p_file_hash: hash, p_rows: objects, p_mapping: mapping, p_on_duplicate: dup }); if (st.error) throw st.error
      const id = st.data as string; const v = await supabase.rpc('import_validate', { p_batch: id }); if (v.error) throw v.error
      notify('File validated. Review the result before committing.', 'ok'); nav(`/admin/imports/${id}`)
    } catch (e) { setError(describeError(e)) } finally { setBusy(false) }
  }
  return (
    <div className="space-y-5">
      <div className="space-y-2 rounded-lg border border-line bg-white p-4">
        <div className="flex flex-wrap items-center justify-between gap-2"><h2 className="text-base font-semibold">{def.name}</h2><Button variant="secondary" onClick={() => download(`${def.code}_template.csv`, templateCsv(def.columns))}>Download CSV template</Button></div>
        {def.description && <p className="text-sm text-muted">{def.description}</p>}
        <p className="text-sm">Duplicate check on: <strong>{def.key_columns.length ? def.key_columns.join(' + ') : 'none (every row is new)'}</strong> · up to {def.max_rows} rows per file</p>
        <div tabIndex={0} role="region" aria-label="Preview table, scrollable" className="overflow-x-auto"><table className="w-full text-left text-sm"><caption className="sr-only">Template columns</caption><thead><tr className="text-muted"><th className="py-1 pr-3">Column</th><th className="pr-3">Required</th><th className="pr-3">Type</th><th>Notes</th></tr></thead>
          <tbody>{guide.map((g) => <tr key={g.column} className="border-t border-line"><td className="py-1 pr-3 font-medium">{g.column}</td><td className="pr-3">{g.required ? 'Yes' : ''}</td><td className="pr-3">{g.type}</td><td className="text-muted">{g.help}</td></tr>)}</tbody></table></div>
      </div>
      <Field label="2. Choose the file (.csv or .xlsx)" required>{(f) => <input {...f} type="file" accept=".csv,.xlsx" className="block w-full text-sm" onChange={(e) => { const fl = e.target.files?.[0] ?? null; setFile(fl); if (fl) void load(fl) }} />}</Field>
      {error && <p role="alert" className="text-sm text-status-crit">{error}</p>}
      {table && file && (
        <>
          {table.sheets && table.sheets.length > 1 && <Field label="Sheet" help="Only the chosen sheet is imported">{(f) => <Select {...f} value={table.sheet ?? ''} options={table.sheets!.map((s) => ({ value: s.name, label: s.name }))} onChange={(e) => void load(file, e.target.value)} />}</Field>}
          <div className="space-y-2 rounded-lg border border-line bg-white p-4">
            <h2 className="text-base font-semibold">3. Match the columns</h2>
            <p className="text-sm text-muted">{table.rows.length} data row(s) found. Columns were matched by name; change any that are wrong.</p>
            <div className="grid gap-2 sm:grid-cols-2">{def.columns.map((c) => (
              <Field key={c.key} label={c.label + (c.required ? ' *' : '')}>{(f) => <Select {...f} value={mapping[c.key] === null || mapping[c.key] === undefined ? '' : String(mapping[c.key])} placeholder="— not in the file —" options={table.headers.map((h, i) => ({ value: String(i), label: h || `(column ${i + 1})` }))}
                onChange={(e) => setMapping((m) => ({ ...m, [c.key]: e.target.value === '' ? null : Number(e.target.value) }))} />}</Field>))}</div>
            {missing.length > 0 && <p role="alert" className="text-sm text-status-crit">Required column(s) not matched: {missing.map((c) => c.label).join(', ')}</p>}
            {problems > 0 && <p className="text-sm text-status-warn"><Badge tone="warn">{problems}</Badge> row(s) have problems that will be reported after validation; you can fix them in the file and upload again.</p>}
          </div>
          <Field label="4. If a record already exists">{(f) => <Select {...f} value={dup} options={DUP} onChange={(e) => setDup(e.target.value)} />}</Field>
          <div className="flex justify-end gap-2"><Button variant="secondary" onClick={() => nav('/admin/imports')}>Cancel</Button><Button disabled={missing.length > 0} loading={busy} onClick={() => void submit()}>Upload & validate</Button></div>
        </>)}
    </div>
  )
}
