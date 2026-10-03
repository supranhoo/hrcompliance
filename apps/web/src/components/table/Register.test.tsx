import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ColumnDef } from '@tanstack/react-table'

const table = vi.hoisted(() => ({ calls: [] as unknown[][], rows: [{ id: 'r1', name: 'Alpha' }] }))
vi.mock('../../hooks/useServerTable', () => ({ useServerTable: (...a: unknown[]) => { table.calls.push(a); return { query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: table.rows, total: table.rows.length, isLoading: false, error: null, refetch: vi.fn() } } }))
vi.mock('../../hooks/useLookups', () => ({ useLovOptions: (s?: string) => ({ data: s === 'RISK' ? [{ value: 'high', label: 'High' }, { value: 'low', label: 'Low' }] : undefined }), useStatusOptions: () => ({ data: undefined }) }))
vi.mock('../../admin/lookups', () => ({ useLookup: (l?: { table: string }) => ({ data: l?.table === 'module_definition' ? [{ value: 'compliance', label: 'Compliance' }] : undefined }) }))
import { Register } from './Register'

type Row = { id: string; name: string }
const cols: ColumnDef<Row, unknown>[] = [{ accessorKey: 'name', header: 'Name' }]
const Loc = () => { const l = useLocation(); return <output data-testid="loc">{l.pathname + l.search}</output> }
const setup = (url: string) => render(<MemoryRouter initialEntries={[url]}><Register<Row> id="t" title="Things" table="v_things" select="id,name" columns={cols} getRowId={(r) => r.id} searchColumns={['name']} defaultSort={{ id: 'name', desc: false }}
  filterDefs={[{ key: 'risk_level', label: 'Risk', lov: 'RISK' }, { key: 'due_state', label: 'State', options: [{ value: 'overdue', label: 'Overdue' }] }]} extraKeys={['location_code']} renderQuickView={(r) => <p>detail of {r.name}</p>} quickViewTitle={(r) => r.name} /><Loc /></MemoryRouter>)

describe('Register', () => {
  beforeEach(() => { table.calls.length = 0 })
  it('reads filters from the URL and sends only whitelisted keys to the server query', () => {
    setup('/things?due_state=overdue&location_code=L-E1&evil=1')
    const opts = table.calls.at(-1)![2] as { filters: Record<string, string> }
    expect(opts.filters).toEqual({ due_state: 'overdue', location_code: 'L-E1' })
  })
  it('selecting a filter writes it to the URL (shareable drill-down) and clearing removes it', () => {
    setup('/things')
    fireEvent.change(screen.getByLabelText('Risk'), { target: { value: 'high' } })
    expect(screen.getByTestId('loc')).toHaveTextContent('/things?risk_level=high')
    fireEvent.change(screen.getByLabelText('Risk'), { target: { value: '' } })
    expect(screen.getByTestId('loc')).toHaveTextContent(/^\/things$/)
  })
  it('options come from the LOV hook (database), not a hardcoded list', () => {
    setup('/things'); const opts = Array.from((screen.getByLabelText('Risk') as HTMLSelectElement).options).map((o) => o.value)
    expect(opts).toEqual(['', 'high', 'low'])
  })
  it('URL-only drill-down filters show as removable chips', () => {
    setup('/things?location_code=L-E1')
    fireEvent.click(screen.getByRole('button', { name: 'Remove filter location_code' }))
    expect(screen.getByTestId('loc')).toHaveTextContent(/^\/things$/)
  })
  it('a drill-down value missing from the option list is still shown and selectable', () => {
    setup('/things?risk_level=critical'); expect((screen.getByLabelText('Risk') as HTMLSelectElement).value).toBe('critical')
  })
  it('Clear filters resets everything', () => {
    setup('/things?risk_level=high&due_state=overdue'); fireEvent.click(screen.getByText('Clear filters'))
    expect(screen.getByTestId('loc')).toHaveTextContent(/^\/things$/)
  })
  it('a filter can take its options from a database lookup (no hardcoded list)', () => {
    render(<MemoryRouter initialEntries={['/things']}><Register<Row> id="t2" title="Things" table="v_things" select="id,name" columns={cols} getRowId={(r) => r.id} searchColumns={['name']} defaultSort={{ id: 'name', desc: false }} filterDefs={[{ key: 'module', label: 'Module', lookup: { table: 'module_definition', value: 'code', label: 'name' } }]} /></MemoryRouter>)
    expect(Array.from((screen.getByLabelText('Module') as HTMLSelectElement).options).map((o) => o.value)).toEqual(['', 'compliance'])
  })
  it('row click opens the quick view panel', () => {
    setup('/things'); fireEvent.click(screen.getByText('Alpha')); expect(screen.getByText('detail of Alpha')).toBeInTheDocument()
  })
})
