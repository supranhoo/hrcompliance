import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => ({
  perms: new Set<string>(['import.manage', 'import.read']), rpc: [] as Array<{ fn: string; args: Record<string, unknown> }>, rpcError: null as null | { code?: string; message: string },
  batch: null as Record<string, unknown> | null, rows: [] as Array<Record<string, unknown>>,
}))
const DEF = { code: 'department', name: 'Departments', description: 'Departments of the organisation', key_columns: ['code'], max_rows: 3, columns: [
  { key: 'code', label: 'Code', type: 'text', required: true, max: 40 }, { key: 'name', label: 'Name', type: 'text', required: true }, { key: 'is_active', label: 'Active', type: 'boolean' }] }
vi.mock('../../app/AuthProvider', () => ({ useAuth: () => ({ access: { permissions: h.perms, userId: 'u', email: 'a@b', fullName: null, scopeAll: true, roles: [] } }) }))
vi.mock('../../hooks/useLookups', () => ({ useLovOptions: () => ({ data: [] }), useStatusOptions: () => ({ data: [] }) }))
vi.mock('../lookups', () => ({ useLookup: () => ({ data: [] }) }))
vi.mock('../../lib/supabase', () => {
  const builder = (table: string) => { const c: Record<string, unknown> = {}
    c.select = () => c; c.eq = () => c; c.in = () => c; c.order = () => c
    c.range = async () => ({ data: h.rows, count: h.rows.length, error: null })
    c.maybeSingle = async () => ({ data: table === 'v_import_batch' ? h.batch : null, error: null })
    c.then = (res: (v: unknown) => void) => res({ data: table === 'import_template' ? [{ code: 'department', name: 'Departments', description: 'x', write_permission: 'master.write', is_active: true }] : [], error: null }); return c }
  return { supabase: { from: builder, rpc: async (fn: string, args: Record<string, unknown>) => {
    h.rpc.push({ fn, args })
    if (h.rpcError && fn !== 'import_template_columns') return { data: null, error: h.rpcError }
    if (fn === 'import_template_columns') return { data: DEF, error: null }
    if (fn === 'import_stage') return { data: 'batch-1', error: null }
    if (fn === 'import_commit') return { data: { committed: 2, failed: 0, skipped: 0 }, error: null }
    return { data: {}, error: null } } }, appEnv: 'test' }
})
import { NewImportPage } from './NewImportPage'
import { ImportBatchPage } from './ImportBatchPage'
import { ToastProvider } from '../../app/Toasts'

const Loc = () => <output data-testid="loc">{useLocation().pathname}</output>
const wrap = (path: string) => render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><ToastProvider><MemoryRouter initialEntries={[path]}><Loc />
  <Routes><Route path="/admin/imports/new" element={<NewImportPage />} /><Route path="/admin/imports/:id" element={<ImportBatchPage />} /><Route path="/admin/imports" element={<p>history</p>} /></Routes></MemoryRouter></ToastProvider></QueryClientProvider>)
const csvFile = (text: string, name = 'depts.csv') => { const f = new File([text], name, { type: 'text/csv' }); if (!f.arrayBuffer) (f as unknown as { arrayBuffer: () => Promise<ArrayBuffer> }).arrayBuffer = async () => new TextEncoder().encode(text).buffer as ArrayBuffer; return f }
beforeEach(() => { h.rpc.length = 0; h.rpcError = null; h.perms = new Set(['import.manage', 'import.read']); h.rows = [] })

describe('New import', () => {
  it('lists templates from the database and shows the template guide with a download', async () => {
    wrap('/admin/imports/new'); fireEvent.change(await screen.findByLabelText(/What are you importing/), { target: { value: 'department' } })
    expect(await screen.findByRole('button', { name: 'Download CSV template' })).toBeInTheDocument(); expect(screen.getByText(/Duplicate check on:/)).toHaveTextContent('code'); expect(screen.getByRole('table', { name: 'Template columns' })).toHaveTextContent('Name')
  })
  it('reads the file, maps columns by header, stages and validates through the server, then opens the batch', async () => {
    wrap('/admin/imports/new'); fireEvent.change(await screen.findByLabelText(/What are you importing/), { target: { value: 'department' } })
    const input = await screen.findByLabelText(/Choose the file/); fireEvent.change(input, { target: { files: [csvFile('Code,Name,Active\r\nHR,Human Resources,yes\r\nFIN,Finance,no\r\n')] } })
    expect(await screen.findByText(/2 data row\(s\) found/)).toBeInTheDocument()
    expect(screen.getByLabelText('Code *')).toHaveValue('0'); expect(screen.getByLabelText('Name *')).toHaveValue('1')
    fireEvent.change(screen.getByLabelText(/If a record already exists/), { target: { value: 'update' } })
    fireEvent.click(screen.getByRole('button', { name: 'Upload & validate' }))
    await waitFor(() => expect(h.rpc.filter((r) => r.fn === 'import_validate')).toHaveLength(1))
    const stage = h.rpc.find((r) => r.fn === 'import_stage')!.args
    expect(stage).toMatchObject({ p_template: 'department', p_file_name: 'depts.csv', p_on_duplicate: 'update', p_rows: [{ code: 'HR', name: 'Human Resources', is_active: 'yes' }, { code: 'FIN', name: 'Finance', is_active: 'no' }] })
    expect(String(stage.p_file_hash)).toMatch(/^[0-9a-f]{64}$/); await waitFor(() => expect(screen.getByTestId('loc')).toHaveTextContent('/admin/imports/batch-1'))
  })
  it('refuses a file with a missing required column or too many rows, before anything is sent', async () => {
    wrap('/admin/imports/new'); fireEvent.change(await screen.findByLabelText(/What are you importing/), { target: { value: 'department' } })
    fireEvent.change(await screen.findByLabelText(/Choose the file/), { target: { files: [csvFile('Code,Colour\r\nHR,red\r\n')] } })
    expect(await screen.findByText(/Required column\(s\) not matched: Name/)).toBeInTheDocument(); expect(screen.getByRole('button', { name: 'Upload & validate' })).toBeDisabled()
    fireEvent.change(screen.getByLabelText(/^Name/), { target: { value: '1' } })       // mapping the wrong column to Name makes it submittable
    expect(screen.getByRole('button', { name: 'Upload & validate' })).toBeEnabled()
    fireEvent.change(screen.getByLabelText(/Choose the file/), { target: { files: [csvFile('Code,Name\r\na,A\r\nb,B\r\nc,C\r\nd,D\r\n', 'big.csv')] } })
    expect(await screen.findByText(/accepts at most 3 per file/)).toBeInTheDocument(); expect(h.rpc.filter((r) => r.fn === 'import_stage')).toHaveLength(0)
  })
  it('shows the server message when the same file was already uploaded', async () => {
    h.rpcError = { code: '23505', message: 'this file was already uploaded as batch IMP-2026-000001 (re-uploading the same file is refused; cancel that batch first if it was a mistake)' }
    wrap('/admin/imports/new'); fireEvent.change(await screen.findByLabelText(/What are you importing/), { target: { value: 'department' } })
    fireEvent.change(await screen.findByLabelText(/Choose the file/), { target: { files: [csvFile('Code,Name\r\nHR,Human Resources\r\n')] } }); await screen.findByText(/1 data row/)
    fireEvent.click(screen.getByRole('button', { name: 'Upload & validate' })); expect(await screen.findByText(/already uploaded as batch IMP-2026-000001/)).toBeInTheDocument()
  })
})

const batch = (o: Record<string, unknown> = {}) => ({ id: 'batch-1', batch_no: 'IMP-2026-000001', template_code: 'department', template_name: 'Departments', file_name: 'depts.csv', status: 'validated', on_duplicate: 'skip', total_rows: 3, valid_rows: 2, warning_rows: 0, error_rows: 1, skipped_rows: 0, committed_rows: 0, failed_rows: 0, created_at: '2026-10-03T10:00:00Z', created_by_email: 'a@b', cancel_reason: null, ...o })
describe('Import batch', () => {
  it('with errors: full commit is not offered; only the valid rows can be committed, after a confirmation', async () => {
    h.batch = batch(); h.rows = [{ row_no: 1, status: 'valid', action: 'insert', errors: [], warnings: [], raw: { code: 'HR', name: 'HR' }, target_id: null }, { row_no: 3, status: 'error', action: null, errors: [{ column: 'name', message: 'Name is required' }], warnings: [], raw: { code: 'X' }, target_id: null }]
    wrap('/admin/imports/batch-1'); expect(await screen.findByText(/1 row\(s\) have errors/)).toBeInTheDocument(); expect(screen.queryByRole('button', { name: /^Commit 2 record/ })).toBeNull()
    expect(await screen.findByText('Name is required')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /Commit the 2 valid row\(s\) only/ })); expect(screen.getByText(/1 row\(s\) with errors will NOT be imported/)).toBeInTheDocument(); expect(h.rpc.filter((r) => r.fn === 'import_commit')).toHaveLength(0)
    fireEvent.click(screen.getByRole('button', { name: 'Commit' })); await waitFor(() => expect(h.rpc.filter((r) => r.fn === 'import_commit')).toHaveLength(1))
    expect(h.rpc.find((r) => r.fn === 'import_commit')!.args).toEqual({ p_batch: 'batch-1', p_valid_only: true })
  })
  it('a clean batch commits everything (all-or-nothing)', async () => {
    h.batch = batch({ error_rows: 0, valid_rows: 3 }); wrap('/admin/imports/batch-1')
    fireEvent.click(await screen.findByRole('button', { name: 'Commit 3 record(s)' })); fireEvent.click(screen.getByRole('button', { name: 'Commit' }))
    await waitFor(() => expect(h.rpc.find((r) => r.fn === 'import_commit')?.args).toEqual({ p_batch: 'batch-1', p_valid_only: false }))
  })
  it('cancel needs a reason and calls the cancel function', async () => {
    h.batch = batch(); wrap('/admin/imports/batch-1'); fireEvent.click(await screen.findByRole('button', { name: 'Cancel this batch' }))
    const go = await screen.findByRole('button', { name: 'Cancel batch' }); expect(go).toBeDisabled(); fireEvent.change(screen.getByLabelText(/Reason/), { target: { value: 'wrong file' } }); fireEvent.click(go)
    await waitFor(() => expect(h.rpc.find((r) => r.fn === 'import_cancel')?.args).toEqual({ p_batch: 'batch-1', p_reason: 'wrong file' }))
  })
  it('a committed batch is read-only history; read-only users get no actions', async () => {
    h.batch = batch({ status: 'committed', committed_rows: 2 }); wrap('/admin/imports/batch-1'); await screen.findByText(/IMP-2026-000001/); expect(screen.queryByRole('button', { name: /Commit/ })).toBeNull(); expect(screen.queryByRole('button', { name: 'Cancel this batch' })).toBeNull()
  })
  it('read-only (import.read) users see the batch but cannot act', async () => { h.perms = new Set(['import.read']); h.batch = batch(); wrap('/admin/imports/batch-1'); await screen.findByText(/IMP-2026-000001/); expect(screen.queryByRole('button', { name: /Commit/ })).toBeNull() })
  it('a missing or foreign batch says so', async () => { h.batch = null; wrap('/admin/imports/nope'); expect(await screen.findByText('Batch not found')).toBeInTheDocument() })
})
