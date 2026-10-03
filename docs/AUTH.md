# Authentication (Google → Supabase Auth → application user)

## Flow (implemented, unit/browser-smoke tested; **real Google login NOT yet tested**)
1. `/login` → "Continue with Google" → `supabase.auth.signInWithOAuth({provider:'google', redirectTo: <origin>/auth/callback})` (PKCE; `prompt=select_account`). The pre-login path is stored (sessionStorage) and sanitised (`safeReturnTo`: same-origin relative paths only).
2. Google → **Supabase** (`https://<ref>.supabase.co/auth/v1/callback`) → redirect to the app's `/auth/callback?code=…` (only if that URL is on the Supabase Redirect URL allow-list).
3. `AuthCallbackPage` exchanges the single-use code once (StrictMode-safe), shows provider/exchange errors with a way back, then navigates to the return path.
4. `AuthProvider` loads `my_access()` → status `ready` / `unauthorized` (Google account has no `app_user`, or is disabled → `/no-access`) / `error` (retry + sign out). Session persists in browser storage and auto-refreshes.
5. Route guards (`RequireAuth`, `RequirePermission`) are UX only; every query is re-authorised by RLS.
6. Logout: `signOut()` clears the session and the query cache → guards redirect to `/login`.

## Where each URL goes (corrects a common mix-up)
| Setting | Value |
|---|---|
| **Google Cloud → OAuth client → Authorized redirect URI** (required) | `https://<project-ref>.supabase.co/auth/v1/callback` |
| Google → Authorized JavaScript origins | not used by the server-side Supabase flow; harmless to add the app origin |
| **Supabase → Authentication → URL Configuration → Site URL** | the app origin you test from |
| **Supabase → Redirect URLs** (required) | `<app origin>/auth/callback` |

## Which app origin can be tested
This cloud container has **no inbound public URL**, and its egress policy returns 403 for `*.supabase.co` / `api.supabase.com` — so a real login cannot run from inside it. Test from where a browser can reach both Google and Supabase:
* **Local (simplest):** clone the repo, create `apps/web/.env.local` with `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`, `npm ci && npm run dev`, open `http://localhost:5173`. Register `http://localhost:5173/auth/callback`.
* **Cloudflare Pages preview:** connect `supranhoo/hrcompliance`, build `npm ci && npm run build`, output `apps/web/dist`, env vars as above; preview URLs look like `https://<branch>.<project>.pages.dev`. Register `https://*.<project>.pages.dev/auth/callback` (Supabase allows wildcards) plus the production origin later. `public/_redirects` provides the SPA fallback so `/auth/callback` resolves.
* For the cloud session to talk to Supabase at all (e.g. future integration tests), the environment's Network access must allow `*.supabase.co`, and the two public variables must be set as environment variables (new session needed).

## Test checklist (execute on the above; record results here)
| # | Case | Expected | Result |
|---|---|---|---|
| T1 | Unauthenticated visit to `/admin/users` | redirected to `/login` | verified in headless Chromium |
| T2 | Missing env | clear "not configured" alert, button disabled | verified in headless Chromium |
| T3 | Provider error on callback | readable error + back link | verified (browser + unit) |
| T4 | Google login with the dev admin, migrations applied + `dev_bootstrap_admin.sql` run | lands on dashboard; header shows name/roles; Users + System Health in nav | **not run** |
| T5 | Google login with a different Google account | Google blocks (not a test user) — or, if allowed, `/no-access` | **not run** |
| T6 | Reload after login | session persists | **not run** |
| T7 | Sign out | back to `/login`; protected URL redirects | **not run** |
| T8 | Dev admin before bootstrap SQL | `/no-access` (authenticated but unprovisioned) | **not run** |
Authentication is **not** considered complete until T4–T8 pass.
