import { expect, it } from 'vitest'
import { breadcrumbsFor } from './navigation'

it('builds breadcrumbs from the path with configured titles', () => {
  expect(breadcrumbsFor('/').map((c) => c.title)).toEqual(['Home'])
  expect(breadcrumbsFor('/admin/system-health').map((c) => c.title)).toEqual(['Home', 'Administration', 'System Health'])
  expect(breadcrumbsFor('/admin/some-new-page').at(-1)?.title).toBe('Some new page')
})
