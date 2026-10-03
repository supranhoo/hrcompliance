/** Single source for sidebar, breadcrumbs and route guards. Entries appear as their modules are built. */
export type NavItem = { path: string; title: string; perm?: string; group: 'Overview' | 'Compliance' | 'Administration' }
export const NAV: NavItem[] = [
  { path: '/', title: 'Executive Dashboard', group: 'Overview' },
  { path: '/compliance', title: 'Compliance Register', perm: 'compliance.read', group: 'Compliance' },
  { path: '/calendar', title: 'Compliance Calendar', perm: 'compliance.read', group: 'Compliance' },
  { path: '/exceptions', title: 'Exceptions', perm: 'exception.read', group: 'Compliance' },
  { path: '/licences', title: 'Licences & Registrations', perm: 'licence.read', group: 'Compliance' },
  { path: '/evidence', title: 'Evidence', perm: 'evidence.read', group: 'Compliance' },
  { path: '/admin/users', title: 'Users', perm: 'user.read', group: 'Administration' },
  { path: '/admin/system-health', title: 'System Health', perm: 'health.read', group: 'Administration' },
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
