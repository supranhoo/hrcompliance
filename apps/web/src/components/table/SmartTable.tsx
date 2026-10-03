import { useMemo, useState, type ReactNode } from 'react'
import { flexRender, getCoreRowModel, useReactTable, type ColumnDef, type RowSelectionState, type SortingState, type VisibilityState } from '@tanstack/react-table'
import { cx, Button, EmptyState, ErrorState, Skeleton } from '../ui'
import type { PageQuery } from '../../lib/query'

export type SavedView = { name: string; query: Omit<PageQuery, 'page'>; hidden: string[] }
/** Saved-view architecture: swap the store (localStorage now, a user_view table later) without touching tables. */
export interface SavedViewStore { list(tableId: string): SavedView[]; save(tableId: string, v: SavedView): void; remove(tableId: string, name: string): void }
export const localSavedViews: SavedViewStore = {
  list(id) { try { return JSON.parse(localStorage.getItem(`views:${id}`) ?? '[]') as SavedView[] } catch { return [] } },
  save(id, v) { try { localStorage.setItem(`views:${id}`, JSON.stringify([...this.list(id).filter((x) => x.name !== v.name), v])) } catch { /* storage unavailable */ } },
  remove(id, name) { try { localStorage.setItem(`views:${id}`, JSON.stringify(this.list(id).filter((x) => x.name !== name))) } catch { /* ignore */ } },
}

export type SmartTableProps<T> = {
  id: string
  columns: ColumnDef<T, unknown>[]
  data: T[]
  total: number
  query: PageQuery
  onQueryChange: (q: PageQuery) => void
  isLoading?: boolean
  error?: Error | null
  onRetry?: () => void
  searchPlaceholder?: string
  toolbar?: ReactNode                       // extra filter controls
  getRowId: (row: T) => string
  onRowClick?: (row: T) => void              // quick view
  selectable?: boolean
  onSelectionChange?: (rows: T[]) => void
  onExport?: (q: PageQuery) => void | Promise<void>   // export hook: caller re-queries server-side with the same filters
  emptyTitle?: string
  emptyDescription?: string
}

/** Controlled, fully server-driven table: parent owns `query`; this component never sorts/filters/paginates data itself. */
export function SmartTable<T>(p: SmartTableProps<T>) {
  const [visibility, setVisibility] = useState<VisibilityState>({})
  const [selection, setSelection] = useState<RowSelectionState>({})
  const [colsOpen, setColsOpen] = useState(false)
  const sorting: SortingState = p.query.sort ? [{ id: p.query.sort.id, desc: p.query.sort.desc }] : []
  const pageCount = Math.max(1, Math.ceil(p.total / p.query.pageSize))

  const columns = useMemo<ColumnDef<T, unknown>[]>(() => p.selectable ? [{
    id: '_select', enableSorting: false, enableHiding: false,
    header: ({ table }) => <input type="checkbox" aria-label="Select all rows on this page" checked={table.getIsAllPageRowsSelected()} onChange={table.getToggleAllPageRowsSelectedHandler()} />,
    cell: ({ row }) => <input type="checkbox" aria-label="Select row" checked={row.getIsSelected()} onClick={(e) => e.stopPropagation()} onChange={row.getToggleSelectedHandler()} />,
  }, ...p.columns] : p.columns, [p.columns, p.selectable])

  // TanStack Table returns unmemoisable functions; this is the documented usage and the component does not rely on React Compiler memoisation.
  // eslint-disable-next-line react-hooks/incompatible-library
  const table = useReactTable({
    data: p.data, columns, getRowId: p.getRowId, getCoreRowModel: getCoreRowModel(),
    manualPagination: true, manualSorting: true, manualFiltering: true, pageCount,
    state: { sorting, columnVisibility: visibility, rowSelection: selection },
    enableRowSelection: !!p.selectable,
    onColumnVisibilityChange: setVisibility,
    onRowSelectionChange: (u) => {
      const next = typeof u === 'function' ? u(selection) : u
      setSelection(next); p.onSelectionChange?.(p.data.filter((r) => next[p.getRowId(r)]))
    },
    onSortingChange: (u) => {
      const next = typeof u === 'function' ? u(sorting) : u
      p.onQueryChange({ ...p.query, page: 0, sort: next[0] ? { id: next[0].id, desc: next[0].desc } : null })
    },
  })

  const first = p.total === 0 ? 0 : p.query.page * p.query.pageSize + 1
  const last = Math.min(p.total, (p.query.page + 1) * p.query.pageSize)

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <input type="search" aria-label="Search" placeholder={p.searchPlaceholder ?? 'Search…'} defaultValue={p.query.search}
          onChange={(e) => p.onQueryChange({ ...p.query, page: 0, search: e.target.value })}
          className="w-full max-w-xs rounded border border-line bg-white px-3 py-1.5 text-sm focus-visible:outline-2 focus-visible:outline-blue" />
        {p.toolbar}
        <div className="relative ml-auto flex gap-2">
          {p.onExport && <Button variant="secondary" onClick={() => void p.onExport?.(p.query)}>Export</Button>}
          <Button variant="secondary" aria-expanded={colsOpen} onClick={() => setColsOpen((o) => !o)}>Columns</Button>
          {colsOpen && (
            <fieldset className="absolute right-0 top-9 z-20 w-48 rounded border border-line bg-white p-2 shadow-lg">
              <legend className="sr-only">Visible columns</legend>
              {table.getAllLeafColumns().filter((c) => c.getCanHide()).map((c) => (
                <label key={c.id} className="flex items-center gap-2 px-1 py-0.5 text-sm"><input type="checkbox" checked={c.getIsVisible()} onChange={c.getToggleVisibilityHandler()} />{typeof c.columnDef.header === 'string' ? c.columnDef.header : c.id}</label>
              ))}
            </fieldset>
          )}
        </div>
      </div>

      {p.error ? <ErrorState message={p.error.message} onRetry={p.onRetry} /> : (
        <div className="max-h-[70vh] overflow-auto rounded-lg border border-line bg-white">
          <table className="w-full border-collapse text-left text-sm">
            <thead className="sticky top-0 z-10 bg-canvas text-xs uppercase tracking-wide text-muted">
              {table.getHeaderGroups().map((hg) => (
                <tr key={hg.id}>
                  {hg.headers.map((h) => {
                    const dir = h.column.getIsSorted()
                    return (
                      <th key={h.id} scope="col" aria-sort={dir === 'asc' ? 'ascending' : dir === 'desc' ? 'descending' : undefined} className="whitespace-nowrap border-b border-line px-3 py-2 font-medium">
                        {h.isPlaceholder ? null : h.column.getCanSort()
                          ? <button type="button" onClick={h.column.getToggleSortingHandler()} className="inline-flex items-center gap-1 hover:text-ink">{flexRender(h.column.columnDef.header, h.getContext())}<span aria-hidden>{dir === 'asc' ? '▲' : dir === 'desc' ? '▼' : ''}</span></button>
                          : flexRender(h.column.columnDef.header, h.getContext())}
                      </th>
                    )
                  })}
                </tr>
              ))}
            </thead>
            <tbody>
              {p.isLoading && <tr><td colSpan={columns.length} className="p-4"><Skeleton rows={5} /></td></tr>}
              {!p.isLoading && table.getRowModel().rows.map((r) => (
                <tr key={r.id} data-state={r.getIsSelected() ? 'selected' : undefined} tabIndex={p.onRowClick ? 0 : undefined}
                  onClick={() => p.onRowClick?.(r.original)} onKeyDown={(e) => { if (p.onRowClick && e.key === 'Enter') p.onRowClick(r.original) }}
                  className={cx('border-b border-line last:border-0', p.onRowClick && 'cursor-pointer hover:bg-canvas focus-visible:bg-canvas', r.getIsSelected() && 'bg-blue/5')}>
                  {r.getVisibleCells().map((c) => <td key={c.id} className="whitespace-nowrap px-3 py-2">{flexRender(c.column.columnDef.cell, c.getContext())}</td>)}
                </tr>
              ))}
            </tbody>
          </table>
          {!p.isLoading && p.data.length === 0 && <div className="p-4"><EmptyState title={p.emptyTitle ?? 'No records'} description={p.emptyDescription ?? 'Nothing matches the current search and filters.'} /></div>}
        </div>
      )}

      <div className="flex flex-wrap items-center justify-between gap-2 text-sm text-muted">
        <span aria-live="polite">{p.total === 0 ? '0 records' : `${first}–${last} of ${p.total}`}</span>
        <div className="flex items-center gap-2">
          <select aria-label="Rows per page" value={p.query.pageSize} onChange={(e) => p.onQueryChange({ ...p.query, page: 0, pageSize: Number(e.target.value) })} className="rounded border border-line bg-white px-2 py-1">
            {[10, 25, 50, 100].map((n) => <option key={n} value={n}>{n}</option>)}
          </select>
          <Button variant="secondary" disabled={p.query.page === 0} onClick={() => p.onQueryChange({ ...p.query, page: p.query.page - 1 })}>Previous</Button>
          <span>Page {p.query.page + 1} of {pageCount}</span>
          <Button variant="secondary" disabled={p.query.page + 1 >= pageCount} onClick={() => p.onQueryChange({ ...p.query, page: p.query.page + 1 })}>Next</Button>
        </div>
      </div>
    </div>
  )
}
