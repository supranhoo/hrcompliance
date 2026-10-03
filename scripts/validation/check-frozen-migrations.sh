#!/usr/bin/env bash
# Applied migrations are immutable (D-013). supabase/migrations.lock records the SHA-256 of every migration that has been
# applied to bfcl-hrc-dev. Fails if one is edited, deleted, or if a NEW file sorts before/among the frozen ones.
# To freeze more migrations after they are applied: scripts/validation/check-frozen-migrations.sh --freeze <last-version>
set -euo pipefail
cd "$(dirname "$0")/../.."
LOCK=supabase/migrations.lock
if [ "${1:-}" = "--freeze" ]; then
  LAST="$2"; : > "$LOCK"
  for f in supabase/migrations/*.sql; do v=$(basename "$f" | cut -d_ -f1); [ "$v" -le "$LAST" ] && sha256sum "$f" >> "$LOCK"; done
  echo "froze $(wc -l < "$LOCK") migrations up to $LAST"; exit 0
fi
bad=0
while read -r hash file; do
  [ -f "$file" ] || { echo "FROZEN MIGRATION MISSING: $file"; bad=1; continue; }
  [ "$(sha256sum "$file" | cut -d' ' -f1)" = "$hash" ] || { echo "FROZEN MIGRATION MODIFIED: $file (applied migrations are immutable; add a new migration)"; bad=1; }
done < "$LOCK"
MAX=$(awk '{print $2}' "$LOCK" | xargs -n1 basename | cut -d_ -f1 | sort | tail -1)
for f in supabase/migrations/*.sql; do
  v=$(basename "$f" | cut -d_ -f1)
  if [ "$v" -le "$MAX" ] && ! grep -q " $f\$" "$LOCK"; then echo "NEW MIGRATION INSIDE FROZEN RANGE: $f"; bad=1; fi
done
# Lint for migrations ABOVE the frozen range (new or not yet live-verified): naming, rollback note, no destructive statements without a marker.
for f in supabase/migrations/*.sql; do
  b=$(basename "$f"); v=$(echo "$b" | cut -d_ -f1)
  [ "$v" -le "$MAX" ] && continue
  echo "$b" | grep -Eq '^[0-9]{14}_[a-z0-9_]+\.sql$' || { echo "MIGRATION NAME must be <14-digit version>_snake_case.sql: $b"; bad=1; }
  grep -q '^-- Rollback:' "$f" || { echo "MIGRATION MISSING ROLLBACK NOTE (a line starting with '-- Rollback:'): $b"; bad=1; }
  # temp/scratch tables (name starts with an underscore, e.g. _det) are not schema
  if grep -Ei '^[[:space:]]*(drop[[:space:]]+(table|schema|column)|truncate)' "$f" | grep -Eiv 'drop[[:space:]]+table[[:space:]]+(if[[:space:]]+exists[[:space:]]+)?_' | grep -q . && ! grep -q 'destructive-ok' "$f"; then echo "DESTRUCTIVE STATEMENT without a '-- destructive-ok: <reason>' marker: $b"; bad=1; fi
done
[ "$bad" = 0 ] && echo "ok   - frozen migrations intact ($(wc -l < "$LOCK") files, up to $MAX)"
exit $bad
