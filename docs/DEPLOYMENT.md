# Deployment

**Status: nothing deployed; no migration has been applied to any Supabase project.** This container cannot reach supabase.com, and the publishable key is not a migration credential — so applying migrations needs one of the secure paths below, done by the project owner. No privileged secret is ever pasted into chat or committed.

## Applying migrations to `bfcl-hrc-dev` (pick one)
**A. Supabase ↔ GitHub integration (recommended).** Dashboard → Project Settings → Integrations → GitHub: repository `supranhoo/hrcompliance`, Supabase directory `supabase`, branch = the branch the project tracks. The integration applies `supabase/migrations/*` when that branch is updated. This repo currently has work only on `claude/peaceful-wozniak-gyfjaw`; the tracked branch (normally `main`) must receive it via a PR/merge (not opened without your request).
**B. Supabase CLI from your own terminal** (credentials typed locally, never shared):
```
npx supabase login                       # browser sign-in
npx supabase link --project-ref <ref>    # prompts for the (rotated) DB password locally
npx supabase db push --dry-run           # review
npx supabase db push
```
## Verify after applying (SQL editor, read-only)
1. Run `supabase/tests/security_audit.sql` → **must return 0 rows**. Any row is a defect to report before continuing.
2. Settings → Data API: confirm Data API on, "automatically expose new tables" **off** (or accept that migrations revoke default grants), automatic RLS on.
3. `select count(*) from public.role;` → 5; `select count(*) from public.job_definition;` → 7.

## Google sign-in (dev)
Create a Google OAuth client (Web); redirect URI = `https://<project-ref>.supabase.co/auth/v1/callback`; enter client ID/secret **directly in Supabase → Authentication → Providers → Google**. Add the local/dev site URL to Authentication → URL configuration.

## Bootstrap the dev Super Admin
SQL editor: run `supabase/seed/dev_bootstrap_admin.sql`, then sign in once with that Google account. DEV ONLY; production identity moves to a BFCL-controlled Workspace account (no authorisation design may depend on the gmail.com domain).

## Frontend
`.env.local`: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`. Build: `npm run build` → `apps/web/dist` (static; Cloudflare Pages or any host).

## Release flow
Dev → automated validation (`npm run validate`) → internal test → UAT → release review → prod migration → prod deploy → smoke test → verification. Production needs explicit authorisation; never experiment in production.

## Rollback
Migration headers carry rollback guidance; data-bearing migrations (Phase 5+) must ship a tested down-script before UAT.

## Development environment registry
| Item | Value / state |
|---|---|
| Supabase project | `bfcl-hrc-dev` (development only) |
| Supabase ↔ GitHub integration | repo `supranhoo/hrcompliance`, directory `.`, deploy-to-production ON, tracked branch `claude/peaceful-wozniak-gyfjaw` (owner-configured; note: a feature branch is the tracked branch — repoint to `main` once the repo has one) |
| Web hosting | Cloudflare Pages `https://hrcompliance.pages.dev` (owner-configured) |
| Supabase Auth | Site URL `https://hrcompliance.pages.dev`; Redirect URL `https://hrcompliance.pages.dev/auth/callback`; Google provider enabled; OAuth test user configured (owner-reported) |

## Migration deployment log
| Date | Event | Evidence |
|---|---|---|
| 2026-10-03 | Migrations 1–11 committed and pushed (HEAD `97bfdd3`); integration configured afterwards, so no push event had fired | git only |
| 2026-10-03 | Documentation-only commit pushed to fire the integration's branch-update deployment | **Applied? Unknown** — verify in Supabase (Database → Migrations, and the GitHub integration's deployment status). Do not treat as applied until the validation sequence below passes |
| 2026-10-03 | Previous trigger commit (`47a035c`) was pushed before the owner finished saving the integration settings | No Supabase deployment evidence |
| 2026-10-03 | Owner reports integration fully saved (deploy-to-production ON, tracked branch `claude/peaceful-wozniak-gyfjaw`); fresh documentation-only commit pushed to deliver a new deployment event | **Applied? Unknown** until the validation sequence below passes |

## Post-deployment validation sequence (SQL editor, in order)
1. `select version from supabase_migrations.schema_migrations order by 1;` → 11 rows `20261003000001` … `20261003000011`.
2. Run `supabase/tests/security_audit.sql` → **0 rows**.
3. `select count(*) from public.role;` → **5** · `select count(*) from public.job_definition;` → **7**.
4. Run `supabase/seed/dev_bootstrap_admin.sql`.
5. Sign in at `https://hrcompliance.pages.dev` with the dev admin Google account (checklist T4–T8 in `docs/AUTH.md`).
