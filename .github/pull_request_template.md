## What and why
<!-- one paragraph: the business reason, not the diff -->

## Database changes (delete this section if none)
- [ ] New migration file(s) only — **no edit to any migration at or below `supabase/migrations.lock`**
- [ ] Each migration has a `-- Rollback:` note and (if destructive) a `-- destructive-ok: <reason>` marker
- [ ] New tables have RLS **enabled and forced**, explicit grants (none to `anon`), and policies in the same migration
- [ ] `npm run test:db` green locally; CI shows both **database (16)** and **database (17)** green
- [ ] `supabase/tests/live_gate.sql` regenerated if the expected object counts changed (`scripts/validation/build-live-gate.sh`)
- [ ] Expected live counts after deploy stated here: tables __ / permissions __ / migrations __

## App changes
- [ ] `npm run validate` green; screenshots attached for UI changes
- [ ] No business rule duplicated in the frontend (rules live in the database / configuration)

## Verification after merge (owner)
- [ ] Supabase → Database → Migrations shows the new version(s)
- [ ] `live_gate.sql` returns OVERALL PASS
- [ ] Migration versions added to the hash lock: `scripts/validation/check-frozen-migrations.sh --freeze <version>` (separate small PR)
