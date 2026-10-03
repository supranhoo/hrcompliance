import type { ColumnDef } from '@tanstack/react-table'
import { Link } from 'react-router-dom'
import { Badge } from '../components/ui'
import { titleCase } from '../lib/badges'
import { ACTIVE_OPTIONS, CODE_MESSAGE, CODE_PATTERN } from './domain'
import { validatePeriod, type FieldSpec } from './spec'
import type { AdminRow, MasterSpec } from './AdminRegister'

const activeCol = <T,>(): ColumnDef<T, unknown> => ({ accessorKey: 'is_active', header: 'Status', cell: (c) => <Badge tone={c.getValue<boolean>() ? 'ok' : 'neutral'}>{c.getValue<boolean>() ? 'Active' : 'Inactive'}</Badge> })
const active: FieldSpec = { key: 'is_active', label: 'Active', type: 'boolean', help: 'Inactive records are not offered in pick-lists' }
const code = (max = 40): FieldSpec => ({ key: 'code', label: 'Code', type: 'text', required: true, immutable: true, pattern: CODE_PATTERN, patternMessage: CODE_MESSAGE, max })
const period = (v: Record<string, string | boolean>) => validatePeriod(v, 'effective_from', 'effective_to')
const MASTER_PERM = 'master.write'

type Row = AdminRow & { code: string; name: string }
const simple = <T extends Row>(cols: Array<ColumnDef<T, unknown>>): ColumnDef<T, unknown>[] => [{ accessorKey: 'code', header: 'Code' }, { accessorKey: 'name', header: 'Name' }, ...cols, activeCol<T>()]

export type ComplianceMasterRow = AdminRow & {
  code: string; name: string; description: string | null; domain: string | null; category_id: string | null; category_name: string | null; law_id: string | null; law_name: string | null
  section_reference: string | null; legal_source: string | null; last_reviewed_at: string | null; owner_department_id: string | null; department_name: string | null
  default_owner_user_id: string | null; owner_email: string | null; effective_from: string | null; effective_to: string | null
  active_version: number | null; active_frequency: string | null; active_risk: string | null; version_count: number; draft_count: number
}
export const complianceMasterSpec: MasterSpec<ComplianceMasterRow> = {
  id: 'compliance-masters', title: 'Compliance Master', singular: 'compliance', hasActive: true,
  readTable: 'v_compliance_master', writeTable: 'compliance_master', permission: 'compliance.manage',
  select: 'id,code,name,description,domain,category_id,category_name,law_id,law_name,section_reference,legal_source,last_reviewed_at,owner_department_id,department_name,default_owner_user_id,owner_email,is_active,effective_from,effective_to,row_version,active_version,active_frequency,active_risk,version_count,draft_count',
  searchColumns: ['code', 'name', 'section_reference', 'law_name'], defaultSort: { id: 'code', desc: false },
  searchPlaceholder: 'Search code, name, law or section…',
  filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }, { key: 'active_risk', label: 'Risk', lov: 'RISK' }],
  titleOf: (r) => `${r.code} · ${r.name}`,
  columns: [
    { accessorKey: 'code', header: 'Code' }, { accessorKey: 'name', header: 'Name' },
    { accessorKey: 'category_name', header: 'Category', cell: (c) => c.getValue<string>() ?? '—' },
    { accessorKey: 'law_name', header: 'Law / Act', cell: (c) => c.getValue<string>() ?? '—' },
    { accessorKey: 'active_version', header: 'Rule', cell: (c) => c.getValue<number>() ? `v${c.getValue<number>()} · ${titleCase(c.row.original.active_frequency ?? '')}` : <span className="text-muted">No active rule</span> },
    activeCol<ComplianceMasterRow>(),
  ],
  fields: [
    code(), { key: 'name', label: 'Name', type: 'text', required: true, max: 200 },
    { key: 'description', label: 'Description', type: 'textarea', max: 2000 },
    { key: 'domain', label: 'Domain', type: 'select', lov: 'COMPLIANCE_DOMAIN', help: 'Managed under LOV administration' },
    { key: 'category_id', label: 'Category', type: 'select', lookup: { table: 'compliance_category', value: 'id', label: 'name', filter: { is_active: true } } },
    { key: 'law_id', label: 'Law / Act', type: 'select', lookup: { table: 'law', value: 'id', label: 'name', filter: { is_active: true } } },
    { key: 'section_reference', label: 'Section / rule reference', type: 'text', max: 200, help: 'As supplied by BFCL — never invented' },
    { key: 'legal_source', label: 'Legal source (citation / URL)', type: 'text', max: 500 },
    { key: 'last_reviewed_at', label: 'Last reviewed', type: 'date' },
    { key: 'owner_department_id', label: 'Owner department', type: 'select', lookup: { table: 'department', value: 'id', label: 'name', filter: { is_active: true } } },
    { key: 'default_owner_user_id', label: 'Default owner', type: 'select', lookup: { table: 'app_user', value: 'id', label: 'email', filter: { status: 'active' } }, help: 'New obligations are assigned to this person' },
    { key: 'effective_from', label: 'Effective from', type: 'date' }, { key: 'effective_to', label: 'Effective to', type: 'date' },
    active,
  ],
  extraValidate: (v) => period(v),
  facts: (r) => [['Active rule', r.active_version ? `v${r.active_version} · ${titleCase(r.active_frequency ?? '')} · risk ${titleCase(r.active_risk ?? '')}` : 'None'], ['Rule versions', `${r.version_count} (${r.draft_count} draft)`]],
  extraDetail: (r) => (
    <div className="rounded border border-line bg-canvas p-3 text-sm">
      <p className="text-muted">The master is the stable identity. Due dates, frequency, risk and evidence are defined by <strong>rule versions</strong>; an effective rule is never edited — a new version is created.</p>
      <Link className="mt-2 inline-block text-blue hover:underline" to={`/admin/rule-versions?compliance_code=${encodeURIComponent(r.code)}`}>Manage rule versions →</Link>
      {' · '}<Link className="text-blue hover:underline" to={`/admin/applicability?compliance_code=${encodeURIComponent(r.code)}`}>Applicability →</Link>
    </div>),
}

type CatRow = AdminRow & { code: string; name: string; parent_id: string | null }
const categorySpec: MasterSpec<CatRow> = {
  id: 'ref-category', title: 'Compliance Categories', singular: 'category', hasActive: true, readTable: 'compliance_category', writeTable: 'compliance_category', permission: 'compliance.manage',
  select: 'id,code,name,parent_id,is_active,row_version', searchColumns: ['code', 'name'], defaultSort: { id: 'code', desc: false }, filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }],
  titleOf: (r) => `${r.code} · ${r.name}`, columns: simple<CatRow>([]),
  fields: [code(32), { key: 'name', label: 'Name', type: 'text', required: true, max: 200 }, { key: 'parent_id', label: 'Parent category', type: 'select', lookup: { table: 'compliance_category', value: 'id', label: 'name', filter: { is_active: true } } }, active],
}
type LawRow = AdminRow & { code: string; name: string; short_name: string | null; jurisdiction: string | null }
const lawSpec: MasterSpec<LawRow> = {
  id: 'ref-law', title: 'Laws & Acts', singular: 'law', hasActive: true, readTable: 'law', writeTable: 'law', permission: MASTER_PERM,
  select: 'id,code,name,short_name,jurisdiction,legal_source,last_reviewed_at,effective_from,effective_to,is_active,row_version', searchColumns: ['code', 'name', 'short_name', 'jurisdiction'],
  defaultSort: { id: 'code', desc: false }, filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }], titleOf: (r) => `${r.code} · ${r.name}`,
  columns: simple<LawRow>([{ accessorKey: 'short_name', header: 'Short name', cell: (c) => c.getValue<string | null>() ?? '—' }, { accessorKey: 'jurisdiction', header: 'Jurisdiction', cell: (c) => c.getValue<string | null>() ?? '—' }]),
  fields: [code(), { key: 'name', label: 'Name', type: 'text', required: true, max: 300 }, { key: 'short_name', label: 'Short name', type: 'text', max: 80 }, { key: 'jurisdiction', label: 'Jurisdiction', type: 'text', max: 120 },
    { key: 'legal_source', label: 'Legal source (citation / URL)', type: 'text', max: 500, help: 'As supplied by BFCL — never invented' }, { key: 'last_reviewed_at', label: 'Last reviewed', type: 'date' },
    { key: 'effective_from', label: 'Effective from', type: 'date' }, { key: 'effective_to', label: 'Effective to', type: 'date' }, active],
  extraValidate: (v) => period(v),
}
type AuthRow = AdminRow & { code: string; name: string; authority_type: string | null; office: string | null }
const authoritySpec: MasterSpec<AuthRow> = {
  id: 'ref-authority', title: 'Authorities', singular: 'authority', hasActive: true, readTable: 'authority', writeTable: 'authority', permission: MASTER_PERM,
  select: 'id,code,name,authority_type,office,address,contact_person,email,phone,is_active,row_version', searchColumns: ['code', 'name', 'office'], defaultSort: { id: 'code', desc: false },
  filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }], titleOf: (r) => `${r.code} · ${r.name}`,
  columns: simple<AuthRow>([{ accessorKey: 'authority_type', header: 'Type', cell: (c) => c.getValue<string | null>() ?? '—' }, { accessorKey: 'office', header: 'Office', cell: (c) => c.getValue<string | null>() ?? '—' }]),
  fields: [code(), { key: 'name', label: 'Name', type: 'text', required: true, max: 300 }, { key: 'authority_type', label: 'Type', type: 'text', max: 80 }, { key: 'office', label: 'Office', type: 'text', max: 200 },
    { key: 'address', label: 'Address', type: 'textarea', max: 500 }, { key: 'contact_person', label: 'Contact person', type: 'text', max: 120 },
    { key: 'email', label: 'Email', type: 'text', max: 200, pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/, patternMessage: 'Enter a valid email address' }, { key: 'phone', label: 'Phone', type: 'text', max: 40 }, active],
}
type DeptRow = AdminRow & { code: string; name: string; parent_id: string | null }
const departmentSpec: MasterSpec<DeptRow> = {
  id: 'ref-department', title: 'Departments', singular: 'department', hasActive: true, readTable: 'department', writeTable: 'department', permission: MASTER_PERM,
  select: 'id,code,name,parent_id,is_active,row_version', searchColumns: ['code', 'name'], defaultSort: { id: 'code', desc: false }, filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }],
  titleOf: (r) => `${r.code} · ${r.name}`, columns: simple<DeptRow>([]),
  fields: [code(), { key: 'name', label: 'Name', type: 'text', required: true, max: 200 }, { key: 'parent_id', label: 'Parent department', type: 'select', lookup: { table: 'department', value: 'id', label: 'name', filter: { is_active: true } } }, active],
}
type EntityRow = AdminRow & { code: string; name: string; legal_name: string | null; industry: string | null }
const entitySpec: MasterSpec<EntityRow> = {
  id: 'ref-entity', title: 'Legal Entities', singular: 'entity', hasActive: true, readTable: 'entity', writeTable: 'entity', permission: MASTER_PERM,
  select: 'id,code,name,legal_name,industry,pan,gstin,cin,effective_from,effective_to,is_active,row_version', searchColumns: ['code', 'name', 'legal_name'], defaultSort: { id: 'code', desc: false },
  filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }], titleOf: (r) => `${r.code} · ${r.name}`,
  columns: simple<EntityRow>([{ accessorKey: 'legal_name', header: 'Legal name', cell: (c) => c.getValue<string | null>() ?? '—' }, { accessorKey: 'industry', header: 'Industry', cell: (c) => c.getValue<string | null>() ?? '—' }]),
  fields: [code(), { key: 'name', label: 'Name', type: 'text', required: true, max: 200 }, { key: 'legal_name', label: 'Legal name', type: 'text', max: 300 }, { key: 'industry', label: 'Industry', type: 'text', max: 120 },
    { key: 'pan', label: 'PAN', type: 'text', max: 10, pattern: /^[A-Z]{5}[0-9]{4}[A-Z]$/, patternMessage: 'PAN format: ABCDE1234F' }, { key: 'gstin', label: 'GSTIN', type: 'text', max: 15 }, { key: 'cin', label: 'CIN', type: 'text', max: 21 },
    { key: 'effective_from', label: 'Effective from', type: 'date' }, { key: 'effective_to', label: 'Effective to', type: 'date' }, active],
  extraValidate: (v) => period(v),
}
type LocRow = AdminRow & { code: string; name: string; state: string | null; establishment_type: string | null }
const locationSpec: MasterSpec<LocRow> = {
  id: 'ref-location', title: 'Locations', singular: 'location', hasActive: true, readTable: 'location', writeTable: 'location', permission: MASTER_PERM,
  select: 'id,entity_id,code,name,state,district,address,establishment_type,employee_headcount,contractor_headcount,effective_from,effective_to,is_active,row_version', searchColumns: ['code', 'name', 'state'],
  defaultSort: { id: 'code', desc: false }, filterDefs: [{ key: 'is_active', label: 'Status', options: ACTIVE_OPTIONS }], titleOf: (r) => `${r.code} · ${r.name}`,
  columns: simple<LocRow>([{ accessorKey: 'state', header: 'State', cell: (c) => c.getValue<string | null>() ?? '—' }, { accessorKey: 'establishment_type', header: 'Type', cell: (c) => c.getValue<string | null>() ?? '—' }]),
  fields: [code(), { key: 'name', label: 'Name', type: 'text', required: true, max: 200 },
    { key: 'entity_id', label: 'Legal entity', type: 'select', required: true, immutable: true, lookup: { table: 'entity', value: 'id', label: 'name', filter: { is_active: true } } },
    { key: 'state', label: 'State', type: 'text', max: 80 }, { key: 'district', label: 'District', type: 'text', max: 80 }, { key: 'address', label: 'Address', type: 'textarea', max: 500 },
    { key: 'establishment_type', label: 'Establishment type', type: 'text', max: 80, help: 'Used by applicability rules' },
    { key: 'employee_headcount', label: 'Employees (headcount)', type: 'number', min: 0, max: 1000000, help: 'Used by applicability rules (e.g. 50+ employees)' },
    { key: 'contractor_headcount', label: 'Contractor headcount', type: 'number', min: 0, max: 1000000 },
    { key: 'effective_from', label: 'Effective from', type: 'date' }, { key: 'effective_to', label: 'Effective to', type: 'date' }, active],
  extraValidate: (v) => period(v),
}

/** Reference masters served by one generic page (route /admin/reference/:kind). */
export const REFERENCE_MASTERS = {
  category: categorySpec, law: lawSpec, authority: authoritySpec, department: departmentSpec, entity: entitySpec, location: locationSpec,
} as unknown as Record<string, MasterSpec<AdminRow>>
export const REFERENCE_LABELS: Record<string, string> = { entity: 'Legal Entities', location: 'Locations', category: 'Compliance Categories', law: 'Laws & Acts', authority: 'Authorities', department: 'Departments' }
