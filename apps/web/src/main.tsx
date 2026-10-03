import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import './styles/index.css'
import { AuthProvider } from './app/AuthProvider'
import { RequireAuth, RequirePermission } from './app/RequireAccess'
import { Layout } from './app/Layout'
import { ToastProvider } from './app/Toasts'
import { ErrorBoundary } from './app/ErrorBoundary'
import { DashboardPage, LoginPage, NoAccessPage, NotFoundPage, UnauthorizedPage } from './pages/Pages'
import { AuthCallbackPage } from './pages/AuthCallbackPage'
import { UsersPage } from './pages/UsersPage'
import { SystemHealthPage } from './pages/SystemHealthPage'

const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 30_000 } } })

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <ToastProvider>
          <BrowserRouter>
            <AuthProvider>
              <Routes>
                <Route path="/login" element={<LoginPage />} />
                <Route path="/auth/callback" element={<AuthCallbackPage />} />
                <Route path="/no-access" element={<NoAccessPage />} />
                <Route element={<RequireAuth />}>
                  <Route element={<Layout />}>
                    <Route index element={<DashboardPage />} />
                    <Route path="unauthorized" element={<UnauthorizedPage />} />
                    <Route element={<RequirePermission perm="user.read" />}><Route path="admin/users" element={<UsersPage />} /></Route>
                    <Route element={<RequirePermission perm="health.read" />}><Route path="admin/system-health" element={<SystemHealthPage />} /></Route>
                    <Route path="*" element={<NotFoundPage />} />
                  </Route>
                </Route>
                <Route path="*" element={<NotFoundPage />} />
              </Routes>
            </AuthProvider>
          </BrowserRouter>
        </ToastProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  </StrictMode>,
)
