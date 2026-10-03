# Architecture Decision Log

## D-001 Monorepo with npm workspaces
Decision: `apps/web` plus SQL/scripts/docs at root; `packages/*` created only when code is actually shared. Reason: avoid folder sprawl.
Alternatives: pnpm/turbo (extra tooling, no benefit at this scale). Impact: single `npm run validate`.

## D-002 Supabase migrations are plain ordered SQL, tested on a throwaway Postgres
Decision: `supabase/migrations/<timestamp>_name.sql`, validated by `scripts/validation/db-test.sh` using a shim of `auth`/roles.
Reason: deterministic, reviewable, runnable without a cloud project. Alternatives: Supabase CLI + Docker (not available in this environment; adopt in CI later).
Impact: shim must mirror Supabase defaults; it already exposed one real risk (D-003).

## D-003 Reset default grants, then grant minimally; RLS is the second layer, not the only one
Reason: Supabase grants ALL on new public tables to anon/authenticated. An absent DELETE policy then silently deletes 0 rows instead of erroring.
Decision: migration 0007 revokes all, grants per table. **Every new migration that adds a table must add its own grants, RLS and policies** (checked by the RLS test suite).

## D-004 Typed core columns + metadata-defined custom fields in JSONB
Decision: critical fields are typed columns. Admin-added fields are rows in `field_definition`; values live in a `custom jsonb` column on each
business table, validated server-side against the definition, GIN-indexed, and promoted to typed columns by migration if a field becomes hot.
Reason: no schema change per UI field; core stays queryable and constrained. Alternatives: EAV table (slow, unconstrained), column-per-field DDL from UI (unsafe).
Impact: reporting/import/export read `field_definition` to expand `custom`. Field versions: one live version per (module,key) enforced by partial unique index.

## D-005 Rules are a whitelisted JSON AST, validated in the database
Decision: `app.rule_is_valid` allows only the approved operators, identifier-shaped field names, scalar values, max depth 8; enforced by CHECK constraints.
Reason: administrators can never inject SQL/JS. Impact: evaluator (Phase 4/6) must interpret the same AST; unit-tested against the same fixtures.

## D-006 Dependencies are added with the first feature that needs them
Reason: "every dependency must have a justified purpose". Currently: react, react-router, supabase-js, TanStack Query, zod, tailwind.

## D-007 Business IDs via atomic counter upsert
Decision: `app.next_business_id(rule_key)`; one `INSERT … ON CONFLICT DO UPDATE … RETURNING` per ID; yearly or non-resetting. Verified with 40 parallel callers (40 unique, gapless).
Impact: callable only with service-role / SECURITY DEFINER wrappers, not by API roles.

## D-008 Pre-provisioned users only
Decision: `app_user` rows are created by an admin by email; the first Google login links `auth.users` to it. Reason: "only authorised BFCL users". Open point: also restrict Google sign-in to the BFCL Workspace domain (hosted-domain claim) — needs BFCL decision on domain(s).

## D-009 Audit via row triggers; reasons via transaction-local settings
Decision: `app.audit_row` writes old/new JSON and changed fields (ignoring stamp columns); append-only enforced by triggers incl. TRUNCATE. Reason text via `set_config('app.audit_reason', …, true)`.
Limitation: service-role/superuser sessions can still disable triggers; production DB role hygiene is covered in SECURITY.md.

## D-010 No maker-checker, no month lock (per product requirement 95/96)
