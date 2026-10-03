import { fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { vi } from 'vitest'
import { AuditHistory, Badge, ConfirmDialog, EmptyState, ErrorState, EvidencePlaceholder, Field, Input, KpiCard, MultiSelect, RiskBadge, StatusBadge, Tabs, Timeline } from '.'

describe('forms', () => {
  it('Field wires label, error and aria attributes', () => {
    render(<Field label="Email" error="Required" required>{(p) => <Input {...p} />}</Field>)
    const input = screen.getByLabelText(/Email/)
    expect(input).toHaveAttribute('aria-invalid', 'true')
    expect(input).toHaveAccessibleDescription('Required')
    expect(screen.getByRole('alert')).toHaveTextContent('Required')
  })
  it('MultiSelect toggles values and summarises the selection', () => {
    const Harness = () => { const [v, setV] = useState<string[]>([]); return <MultiSelect label="Roles" value={v} onChange={setV} options={[{ value: 'a', label: 'Alpha' }, { value: 'b', label: 'Beta' }]} /> }
    render(<Harness />)
    fireEvent.click(screen.getByRole('button', { name: 'Roles' }))
    fireEvent.click(screen.getByLabelText('Alpha')); fireEvent.click(screen.getByLabelText('Beta'))
    expect(screen.getByRole('button', { name: 'Roles' })).toHaveTextContent('Alpha, Beta')
    fireEvent.click(screen.getByLabelText('Alpha'))
    expect(screen.getByRole('button', { name: 'Roles' })).toHaveTextContent('Beta')
  })
})

describe('display', () => {
  it('badges always render a text label', () => {
    render(<><StatusBadge label="Overdue" color="red" /><RiskBadge level="High" /><Badge tone="ok">Done</Badge></>)
    expect(screen.getByText('Overdue')).toBeInTheDocument(); expect(screen.getByText('High')).toBeInTheDocument()
  })
  it('KpiCard is a button only when it drills down', () => {
    const onClick = vi.fn()
    const { rerender } = render(<KpiCard label="Overdue" value={3} onClick={onClick} />)
    fireEvent.click(screen.getByRole('button')); expect(onClick).toHaveBeenCalled()
    rerender(<KpiCard label="Overdue" value={3} />); expect(screen.queryByRole('button')).toBeNull()
  })
  it('empty and error states', () => {
    const retry = vi.fn()
    render(<><EmptyState title="Nothing" /><ErrorState message="boom" onRetry={retry} /></>)
    fireEvent.click(screen.getByText('Retry')); expect(retry).toHaveBeenCalled()
    expect(screen.getByRole('alert')).toHaveTextContent('boom')
  })
  it('Timeline and AuditHistory render field-level changes', () => {
    render(<><Timeline items={[]} /><AuditHistory entries={[{ id: 1, at: '2026-01-01T00:00:00Z', action: 'UPDATE', actor: 'amit', changed_fields: ['name'], old_data: { name: 'A' }, new_data: { name: 'B' }, reason: 'typo' }]} /></>)
    expect(screen.getByText('No activity yet.')).toBeInTheDocument()
    expect(screen.getByText('Updated name')).toBeInTheDocument()
    expect(screen.getByText(/name: A → B/)).toBeInTheDocument()
    expect(screen.getByText(/Reason: typo/)).toBeInTheDocument()
  })
  it('EvidencePlaceholder reflects adapter state', () => {
    render(<EvidencePlaceholder storageState="NOT_CONFIGURED" />)
    expect(screen.getByText(/NOT CONFIGURED/)).toBeInTheDocument()
  })
})

describe('navigation + overlay', () => {
  it('Tabs switch with click and arrow keys', () => {
    render(<Tabs tabs={[{ id: 'a', label: 'One', content: <p>first</p> }, { id: 'b', label: 'Two', content: <p>second</p> }]} />)
    expect(screen.getByText('first')).toBeInTheDocument()
    fireEvent.keyDown(screen.getByRole('tablist'), { key: 'ArrowRight' })
    expect(screen.getByText('second')).toBeInTheDocument(); expect(screen.queryByText('first')).toBeNull()
    fireEvent.click(screen.getByRole('tab', { name: 'One' })); expect(screen.getByText('first')).toBeInTheDocument()
  })
  it('ConfirmDialog confirms and cancels', () => {
    const ok = vi.fn(), no = vi.fn()
    render(<ConfirmDialog open title="Delete?" message="Sure?" confirmLabel="Yes" onConfirm={ok} onCancel={no} />)
    fireEvent.click(screen.getByText('Yes')); expect(ok).toHaveBeenCalled()
    fireEvent.click(screen.getByText('Cancel')); expect(no).toHaveBeenCalled()
  })
})
