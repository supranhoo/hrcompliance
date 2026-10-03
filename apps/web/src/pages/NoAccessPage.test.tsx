import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { beforeEach, expect, it, vi } from 'vitest'

const auth = vi.hoisted(() => ({ value: {} as Record<string, unknown> }))
vi.mock('../app/AuthProvider', () => ({ useAuth: () => auth.value }))
import { NoAccessPage } from './Pages'

const b64 = (o: object) => btoa(JSON.stringify(o)).replace(/=+$/, '')
const TOKEN = `${b64({ alg: 'x' })}.${b64({ role: 'authenticated', sub: 'u-1', exp: 4_000_000_000 })}.SECRET_SIGNATURE_PART`
const session = { access_token: TOKEN, user: { id: 'u-1', email: 'vivek@example.com', app_metadata: { provider: 'google', providers: ['google'] } } }
const renderPage = () => render(<MemoryRouter initialEntries={['/no-access']}><Routes><Route path="/no-access" element={<NoAccessPage />} /><Route path="/" element={<p>home</p>} /></Routes></MemoryRouter>)
beforeEach(() => { auth.value = { session, accessResult: 'empty', errorMessage: null, signOut: vi.fn(), recheckAccess: vi.fn().mockResolvedValue(undefined) } })

it('explains the state and shows diagnostics without any token material', () => {
  renderPage()
  expect(screen.getByRole('alert')).toHaveTextContent('vivek@example.com is not registered')
  const diag = screen.getByTestId('diag').textContent ?? ''
  expect(diag).toContain('"accessResult": "empty"'); expect(diag).toContain('"tokenSubMatchesUser": true'); expect(diag).toContain('"userId": "u-1"')
  expect(document.body.textContent).not.toContain('SECRET_SIGNATURE_PART'); expect(document.body.textContent).not.toContain(TOKEN)
})
it('Re-check access refreshes the session via the provider', async () => {
  renderPage()
  fireEvent.click(screen.getByText('Re-check access'))
  await waitFor(() => expect((auth.value.recheckAccess as ReturnType<typeof vi.fn>)).toHaveBeenCalledTimes(1))
})
it('moves straight into the app once a profile is found', () => {
  auth.value = { ...auth.value, accessResult: 'profile' }
  renderPage(); expect(screen.getByText('home')).toBeInTheDocument()
})
