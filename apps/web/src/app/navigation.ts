/** Single source for sidebar, breadcrumbs and route guards. Entries appear as their modules are built. */
export type NavItem = { path: string; title: string; perm?: string; group: 'Overview' | 'Administration' }
export const NAV: NavItem[] = [
  { path: '/', title: 'Executive Dashboard', group: 'Overview' },
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
