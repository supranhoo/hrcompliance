import { describe, expect, it } from 'vitest'
import { describeAst, draftErrors, emptyDraft, fromAst, isValidAst, leafError, toAst } from './condition'

describe('applicability condition builder', () => {
  it('builds the whitelisted AST the database evaluates', () => {
    expect(toAst({ join: 'and', leaves: [{ field: 'location.employee_headcount', op: 'gte', value: '50' }, { field: 'location.state', op: 'in', value: 'Odisha, Gujarat' }, { field: 'entity.industry', op: 'is_blank', value: '' }] }))
      .toEqual({ op: 'and', args: [{ op: 'gte', field: 'location.employee_headcount', value: 50 }, { op: 'in', field: 'location.state', value: ['Odisha', 'Gujarat'] }, { op: 'is_blank', field: 'entity.industry' }] })
  })
  it('validates leaves: value required, numbers numeric, unknown comparison refused', () => {
    expect(leafError({ field: 'location.employee_headcount', op: 'gte', value: '' })).toBe('Enter a value')
    expect(leafError({ field: 'location.employee_headcount', op: 'gte', value: 'many' })).toBe('Enter a number')
    expect(leafError({ field: 'location.state', op: 'gte', value: '1' })).toBe('Choose a comparison')
    expect(leafError({ field: 'location.state', op: 'is_blank', value: '' })).toBeUndefined()
    expect(leafError({ field: 'nope', op: 'eq', value: 'x' })).toBe('Choose what to test')
    expect(draftErrors(emptyDraft())).toEqual(['Enter a value'])
  })
  it('only structured data: arbitrary fields/operators/expressions are rejected', () => {
    expect(isValidAst({ op: 'and', args: [{ op: 'gte', field: 'location.employee_headcount', value: 50 }] })).toBe(true)
    expect(isValidAst({ op: 'and', args: [{ op: 'eval', field: 'location.state', value: 'x' }] })).toBe(false)
    expect(isValidAst({ op: 'and', args: [{ op: 'eq', field: 'users.password', value: 'x' }] })).toBe(false)
    expect(isValidAst({ op: 'and', args: [] })).toBe(false); expect(isValidAst('1=1; drop table x')).toBe(false); expect(isValidAst(null)).toBe(false)
  })
  it('round-trips through the stored form and reads in plain language', () => {
    const d = { join: 'or' as const, leaves: [{ field: 'location.employee_headcount', op: 'gte', value: '50' }, { field: 'location.state', op: 'in', value: 'Odisha, Gujarat' }] }
    expect(fromAst(toAst(d))).toEqual(d)
    expect(describeAst(toAst(d))).toBe('Employees at the location is at least 50 OR State is one of Odisha, Gujarat')
    expect(fromAst({ op: 'xor' })).toBeNull()
  })
})
