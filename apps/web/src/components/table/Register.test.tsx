import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ColumnDef } from '@tanstack/react-table'

const table = vi.hoisted(() => ({ calls: [] as unknown[][], rows: [{ id: 'r1', name: 'Alpha' }], perms: new Set<string>(), rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, rpcError: null as null | { message: string }, downloads: [] as Array<{ name: string; csv: string }> }))
vi.mock('../../hooks/useServerTable', () => ({ useServerTable: (...a: unknown[]) => { table.calls.push(a); return { query: { page: 0, pageSize: 25, sort: null, search: '' }, setQuery: vi.fn(), rows: table.rows, total: table.rows.length, isLoading: false, error: null, refetch: vi.fn() } } }))
vi.mock('../../hooks/useLookups', () => ({ useLovOptions: (s?: string) => ({ data: s === 'RISK' ? [{ value: 'high', label: 'High' }, { value: 'low', label: 'Low' }] : undefined }), useStatusOptions: () => ({ data: undefined }) }))
vi.mock('../../admin/lookups', () => ({ useLookup: (l?: { table: string }) => ({ data: l?.table === 'module_definition' ? [{ value: 'compliance', label: 'Compliance' }] : undefined }) }))
vi.mock('../../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: table.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../../app/Toasts', () => ({ useToast: () => ({ notify: vi.fn() }) }))
vi.mock('../../lib/supabase', () => {
  const builder = () => { const b: Record<string, unknown> = {}; b.select = () => b; b.order = () => b; b.eq = () => b; b.or = () => b; b.range = async () => ({ data: [{ name: '=cmd()' }, { name: 'Beta' }], error: null, count: 2 }); return b }
  return { supabase: { from: builder, rpc: async (fn: string, args: Record<string, unknown>) => { table.rpc.push({ fn, args }); return { error: table.rpcError } } }, appEnv: 'test' }
})
vi.mock('../../lib/exportCsv', async (orig) => ({ ...(await orig<typeof import('../../lib/exportCsv')>()), downloadCsv: (name: string, csv: string) => { table.downloads.push({ name, csv }) } }))
import { Register } from './Register'

type Row = { id: string; name: string }
const cols: ColumnDef<Row, unknown>[] = [{ accessorKey: 'name', header: 'Name' }]
const Loc = () => { const l = useLocation(); return <output data-testid="loc">{l.pathname + l.search}</output> }
const setup = (url: string) => render(<MemoryRouter initialEntries={[url]}><Register<Row> id="t" title="Things" table="v_things" select="id,name" columns={cols} getRowId={(r) => r.id} searchColumns={['name']} defaultSort={{ id: 'name', desc: false }}
  filterDefs={[{ key: 'risk_level', label: 'Risk', lov: 'RISK' }, { key: 'due_state', label: 'State', options: [{ value: 'overdue', label: 'Overdue' }] }]} extraKeys={['location_code']} renderQuickView={(r) => <p>detail of {r.name}</p>} quickViewTitle={(r) => r.name} /><Loc /></MemoryRouter>)

describe('Register', () => {
  beforeEach(() => { table.calls.length = 0; table.perms = new Set(); table.rpc.length = 0; table.rpcError = null; table.downloads.length = 0 })
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
  it('Export is offered only with report.export', () => { setup('/things'); expect(screen.queryByRole('button', { name: 'Export' })).toBeNull(); })
  it('export logs first, then downloads a CSV with formulas neutralised', async () => {
    table.perms = new Set(['report.export']); setup('/things?due_state=overdue'); fireEvent.click(screen.getByRole('button', { name: 'Export' }))
    await vi.waitFor(() => expect(table.downloads).toHaveLength(1))
    expect(table.rpc[0]).toEqual({ fn: 'export_record', args: { p_register: 't', p_filters: { due_state: 'overdue' }, p_row_count: 2, p_limit_reached: false } })
    expect(table.downloads[0].csv).toContain("'=cmd()"); expect(table.downloads[0].csv.startsWith('\uFEFFName')).toBe(true); expect(table.downloads[0].name).toMatch(/^t-\d{4}-\d{2}-\d{2}\.csv$/)
  })
  it('if the export cannot be logged nothing is downloaded (fail closed)', async () => {
    table.perms = new Set(['report.export']); table.rpcError = { message: 'denied' }; setup('/things'); fireEvent.click(screen.getByRole('button', { name: 'Export' }))
    await vi.waitFor(() => expect(table.rpc).toHaveLength(1)); await new Promise((r) => setTimeout(r, 30)); expect(table.downloads).toHaveLength(0)
  })
})
