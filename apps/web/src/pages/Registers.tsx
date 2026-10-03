import type { ColumnDef } from '@tanstack/react-table'
import { Register, type Derived } from '../components/table/Register'
import { Badge } from '../components/ui'
import { dueStateBadge, evidenceBadge, expiryBadge, severityTone, titleCase } from '../lib/badges'
import { nextDaysRange } from '../lib/urlFilters'
import { ComplianceQuickView, EvidenceQuickView, ExceptionQuickView, LicenceQuickView, type ComplianceRow, type EvidenceReqRow, type ExceptionRow, type LicenceRow } from './quickviews'

const DUE_STATES = [{ value: 'overdue', label: 'Overdue' }, { value: 'due_soon', label: 'Due soon' }, { value: 'upcoming', label: 'Upcoming' }, { value: 'completed', label: 'Completed' }, { value: 'not_applicable', label: 'Not applicable' }]
const AGE_BUCKETS = ['0-7', '8-30', '31-90', '90+'].map((b) => ({ value: b, label: `${b} days` }))
const EXPIRY = ['expired', 'within_7', 'within_15', 'within_30', 'within_60', 'within_90', 'valid', 'no_expiry'].map((v) => ({ value: v, label: expiryBadge(v).label }))
const EVIDENCE_STATES = Object.entries(evidenceBadge).map(([value, b]) => ({ value, label: b.label }))
/** The database contract of each register: every column here must exist in the view (verified against real fixtures in lib/contract.test.ts). */
export const CONTRACT = {
  compliance: { table: 'v_compliance_instance', select: 'id,instance_no,compliance_code,compliance_name,location_code,location_name,period_start,period_end,due_date,status,due_state,risk_level,criticality,frequency,evidence_required,days_overdue,days_to_due', search: ['instance_no', 'compliance_code', 'compliance_name'], filters: ['due_state', 'status', 'risk_level', 'location_code'], sort: 'due_date' },
  exceptions: { table: 'v_exception', select: 'id,exception_no,category,severity,description,status,detected_at,due_date,age_days,age_bucket,target_breached,resolution,compliance_instance_id,licence_id,evidence_id', search: ['exception_no', 'description'], filters: ['severity', 'status', 'age_bucket', 'target_breached'], sort: 'detected_at' },
  licences: { table: 'v_licence_status', select: 'id,licence_no,licence_number,licence_type_name,expiry_date,days_to_expiry,expiry_category,renewal_status,risk_level,renewal_window_open,lifecycle_status', search: ['licence_no', 'licence_number', 'licence_type_name'], filters: ['expiry_category', 'renewal_status', 'renewal_window_open'], sort: 'expiry_date' },
  evidence: { table: 'v_evidence_requirement', select: 'compliance_instance_id,instance_no,document_type_name,evidence_state,evidence_no,version,expiry_date,due_date,is_mandatory', search: ['instance_no', 'document_type_name'], filters: ['evidence_state'], sort: 'due_date' },
} as const
const dateCell = (v: unknown) => (v ? String(v) : '—')

const complianceCols: ColumnDef<ComplianceRow, unknown>[] = [
  { accessorKey: 'instance_no', header: 'Number' },
  { accessorKey: 'compliance_name', header: 'Obligation', cell: (c) => <span><span className="font-medium">{c.row.original.compliance_code}</span> <span className="text-muted">{c.getValue<string>()}</span></span> },
  { accessorKey: 'location_code', header: 'Location' },
  { accessorKey: 'period_start', header: 'Period', cell: (c) => new Date(c.getValue<string>() + 'T00:00:00').toLocaleDateString(undefined, { month: 'short', year: 'numeric' }) },
  { accessorKey: 'due_date', header: 'Due' },
  { accessorKey: 'due_state', header: 'State', cell: (c) => { const b = dueStateBadge[c.getValue<string>()] ?? dueStateBadge.upcoming; return <Badge tone={b.tone}>{b.label}</Badge> } },
  { accessorKey: 'status', header: 'Status', cell: (c) => titleCase(c.getValue<string>()) },
  { accessorKey: 'risk_level', header: 'Risk', cell: (c) => <Badge tone={severityTone(c.getValue<string>())}>{titleCase(c.getValue<string>())}</Badge> },
]
export const complianceDerive = (a: Record<string, string>): Derived => {
  const { due_within, q, ...rest } = a; void q
  const filters: Derived['filters'] = { ...rest }
  if (due_within && /^\d{1,3}$/.test(due_within)) { filters.status = ['open', 'in_progress']; return { filters, ranges: { due_date: nextDaysRange(Number(due_within)) } } }
  return { filters }
}
export function CompliancePage() {
  return <Register<ComplianceRow> id="compliance" title="Compliance Register" table={CONTRACT.compliance.table}
    select={CONTRACT.compliance.select}
    columns={complianceCols} getRowId={(r) => r.id} searchColumns={[...CONTRACT.compliance.search]} defaultSort={{ id: 'due_date', desc: false }}
    filterDefs={[{ key: 'due_state', label: 'State', options: DUE_STATES }, { key: 'status', label: 'Status', statusModule: 'compliance' }, { key: 'risk_level', label: 'Risk', lov: 'RISK' }]}
    extraKeys={['location_code', 'due_within']} derive={complianceDerive} quickViewTitle={(r) => `${r.compliance_code} · ${r.location_code}`}
    renderQuickView={(r) => <ComplianceQuickView row={r} />} searchPlaceholder="Search number, code or name" />
}

const exceptionCols: ColumnDef<ExceptionRow, unknown>[] = [
  { accessorKey: 'exception_no', header: 'Number' },
  { accessorKey: 'severity', header: 'Severity', cell: (c) => <Badge tone={severityTone(c.getValue<string>())}>{titleCase(c.getValue<string>())}</Badge> },
  { accessorKey: 'category', header: 'Category', cell: (c) => titleCase(c.getValue<string>()) },
  { accessorKey: 'description', header: 'Description', cell: (c) => <span className="line-clamp-2 max-w-md whitespace-normal">{c.getValue<string>()}</span> },
  { accessorKey: 'status', header: 'Status', cell: (c) => titleCase(c.getValue<string>()) },
  { accessorKey: 'age_days', header: 'Age (days)' },
  { accessorKey: 'due_date', header: 'Target', cell: (c) => <span className={c.row.original.target_breached ? 'font-medium text-status-crit' : ''}>{dateCell(c.getValue())}</span> },
]
export const exceptionDerive = (a: Record<string, string>): Derived => {
  const { target_breached, status, ...rest } = a
  const filters: Derived['filters'] = { ...rest }
  if (status === 'open') filters.status = ['open', 'acknowledged']; else if (status) filters.status = status
  if (target_breached === 'true') { filters.target_breached = true; if (!status) filters.status = ['open', 'acknowledged'] }
  return { filters }
}
export function ExceptionsPage() {
  return <Register<ExceptionRow> id="exceptions" title="Exceptions" table={CONTRACT.exceptions.table}
    select={CONTRACT.exceptions.select}
    columns={exceptionCols} getRowId={(r) => r.id} searchColumns={[...CONTRACT.exceptions.search]} defaultSort={{ id: 'detected_at', desc: true }}
    filterDefs={[{ key: 'severity', label: 'Severity', lov: 'SEVERITY' }, { key: 'status', label: 'Status', statusModule: 'exception' }, { key: 'age_bucket', label: 'Age', options: AGE_BUCKETS }]}
    extraKeys={['target_breached']} derive={exceptionDerive} quickViewTitle={(r) => r.exception_no} renderQuickView={(r) => <ExceptionQuickView row={r} />} />
}

const licenceCols: ColumnDef<LicenceRow, unknown>[] = [
  { accessorKey: 'licence_no', header: 'Number' },
  { accessorKey: 'licence_type_name', header: 'Type' },
  { accessorKey: 'licence_number', header: 'Authority no.', cell: (c) => dateCell(c.getValue()) },
  { accessorKey: 'expiry_date', header: 'Expiry', cell: (c) => dateCell(c.getValue()) },
  { accessorKey: 'days_to_expiry', header: 'Days left', cell: (c) => (c.getValue<number | null>() ?? '—') },
  { accessorKey: 'expiry_category', header: 'State', cell: (c) => { const b = expiryBadge(c.getValue<string>()); return <Badge tone={b.tone}>{b.label}</Badge> } },
  { accessorKey: 'renewal_status', header: 'Renewal', cell: (c) => titleCase(c.getValue<string>()) },
]
export function LicencesPage() {
  return <Register<LicenceRow> id="licences" title="Licences & Registrations" table={CONTRACT.licences.table}
    select={CONTRACT.licences.select}
    columns={licenceCols} getRowId={(r) => r.id} searchColumns={[...CONTRACT.licences.search]} defaultSort={{ id: 'expiry_date', desc: false }}
    filterDefs={[{ key: 'expiry_category', label: 'Expiry', options: EXPIRY }, { key: 'renewal_status', label: 'Renewal', lov: 'LICENCE_RENEWAL_STATUS' }]}
    extraKeys={['renewal_window_open']} quickViewTitle={(r) => r.licence_no} renderQuickView={(r) => <LicenceQuickView row={r} />} />
}

const evidenceCols: ColumnDef<EvidenceReqRow, unknown>[] = [
  { accessorKey: 'instance_no', header: 'Obligation' },
  { accessorKey: 'document_type_name', header: 'Document' },
  { accessorKey: 'evidence_state', header: 'State', cell: (c) => { const b = evidenceBadge[c.getValue<string>()] ?? evidenceBadge.missing; return <Badge tone={b.tone}>{b.label}</Badge> } },
  { accessorKey: 'evidence_no', header: 'Evidence', cell: (c) => dateCell(c.getValue()) },
  { accessorKey: 'expiry_date', header: 'Expiry', cell: (c) => dateCell(c.getValue()) },
  { accessorKey: 'due_date', header: 'Due' },
]
export function EvidencePage() {
  return <Register<EvidenceReqRow> id="evidence" title="Evidence" table={CONTRACT.evidence.table}
    select={CONTRACT.evidence.select}
    columns={evidenceCols} getRowId={(r) => `${r.compliance_instance_id}:${r.document_type_name}`} searchColumns={[...CONTRACT.evidence.search]} defaultSort={{ id: 'due_date', desc: false }}
    filterDefs={[{ key: 'evidence_state', label: 'State', options: EVIDENCE_STATES }]}
    quickViewTitle={(r) => `${r.document_type_name} · ${r.instance_no}`} renderQuickView={(r) => <EvidenceQuickView row={r} />} />
}
