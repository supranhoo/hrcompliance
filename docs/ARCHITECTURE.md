# Architecture

## Components
```
Browser (React SPA, Cloudflare Pages)
   │  supabase-js (anon key + user JWT)         Google Sign-In → Supabase Auth
   ▼
Supabase: PostgREST/RPC ── RLS ── PostgreSQL (source of truth) ── pg_cron / Edge Functions (jobs)
                                        │
                     Edge Functions (service role, server-side only) ──► Google Drive API, Gmail API
```
* **Frontend**: React + TypeScript + Vite, Tailwind, TanStack Query (server state), Zod (validation). TanStack Table,
  React Hook Form, charting, calendar and rich-text editor are added **when the first module needs them** (D-006).
* **Database**: typed relational core + metadata-driven configuration (D-004). Authorization is enforced by RLS and
  `SECURITY DEFINER` helpers in the non-exposed `app` schema; UI hiding is convenience only.
* **Identity**: Google → Supabase Auth → `app_user` (pre-provisioned by email; unknown Google accounts get no profile and
  every RLS check fails closed) → roles → permissions + entity/location scope.
* **Documents**: Google Drive holds files; PostgreSQL holds Drive file IDs, metadata, version chain and verification status.
  Drive/Gmail calls run only in Edge Functions with server-held credentials (never in the browser).
* **Jobs**: scheduled functions write to `job_run` (Phase 12) and are idempotent via natural-key unique constraints.

## Boundaries (what lives where)
| Concern | Location | Reason |
|---|---|---|
| Integrity, uniqueness, ID allocation, audit, RLS, rule-AST validation | PostgreSQL | must hold regardless of client |
| Aggregations for dashboards, ageing, expiry buckets | SQL views/RPC (Phase 7) | server-side, indexed, no client filtering |
| Form rendering, rule *evaluation for UI hints* | React | UX |
| Rule evaluation that creates records (applicability, exceptions, hold) | SQL/Edge Function from the same validated AST | one authoritative implementation per rule |
| Drive, Gmail | Edge Functions | secrets stay server-side |

## Environments
Development → UAT → Production, separate Supabase projects and hosting projects. Not yet created (no access provided).
