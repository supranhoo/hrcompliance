import { useEffect, useState, type ReactNode } from 'react'
import { useSearchParams } from 'react-router-dom'
import type { ColumnDef } from '@tanstack/react-table'
import { SmartTable } from './SmartTable'
import { Button, Drawer, Select, type Option } from '../ui'
import { useServerTable } from '../../hooks/useServerTable'
import { useLovOptions, useStatusOptions } from '../../hooks/useLookups'
import { filtersFromSearch } from '../../lib/urlFilters'
import { useLookup } from '../../admin/lookups'
import type { Lookup } from '../../admin/spec'
import type { FilterValue, PageQuery } from '../../lib/query'

export type FilterDef = { key: string; label: string; options?: Option[]; lov?: string; statusModule?: string; lookup?: Lookup }
export type Derived = { filters: Record<string, FilterValue>; ranges?: PageQuery['ranges'] }

function FilterSelect({ def, value, onChange }: { def: FilterDef; value: string; onChange: (v: string) => void }) {
  const lov = useLovOptions(def.lov); const st = useStatusOptions(def.statusModule); const look = useLookup(def.lookup)
  const options = def.options ?? lov.data ?? st.data ?? look.data ?? []
  const withCurrent = value && !options.some((o) => o.value === value) ? [...options, { value, label: value }] : options   // a drill-down value not in the list stays visible
  return <div className="w-44"><Select aria-label={def.label} value={value} placeholder={`${def.label}: all`} options={withCurrent} onChange={(e) => onChange(e.target.value)} /></div>
}

export type RegisterProps<T> = {
  id: string; title: string; table: string; select: string
  columns: ColumnDef<T, unknown>[]; getRowId: (r: T) => string
  searchColumns: string[]; defaultSort: NonNullable<PageQuery['sort']>
  filterDefs: FilterDef[]
  /** URL-only drill-down keys (shown as removable chips), e.g. location_code, due_within */
  extraKeys?: string[]
  derive?: (active: Record<string, string>) => Derived
  quickViewTitle?: (r: T) => string
  renderQuickView?: (r: T, close: () => void) => ReactNode
  searchPlaceholder?: string
  /** Buttons shown next to the page title (e.g. "New …"). */
  actions?: ReactNode
}

/** Generic register: URL is the single source of filter state; every query is a server page; rows open a side-panel quick view. */
export function Register<T>(p: RegisterProps<T>) {
  const [params, setParams] = useSearchParams()
  const keys = [...p.filterDefs.map((f) => f.key), ...(p.extraKeys ?? []), 'q']
  const active = filtersFromSearch(params.toString(), keys)
  const derived: Derived = p.derive ? p.derive(active) : { filters: Object.fromEntries(Object.entries(active).filter(([k]) => k !== 'q')) }
  const t = useServerTable<T>(p.table, p.select, { searchColumns: p.searchColumns, sort: p.defaultSort, filters: derived.filters, ranges: derived.ranges, initialSearch: active.q })
  const [selected, setSelected] = useState<T | null>(null)
  useEffect(() => { document.title = `${p.title} · BFCL HR Compliance` }, [p.title])

  const setFilter = (k: string, v: string) => { const n = new URLSearchParams(params); if (v) n.set(k, v); else n.delete(k); setParams(n, { replace: true }) }
  const chips = Object.entries(active).filter(([k]) => k !== 'q' && !p.filterDefs.some((f) => f.key === k))
  const anyActive = Object.keys(active).some((k) => k !== 'q')

  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2"><h1 className="text-xl font-semibold text-navy">{p.title}</h1>{p.actions}</div>
      <SmartTable<T> id={p.id} columns={p.columns} data={t.rows} total={t.total} query={t.query} onQueryChange={t.setQuery}
        isLoading={t.isLoading} error={t.error} onRetry={() => void t.refetch()} getRowId={p.getRowId} onRowClick={p.renderQuickView ? setSelected : undefined}
        searchPlaceholder={p.searchPlaceholder}
        toolbar={<>
          {p.filterDefs.map((d) => <FilterSelect key={d.key} def={d} value={active[d.key] ?? ''} onChange={(v) => setFilter(d.key, v)} />)}
          {chips.map(([k, v]) => <button key={k} type="button" onClick={() => setFilter(k, '')} aria-label={`Remove filter ${k}`} className="rounded-full bg-blue/10 px-2 py-1 text-xs text-blue hover:bg-blue/20">{k.replace(/_/g, ' ')}: {v} ✕</button>)}
          {anyActive && <Button variant="ghost" onClick={() => setParams(new URLSearchParams(), { replace: true })}>Clear filters</Button>}
        </>}
        emptyTitle={`No ${p.title.toLowerCase()} match`} />
      {p.renderQuickView && (
        <Drawer open={!!selected} onClose={() => setSelected(null)} title={selected && p.quickViewTitle ? p.quickViewTitle(selected) : p.title}>
          {selected && p.renderQuickView(selected, () => setSelected(null))}
        </Drawer>
      )}
    </section>
  )
}
