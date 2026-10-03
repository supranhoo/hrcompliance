# BFCL HR Compliance & Governance Command Center

Configurable compliance and governance platform (compliance, contractor compliance, statutory liaison, GRC,
disciplinary, communications, dashboards). PostgreSQL (Supabase) is the source of truth; Excel/Sheets are import,
export and reconciliation formats only.

## Status (v0.1.0 — development, nothing deployed)
| Area | State |
|---|---|
| Repo, CI definition | implemented; CI workflow **not yet run on GitHub** |
| DB foundation (masters, RBAC, audit, business IDs, config metadata, RLS) | implemented, **locally tested** on PostgreSQL 16 with a Supabase shim (68 checks) |
| Web foundation (auth shell, route guard, layout, theme) | implemented, **locally tested** (typecheck, lint, 11 unit/component tests, build) |
| Source data audit | **blocked: no source workbooks supplied** (`docs/migration/SOURCE_DATA_AUDIT.md`) |
| Real Supabase project / Google OAuth / Drive / Gmail | **not connected** (credentials not provided) |
| Everything else (compliance core, contractors, cases, comms, reports…) | not started — see `docs/IMPLEMENTATION_PLAN.md` |

## Layout
`apps/web` React+TS+Vite SPA · `supabase/migrations` ordered SQL · `supabase/seed` system seed · `supabase/tests` SQL tests ·
`scripts/validation` test runners · `scripts/migration` source profiling/import tooling · `docs/` architecture & runbooks.

## Commands
```
npm install
npm run typecheck | lint | test | build
npm run test:db        # needs local PostgreSQL 16 (psql, createdb rights); uses a throwaway database
npm run validate       # all of the above
```
Copy `.env.example` to `.env.local` and fill names with your **development** Supabase project values. Never commit secrets.

## Documentation
ARCHITECTURE · DATA_MODEL · IMPLEMENTATION_PLAN · DECISIONS · MIGRATION_PLAN · SECURITY · DEPLOYMENT · UAT · OPERATIONS (all in `docs/`).
