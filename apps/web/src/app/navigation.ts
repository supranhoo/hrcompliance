/** Single source for sidebar, breadcrumbs and route guards. Entries appear as their modules are built. */
export type NavItem = { path: string; title: string; perm?: string; group: 'Overview' | 'Compliance' | 'Master Data' | 'Administration' }
export const NAV: NavItem[] = [
  { path: '/', title: 'Executive Dashboard', group: 'Overview' },
  { path: '/compliance', title: 'Compliance Register', perm: 'compliance.read', group: 'Compliance' },
  { path: '/calendar', title: 'Compliance Calendar', perm: 'compliance.read', group: 'Compliance' },
  { path: '/exceptions', title: 'Exceptions', perm: 'exception.read', group: 'Compliance' },
  { path: '/licences', title: 'Licences & Registrations', perm: 'licence.read', group: 'Compliance' },
  { path: '/evidence', title: 'Evidence', perm: 'evidence.read', group: 'Compliance' },
  { path: '/notifications', title: 'Notification Centre', group: 'Overview' },
  { path: '/reports', title: 'Reports', perm: 'compliance.read', group: 'Compliance' },
  { path: '/admin/compliance-masters', title: 'Compliance Master', perm: 'compliance.read', group: 'Master Data' },
  { path: '/admin/rule-versions', title: 'Rule Versions', perm: 'compliance.read', group: 'Master Data' },
  { path: '/admin/applicability', title: 'Applicability Matrix', perm: 'compliance.read', group: 'Master Data' },
  { path: '/admin/licence-types', title: 'Licence Types', perm: 'licence.read', group: 'Master Data' },
  { path: '/admin/reference/entity', title: 'Legal Entities', perm: 'master.read', group: 'Master Data' },
  { path: '/admin/reference/location', title: 'Locations', perm: 'master.read', group: 'Master Data' },
  { path: '/admin/reference/law', title: 'Laws & Acts', perm: 'master.read', group: 'Master Data' },
  { path: '/admin/reference/authority', title: 'Authorities', perm: 'master.read', group: 'Master Data' },
  { path: '/admin/reference/department', title: 'Departments', perm: 'master.read', group: 'Master Data' },
  { path: '/admin/reference/document-type', title: 'Document Types', perm: 'master.read', group: 'Master Data' },
  { path: '/admin/reference/category', title: 'Compliance Categories', perm: 'compliance.read', group: 'Master Data' },
  { path: '/admin/alert-rules', title: 'Alert Rules', perm: 'config.read', group: 'Administration' },
  { path: '/admin/exception-config', title: 'Exception Settings', perm: 'config.read', group: 'Administration' },
  { path: '/admin/lov', title: 'Lists (LOV)', perm: 'config.read', group: 'Administration' },
  { path: '/admin/statuses', title: 'Statuses', perm: 'config.read', group: 'Administration' },
  { path: '/admin/settings', title: 'Settings', perm: 'config.read', group: 'Administration' },
  { path: '/admin/imports', title: 'Imports', perm: 'import.read', group: 'Administration' },
  { path: '/admin/users', title: 'Users', perm: 'user.read', group: 'Administration' },
  { path: '/admin/roles', title: 'Roles & Permissions', perm: 'user.read', group: 'Administration' },
  { path: '/admin/export-history', title: 'Export History', perm: 'report.export', group: 'Administration' },
  { path: '/admin/system-health', title: 'System Health', perm: 'health.read', group: 'Administration' },
  { path: '/admin/jobs', title: 'Job Monitor', perm: 'job.read', group: 'Administration' },
]
export const TITLES: Record<string, string> = { admin: 'Administration', ...Object.fromEntries(NAV.map((n) => [n.path, n.title])) }

export function breadcrumbsFor(pathname: string): Array<{ path: string; title: string }> {
  const parts = pathname.split('/').filter(Boolean)
  const crumbs = [{ path: '/', title: 'Home' }]
  let acc = ''
  for (const part of parts) {
    acc += `/${part}`
    crumbs.push({ path: acc, title: TITLES[acc] ?? TITLES[part] ?? part.replace(/-/g, ' ').replace(/^./, (c) => c.toUpperCase()) })
  }
  return crumbs
}
