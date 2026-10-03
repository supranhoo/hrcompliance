import { describe, expect, it } from 'vitest'
import { rememberReturnTo, safeReturnTo, takeReturnTo } from './returnTo'

describe('safeReturnTo (open-redirect guard)', () => {
  it.each([['/admin/users', '/admin/users'], ['/a?x=1#h', '/a?x=1#h'], [null, '/'], ['', '/'], ['//evil.com', '/'], ['https://evil.com', '/'], ['/\\evil.com', '/'],
    ['javascript:alert(1)', '/'], ['/auth/callback', '/'], ['/login', '/'], ['/no-access', '/'], ['/x\ny', '/']])('%s -> %s', (i, o) => expect(safeReturnTo(i)).toBe(o))
  it('remembers once and clears', () => {
    rememberReturnTo('/admin/users'); expect(takeReturnTo()).toBe('/admin/users'); expect(takeReturnTo()).toBe('/')
  })
})
