# BFCL HR Compliance & Governance Command Center

Configurable compliance and governance platform (compliance, contractor compliance, statutory liaison, GRC,
disciplinary, communications, dashboards). PostgreSQL (Supabase) is the source of truth; Excel/Sheets are import,
export and reconciliation formats only.

## Status (v0.2.0 — development; nothing deployed, nothing applied to Supabase)
| Area | State |
|---|---|
| DB foundation + platform + jobs (migrations 1–11) | implemented, **locally tested** on PostgreSQL 16 with a Supabase shim: 127 checks incl. negative RLS, security audit (0 violations), concurrency |
| Web shell, UI kit, server-driven table, service contracts, Users/System Health pages | implemented, **locally tested** (typecheck, lint, 69 tests, build); Google login flow implemented but **not tested against real Google/Supabase** (`docs/AUTH.md`); not exercised against a live project |
| Supabase dev project `bfcl-hrc-dev` | migrations 3–11 evidenced as applied via owner screenshots; 0012 pending; first live audit found 2 items (D-016) |
| Google sign-in, Drive, Gmail | not configured (adapters report `NOT_CONFIGURED`) |
| Source data audit | **blocked: no workbooks received** |
| Compliance core, contractors, cases, comms, reports… | not started |

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
Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` for the **development** project. Never commit secrets; privileged keys are server-side only.

## Documentation
ARCHITECTURE · DATA_MODEL · IMPLEMENTATION_PLAN · DECISIONS · MIGRATION_PLAN · SECURITY · DEPLOYMENT · UAT · OPERATIONS (all in `docs/`).
