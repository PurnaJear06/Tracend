#!/usr/bin/env bash
# Fails when a branch's migrations would not apply cleanly after the base branch's migrations.
#
#   scripts/check-migration-order.sh [base-ref]   (default: origin/main)
#
# Production applies migrations with `supabase db push`, which refuses a migration whose version
# is older than the newest one already applied. Two branches cut on the same day can each pass the
# duplicate check and still fail the deploy once the second one merges. This check moves that
# failure into the pull request:
#   1. every migration the branch adds must be newer than the base's newest migration;
#   2. every migration name must start with a 14-digit version and an underscore;
#   3. migrations already on the base must not be edited, renamed or deleted (forward-only rule).
# The fix for (1) is re-stamping the branch's new migration files to a current version.
set -euo pipefail

base="${1:-origin/main}"
dir="supabase/migrations"

if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "::error::Base ref not found: $base" >&2
  exit 2
fi

versions_in() { sed -n 's#^.*/\([0-9]\{14\}\)_[^/]*\.sql$#\1#p'; }

base_files="$(git ls-tree --name-only "$base" "$dir/" | grep '\.sql$' || true)"
head_files="$(git ls-tree --name-only HEAD "$dir/" | grep '\.sql$' || true)"
base_latest="$(printf '%s\n' "$base_files" | versions_in | sort | tail -1)"

failures=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  name="${file##*/}"
  if ! printf '%s\n' "$name" | grep -Eq '^[0-9]{14}_[a-z0-9_]+\.sql$'; then
    echo "::error file=$file::Migration name must be <14-digit version>_<snake_case>.sql: $name"
    failures=$((failures + 1))
  fi
  if printf '%s\n' "$base_files" | grep -Fxq "$file"; then
    if [ "$(git rev-parse "$base:$file")" != "$(git rev-parse "HEAD:$file")" ]; then
      echo "::error file=$file::Migration already on $base was edited. Migrations are forward-only; add a new one."
      failures=$((failures + 1))
    fi
    continue
  fi
  version="${name%%_*}"
  if [ -n "$base_latest" ] && [[ ! "$version" > "$base_latest" ]]; then
    echo "::error file=$file::Migration $version is not newer than $base's newest ($base_latest). Re-stamp it; production would refuse it."
    failures=$((failures + 1))
  fi
done <<<"$head_files"

# A migration the branch removed (or renamed) is gone from HEAD but present where the branch
# started. Compare with the merge base, so a branch that is merely behind the base does not count
# as removing the base's newer migrations. CI checks out the pull request's merge commit with
# shallow history, where no merge base exists; that commit already holds the base's files, so the
# base itself is the right comparison there.
start="$(git merge-base "$base" HEAD 2>/dev/null || echo "$base")"
start_files="$(git ls-tree --name-only "$start" "$dir/" | grep '\.sql$' || true)"
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if ! printf '%s\n' "$head_files" | grep -Fxq "$file"; then
    echo "::error file=$file::Migration ${file##*/} on $base was deleted or renamed. Migrations are forward-only; add a new one."
    failures=$((failures + 1))
  fi
done <<<"$start_files"

if [ "$failures" -gt 0 ]; then
  echo "Migration order check failed ($failures problem(s))."
  exit 1
fi
echo "Migration order OK (base newest: ${base_latest:-none})."
