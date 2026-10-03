# BFCL HR Compliance & Governance Command Center

Configurable compliance and governance platform (compliance, contractor compliance, statutory liaison, GRC,
disciplinary, communications, dashboards). PostgreSQL (Supabase) is the source of truth; Excel/Sheets are import,
export and reconciliation formats only.

## Status (v0.3.0 — development; nothing deployed, nothing applied to Supabase)
| Area | State |
|---|---|
| DB foundation + platform + jobs + compliance core (migrations 0001–0022) | implemented, **locally tested** on PostgreSQL 16 (12 SQL suites, security audit 0 violations, 3 concurrency checks); migrations 1–13 hash-locked and live; **0014–0022 not yet confirmed on the live project** |
| Web: shell, UI kit, server-driven tables, **Phase 6 UI** (dashboard with drill-down, compliance/exception/licence/evidence registers, calendar, quick views, status actions) | implemented, **locally tested**: typecheck, lint, 127 unit/component tests, 23 real-browser smoke checks, build; contract tests against real PostgreSQL output; live auth confirmed by owner |
| Supabase dev project `bfcl-hrc-dev` | migrations 3–11 evidenced as applied via owner screenshots; 0012 pending; first live audit found 2 items (D-016) |
| Google sign-in, Drive, Gmail | not configured (adapters report `NOT_CONFIGURED`) |
| Source data audit | **blocked: no workbooks received** |
| Compliance core (Phase 6) | built and locally tested end-to-end (see `docs/IMPLEMENTATION_PLAN.md`); **no master-data entry UI yet**, engines **not scheduled** |
| Contractors, ESIC/GRC/disciplinary/liaison, communications, import, reports… | not started |

**Frozen:** auth/access/RLS foundation, migrations 0001–0013 — see `docs/FROZEN.md`.

### Layout
`apps/web` React+TS+Vite SPA · `supabase/migrations` ordered SQL · `supabase/seed` system seed · `supabase/tests` SQL tests ·
`scripts/validation` test runners · `scripts/migration` source profiling/import tooling · `docs/` architecture & runbooks.

## Commands
```
npm install
npm run typecheck | lint | test | build
npm run test:db        # needs local PostgreSQL (psql, createdb rights); uses throwaway databases
npm run test:e2e       # real-browser smoke (Chromium via playwright-core; set CHROME_PATH if not auto-detected)
scripts/validation/gen-fixtures.sh   # regenerate frontend contract fixtures from the real migrations
npm run validate       # all of the above
```
Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` for the **development** project. Never commit secrets; privileged keys are server-side only.

## Documentation
ARCHITECTURE · DATA_MODEL · IMPLEMENTATION_PLAN · DECISIONS · MIGRATION_PLAN · SECURITY · DEPLOYMENT · UAT · OPERATIONS (all in `docs/`).
