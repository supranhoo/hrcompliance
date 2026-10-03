import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { vi } from 'vitest'

const auth = vi.hoisted(() => ({ value: { status: 'loading', access: null } as Record<string, unknown> }))
vi.mock('./AuthProvider', () => ({ useAuth: () => auth.value }))
import { RequireAuth, RequirePermission } from './RequireAccess'

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/login" element={<p>login page</p>} />
        <Route path="/no-access" element={<p>no access page</p>} />
        <Route element={<RequireAuth />}>
          <Route path="/" element={<p>private home</p>} />
          <Route element={<RequirePermission perm="config.read" />}><Route path="/admin" element={<p>admin page</p>} /></Route>
        </Route>
      </Routes>
    </MemoryRouter>)
}

describe('route protection', () => {
  it('redirects signed-out users to login', () => {
    auth.value = { status: 'signed_out', access: null }
    renderAt('/'); expect(screen.getByText('login page')).toBeInTheDocument()
  })
  it('sends unprovisioned Google accounts to no-access', () => {
    auth.value = { status: 'unauthorized', access: null }
    renderAt('/'); expect(screen.getByText('no access page')).toBeInTheDocument()
  })
  it('shows private content when ready', () => {
    auth.value = { status: 'ready', access: { permissions: new Set() } }
    renderAt('/'); expect(screen.getByText('private home')).toBeInTheDocument()
  })
  it('blocks a page lacking the permission', () => {
    auth.value = { status: 'ready', access: { permissions: new Set(['master.read']) } }
    renderAt('/admin'); expect(screen.getByText(/do not have permission/i)).toBeInTheDocument()
  })
  it('allows a page with the permission', () => {
    auth.value = { status: 'ready', access: { permissions: new Set(['config.read']) } }
    renderAt('/admin'); expect(screen.getByText('admin page')).toBeInTheDocument()
  })
})
