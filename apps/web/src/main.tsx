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
import { LoginPage, NoAccessPage, NotFoundPage, UnauthorizedPage } from './pages/Pages'
import { DashboardPage } from './pages/DashboardPage'
import { CalendarPage } from './pages/CalendarPage'
import { CompliancePage, EvidencePage, ExceptionsPage, LicencesPage } from './pages/Registers'
import { AuthCallbackPage } from './pages/AuthCallbackPage'
import { UsersPage } from './pages/UsersPage'
import { SystemHealthPage } from './pages/SystemHealthPage'
import { NotificationsPage } from './pages/NotificationsPage'
import { ComplianceMasterPage, ReferenceMasterPage, RuleVersionsPage, ApplicabilityPage, CoveragePage, LicenceTypesPage, LovPage, StatusesPage, SettingsPage } from './admin/pages'

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
                    <Route path="notifications" element={<NotificationsPage />} />
                    <Route element={<RequirePermission perm="compliance.read" />}><Route path="compliance" element={<CompliancePage />} /><Route path="calendar" element={<CalendarPage />} /></Route>
                    <Route element={<RequirePermission perm="exception.read" />}><Route path="exceptions" element={<ExceptionsPage />} /></Route>
                    <Route element={<RequirePermission perm="licence.read" />}><Route path="licences" element={<LicencesPage />} /><Route path="admin/licence-types" element={<LicenceTypesPage />} /></Route>
                    <Route element={<RequirePermission perm="evidence.read" />}><Route path="evidence" element={<EvidencePage />} /></Route>
                    <Route element={<RequirePermission perm="compliance.read" />}><Route path="admin/compliance-masters" element={<ComplianceMasterPage />} /><Route path="admin/rule-versions" element={<RuleVersionsPage />} /><Route path="admin/applicability" element={<ApplicabilityPage />} /><Route path="admin/applicability/coverage" element={<CoveragePage />} /></Route>
                    <Route element={<RequirePermission perm="master.read" />}><Route path="admin/reference/:kind" element={<ReferenceMasterPage />} /></Route>
                    <Route element={<RequirePermission perm="config.read" />}><Route path="admin/lov" element={<LovPage />} /><Route path="admin/statuses" element={<StatusesPage />} /><Route path="admin/settings" element={<SettingsPage />} /></Route>
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
