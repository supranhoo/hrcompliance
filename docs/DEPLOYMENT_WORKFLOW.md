# Deployment workflow — permanent `main` branch (PLAN ONLY — nothing here has been applied)

## Today (temporary, by necessity)
The Supabase GitHub integration deploys migrations when **`claude/peaceful-wozniak-gyfjaw`** is pushed. That is a working branch used by Claude Code, so *any* push to it can change the dev database. This was acceptable while the repository had no `main`. It must not be the long-term trigger.

**The live deployment branch is not changed by this document or by anything committed with it.**

## Target workflow
```
claude/<topic>  ──push──▶  CI (web, database 16, database 17, browser smoke, frozen-migration lint)
      │                              │ green
      └───── Pull Request ──────────▶ main  ◀── owner review (CODEOWNERS for migrations/workflows)
                                       │ merge
                                       ▼
                        Supabase GitHub integration (production branch = main)  ──▶ bfcl-hrc-dev
                                       │
                                       ▼
                    owner runs supabase/tests/live_gate.sql → OVERALL PASS
                                       │
                                       ▼
                   small PR: freeze the new versions in supabase/migrations.lock
```
UAT and production later become **separate Supabase projects** tracking their own branches (`release/uat`, `release/prod`) or tags — never feature branches.

## Safe transition plan (owner approves each step; engineering does not do step 3 alone)
| Step | Action | Who | Changes the live DB? | Rollback |
|---|---|---|---|---|
| 0 | Phase 6 live gate PASS and migrations 0014–0022 hash-locked (`LIVE_VERIFICATION.md`) | Owner confirms, Claude locks | No | — |
| 1 | Create `main` **at the exact verified commit**: `git push origin <verified-sha>:refs/heads/main` (or GitHub UI → branches). Do **not** merge anything yet | Owner or Claude on request | **No** — the integration still tracks the old branch | Delete `main` |
| 2 | GitHub → Settings → Branches → rule for `main`: require PR + passing checks (`web`, `database (16)`, `database (17)`), require CODEOWNER review, block force-push and deletion, require linear history optional | Owner | No | Remove rule |
| 3 | **Prove no-op:** compare `select version from supabase_migrations.schema_migrations` with the migration files on `main` (identical list) and run `live_gate.sql` once more | Owner | No | — |
| 4 | Supabase → Project Settings → Integrations → GitHub: change *Production branch* from `claude/peaceful-wozniak-gyfjaw` to `main`. Because `main` contains exactly the applied migrations, nothing is applied | Owner | **No** (no unapplied migrations) | Switch back to the old branch |
| 5 | Make the feature branch non-deploying: from now on Claude opens PRs; pushes to `claude/*` run CI only. Optionally rename/retire `claude/peaceful-wozniak-gyfjaw` after its last PR merges | Owner | No | — |
| 6 | First real change through the new path (e.g. fix D-001) as a PR: CI green → merge → verify with `live_gate.sql` → lock PR | Both | Yes (intended) | Forward-only fix migration |

**Do not perform step 4 while a migration is mid-flight or while unreviewed commits exist on the old branch**: the target branch must already contain every file the old branch had, otherwise the integration would see "missing" history.

## Rules that stay in force
* Migrations are **forward-only**. A bad migration is corrected by a *new* migration. Each file carries a `-- Rollback:` note describing manual reversal for emergencies.
* Applied migrations are immutable (hash-locked); the lock only advances **after** the owner has seen the live gate pass.
* One logical change per migration; naming `<14-digit>_snake_case.sql`; destructive statements need a `-- destructive-ok:` marker and an explicit owner approval in the PR.
* Production deployment requires explicit owner authorisation; UAT is exercised before it.
* Secrets never in Git; the browser only ever has the publishable key.

## Open points for the owner
1. Who reviews migration PRs besides you (CODEOWNERS currently lists `@supranhoo` only)?
2. Do you want Supabase *branching* (per-PR preview databases, a paid feature) or is CI against PostgreSQL 16/17 enough for now? (Current recommendation: CI is enough until UAT.)
3. Names for the future UAT/production Supabase projects and their Cloudflare Pages projects.
