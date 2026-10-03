# Frozen foundation (declared 2026-10-03)

The following are **FROZEN**. Do not modify unless a *reproducible defect* is demonstrated (failing test or live evidence), then fix with a **new** migration/commit and record it in `docs/DECISIONS.md`.

| Frozen area | Where | Evidence it works |
|---|---|---|
| Google OAuth + Supabase Auth + PKCE | `apps/web/src/lib/supabase.ts`, `pages/AuthCallbackPage.tsx`, `app/AuthProvider.tsx` | Owner confirmed live login to `https://hrcompliance.pages.dev` as dev SUPER_ADMIN |
| `app_user`, roles, permissions, scopes, `my_access()` | migrations 0003, 0013 | 4 DB suites incl. auth-link suite; live provisioning confirmed by owner |
| Protected routes / guards | `app/RequireAccess.tsx`, `main.tsx` | 70 web tests; live dashboard access |
| RLS foundation + grants model | migrations 0007, 0010, 0012 + `supabase/tests/security_audit.sql` | Audit 0 violations locally; live audit run before 0012/0013 returned only the 2 items fixed by 0012 |
| Cloudflare deployment | `public/_redirects`, Pages project | Live |
| GitHub → Supabase migration deployment | `supabase/config.toml`, integration | Migrations 1–13 deployed (owner-confirmed 1–12 via Migrations page; 0013 via live behaviour) |

## Enforcement
* `supabase/migrations.lock` holds SHA-256 of migrations 0001–0013. `scripts/validation/check-frozen-migrations.sh` (run first by `npm run test:db`, therefore by CI) fails if a frozen migration is edited, deleted, or a new file is inserted inside the frozen range. New migrations must sort after 0013 and are added to the lock only after they are applied (`--freeze <version>`).
* Behaviour contract of `my_access()` (fail-closed): unknown email → `{}`; unprovisioned → `{}`; disabled → `{}`; invited + pre-provisioned + **confirmed** email → linked and activated (audited); already-linked active user → returned unchanged with **zero writes**; a row linked to another identity is never taken over.
* Diagnostics: the access diagnostics panel renders **only when `VITE_APP_ENV=development`**; it shows identifiers/states only (no tokens, headers, JWTs, provider secrets or claims beyond role/subject-match/expiry-seconds).

## Change procedure
1. Reproduce (test or live evidence). 2. New migration / commit. 3. All suites + audit pass. 4. Update this file and D-0xx.

## Migration hash-lock (updated 2026-10-03)
`supabase/migrations.lock` holds SHA-256 for **migrations 0001–0025** (all applied to `bfcl-hrc-dev` and live-gated; PostgreSQL 17). `check-frozen-migrations.sh` (CI step 1) fails if any is edited or deleted or if a file is inserted inside the range; `test-frozen-lock.sh` proves the check works.
**A legitimate correction is a NEW migration** (0023 or later): never edit a locked file. Write the fix as `create or replace function …` / `alter …` in a new file with a `-- Rollback:` note, add tests, deploy and live-gate it, then extend the lock with `check-frozen-migrations.sh --freeze <version>` in a follow-up commit after the live gate passes.
