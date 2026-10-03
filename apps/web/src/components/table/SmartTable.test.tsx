import { fireEvent, render, screen } from '@testing-library/react'
import { vi } from 'vitest'
import type { ColumnDef } from '@tanstack/react-table'
import { SmartTable } from './SmartTable'
import type { PageQuery } from '../../lib/query'

type Row = { id: string; name: string }
const columns: ColumnDef<Row, unknown>[] = [{ accessorKey: 'name', header: 'Name' }, { accessorKey: 'id', header: 'Code' }]
const base: PageQuery = { page: 0, pageSize: 10, sort: null, search: '' }
const rows: Row[] = [{ id: 'A1', name: 'Alpha' }, { id: 'B2', name: 'Beta' }]
const setup = (over: Partial<Parameters<typeof SmartTable<Row>>[0]> = {}) => {
  const onQueryChange = vi.fn()
  render(<SmartTable<Row> id="t" columns={columns} data={rows} total={95} query={base} onQueryChange={onQueryChange} getRowId={(r) => r.id} {...over} />)
  return { onQueryChange }
}

describe('SmartTable (server-driven)', () => {
  it('renders only the rows it was given and reports server totals', () => {
    setup()
    expect(screen.getAllByRole('row')).toHaveLength(3) // header + 2 rows; never slices or filters locally
    expect(screen.getByText('1–10 of 95')).toBeInTheDocument()
    expect(screen.getByText('Page 1 of 10')).toBeInTheDocument()
  })
  it('asks the parent for the next page instead of paging locally', () => {
    const { onQueryChange } = setup()
    fireEvent.click(screen.getByText('Next'))
    expect(onQueryChange).toHaveBeenCalledWith({ ...base, page: 1 })
    expect(screen.getByText('Previous')).toBeDisabled()
  })
  it('sort header click requests server sort and resets to page 0', () => {
    const { onQueryChange } = setup({ query: { ...base, page: 3 } })
    fireEvent.click(screen.getByRole('button', { name: /Name/ }))
    expect(onQueryChange).toHaveBeenCalledWith(expect.objectContaining({ page: 0, sort: { id: 'name', desc: false } }))
  })
  it('search and page-size changes reset to page 0', () => {
    const { onQueryChange } = setup({ query: { ...base, page: 2 } })
    fireEvent.change(screen.getByLabelText('Search'), { target: { value: 'al' } })
    expect(onQueryChange).toHaveBeenLastCalledWith(expect.objectContaining({ page: 0, search: 'al' }))
    fireEvent.change(screen.getByLabelText('Rows per page'), { target: { value: '50' } })
    expect(onQueryChange).toHaveBeenLastCalledWith(expect.objectContaining({ page: 0, pageSize: 50 }))
  })
  it('column visibility toggle hides a column', () => {
    setup()
    fireEvent.click(screen.getByText('Columns'))
    fireEvent.click(screen.getByLabelText('Code'))
    expect(screen.queryByRole('columnheader', { name: 'Code' })).toBeNull()
  })
  it('row click opens quick view; selection reports selected rows', () => {
    const onRowClick = vi.fn(), onSel = vi.fn()
    setup({ onRowClick, selectable: true, onSelectionChange: onSel })
    fireEvent.click(screen.getAllByLabelText('Select row')[1])
    expect(onSel).toHaveBeenCalledWith([rows[1]]); expect(onRowClick).not.toHaveBeenCalled()
    fireEvent.click(screen.getByText('Alpha')); expect(onRowClick).toHaveBeenCalledWith(rows[0])
  })
  it('shows loading, empty and error states', () => {
    const { unmount } = render(<SmartTable<Row> id="t" columns={columns} data={[]} total={0} query={base} onQueryChange={() => {}} getRowId={(r) => r.id} isLoading />)
    expect(screen.getByRole('status', { name: 'Loading' })).toBeInTheDocument(); unmount()
    const e = render(<SmartTable<Row> id="t" columns={columns} data={[]} total={0} query={base} onQueryChange={() => {}} getRowId={(r) => r.id} emptyTitle="No users" />)
    expect(screen.getByText('No users')).toBeInTheDocument(); e.unmount()
    render(<SmartTable<Row> id="t" columns={columns} data={[]} total={0} query={base} onQueryChange={() => {}} getRowId={(r) => r.id} error={new Error('denied')} onRetry={() => {}} />)
    expect(screen.getByRole('alert')).toHaveTextContent('denied')
  })
  it('export hook receives the active server query', () => {
    const onExport = vi.fn()
    setup({ onExport, query: { ...base, search: 'x' } })
    fireEvent.click(screen.getByText('Export'))
    expect(onExport).toHaveBeenCalledWith(expect.objectContaining({ search: 'x' }))
  })
})
