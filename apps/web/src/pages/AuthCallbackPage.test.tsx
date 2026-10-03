import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { beforeEach, expect, it, vi } from 'vitest'

const exchange = vi.hoisted(() => vi.fn())
vi.mock('../lib/supabase', () => ({ supabase: { auth: { exchangeCodeForSession: exchange } } }))
import { AuthCallbackPage } from './AuthCallbackPage'
import { rememberReturnTo } from '../lib/returnTo'

function renderAt(search: string) {
  window.history.pushState({}, '', `/auth/callback${search}`)
  return render(<MemoryRouter initialEntries={[`/auth/callback${search}`]}><Routes>
    <Route path="/auth/callback" element={<AuthCallbackPage />} />
    <Route path="/" element={<p>home</p>} /><Route path="/admin/users" element={<p>users page</p>} /><Route path="/login" element={<p>login</p>} />
  </Routes></MemoryRouter>)
}
beforeEach(() => { exchange.mockReset(); sessionStorage.clear() })

it('exchanges the PKCE code once (StrictMode-safe) and returns the user to where they started', async () => {
  exchange.mockResolvedValue({ error: null })
  rememberReturnTo('/admin/users')
  const { rerender } = renderAt('?code=abc123')
  rerender(<MemoryRouter initialEntries={['/auth/callback?code=abc123']}><Routes><Route path="/auth/callback" element={<AuthCallbackPage />} /><Route path="/admin/users" element={<p>users page</p>} /></Routes></MemoryRouter>)
  await waitFor(() => expect(screen.getByText('users page')).toBeInTheDocument())
  expect(exchange).toHaveBeenCalledTimes(1)
  expect(exchange).toHaveBeenCalledWith('abc123')
})
it('shows the provider error (e.g. access_denied) and offers a way back', async () => {
  renderAt('?error=access_denied&error_description=User+is+not+a+test+user')
  expect(await screen.findByRole('alert')).toHaveTextContent('User is not a test user')
  expect(exchange).not.toHaveBeenCalled()
  expect(screen.getByText('Back to sign in')).toBeInTheDocument()
})
it('fails clearly when the code is missing', async () => {
  renderAt('')
  expect(await screen.findByRole('alert')).toHaveTextContent(/authorisation code/)
})
it('surfaces exchange failures (expired/used code)', async () => {
  exchange.mockResolvedValue({ error: new Error('invalid flow state, no valid flow state found') })
  renderAt('?code=zzz')
  expect(await screen.findByRole('alert')).toHaveTextContent('invalid flow state')
})
