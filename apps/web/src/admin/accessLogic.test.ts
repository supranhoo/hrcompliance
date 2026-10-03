import { describe, expect, it } from 'vitest'
import { describeScope, diffPermissions, groupByModule, touchesCritical, validateInvite, validateRoleForm, validateScope } from './accessLogic'
import { describeError, isSelfLockout } from './errors'

describe('permission editor logic', () => {
  it('groups by module and sorts', () => { const g = groupByModule([{ code: 'b.x', module: 'b', description: null }, { code: 'a.z', module: 'a', description: null }, { code: 'a.y', module: 'a', description: null }]); expect(g.map((x) => x.module)).toEqual(['a', 'b']); expect(g[0].items.map((i) => i.code)).toEqual(['a.y', 'a.z']) })
  it('diffs and flags critical removals', () => {
    const d = diffPermissions(['a.read', 'role.admin'], ['a.read', 'a.write']); expect(d).toEqual({ added: ['a.write'], removed: ['role.admin'] }); expect(touchesCritical(d)).toBe(true); expect(touchesCritical(diffPermissions(['a.read'], ['a.read', 'role.admin']))).toBe(false)
  })
  it('validates role, invite and scope forms', () => {
    expect(validateRoleForm({ code: 'bad', name: '', reason: '' }, true)).toMatchObject({ code: expect.any(String), name: expect.any(String), reason: expect.any(String) }); expect(validateRoleForm({ code: '', name: 'x', reason: 'r' }, false)).toEqual({})
    expect(validateInvite({ email: 'nope', reason: 'r' }).email).toBeTruthy(); expect(validateInvite({ email: 'a@b.co', reason: 'r' })).toEqual({})
    expect(validateScope({ scopeAll: false, entities: [], locations: [], departments: [], reason: 'r' }).scope).toBeTruthy(); expect(validateScope({ scopeAll: false, entities: [], locations: [], departments: ['d'], reason: 'r' }).scope).toMatch(/only narrows/); expect(validateScope({ scopeAll: true, entities: [], locations: [], departments: [], reason: 'r' })).toEqual({})
  })
  it('describes broad versus explicit access', () => {
    expect(describeScope({ scopeAll: true, entities: 0, locations: 0, departments: 0 })).toMatch(/broad access/); expect(describeScope({ scopeAll: false, entities: 0, locations: 0, departments: 0 })).toMatch(/sees no business data/)
    expect(describeScope({ scopeAll: false, entities: 1, locations: 2, departments: 0 })).toBe('1 entity + 2 locations; department-owned items are hidden (no department scope)'); expect(describeScope({ scopeAll: false, entities: 1, locations: 0, departments: 2 })).toBe('1 entity, limited to 2 departments for department-owned items')
  })
  it('reports guard errors and detects self-lockout', () => { expect(isSelfLockout({ code: 'AD002' })).toBe(true); expect(isSelfLockout({ code: '42501' })).toBe(false); expect(describeError({ code: 'AD001', message: 'at least one active user must keep role administration' })).toMatch(/at least one active user/) })
})
