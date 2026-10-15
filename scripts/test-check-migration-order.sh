#!/usr/bin/env bash
# Tests for scripts/check-migration-order.sh against throwaway local repositories. No network.
# The working directory contains a space on purpose: the primary checkout path has one.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-migration-order.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

repo=""
new_repo() { # name
  repo="$root/dir with space/$1"
  mkdir -p "$repo/supabase/migrations"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name test
  printf 'select 1;\n' >"$repo/supabase/migrations/20261013100000_waitlist.sql"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" checkout -qb feature
}
add_migration() { # file body
  printf '%s\n' "$2" >"$repo/supabase/migrations/$1"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "add $1"
}
expect() { # name expected-exit
  local status=0
  (cd "$repo" && "$script" main >/dev/null 2>&1) || status=$?
  if [ "$status" = "$2" ]; then pass "$1"; else fail "$1 (expected exit $2, got $status)"; fi
}

new_repo newer
add_migration 20261015120011_provider_neutral.sql 'select 2;'
expect "newer migration passes" 0

new_repo older
add_migration 20261012090031_set_timing.sql 'select 2;'
expect "migration older than base newest fails" 1

new_repo equal
add_migration 20261013100000_other.sql 'select 2;'
expect "same version as base newest fails" 1

new_repo badname
add_migration 2026101512_short.sql 'select 2;'
expect "short version fails" 1

new_repo edited
add_migration 20261013100000_waitlist.sql 'select 3;'
expect "editing a base migration fails" 1

new_repo deleted
git -C "$repo" rm -q supabase/migrations/20261013100000_waitlist.sql
git -C "$repo" commit -qm delete
expect "deleting a base migration fails" 1

new_repo renamed
git -C "$repo" mv supabase/migrations/20261013100000_waitlist.sql \
  supabase/migrations/20261016100000_waitlist.sql
git -C "$repo" commit -qm rename
expect "renaming a base migration fails" 1

new_repo merged
git -C "$repo" checkout -q main
add_migration 20261015130041_library.sql 'select 4;'
git -C "$repo" checkout -q feature
add_migration 20261015140031_set_timing.sql 'select 2;'
git -C "$repo" merge -q --no-edit main
git -C "$repo" rm -q supabase/migrations/20261013100000_waitlist.sql
git -C "$repo" commit -qm delete
expect "deleting a base migration after merging the base fails" 1

new_repo nothing
expect "branch without migrations passes" 0

new_repo behind
git -C "$repo" checkout -q main
add_migration 20261015130041_library.sql 'select 4;'
git -C "$repo" checkout -q feature
add_migration 20261015120031_set_timing.sql 'select 2;'
expect "branch behind a newer base migration fails until re-stamped" 1
git -C "$repo" mv supabase/migrations/20261015120031_set_timing.sql \
  supabase/migrations/20261015140031_set_timing.sql
git -C "$repo" commit -qm restamp
expect "re-stamped branch passes" 0

if [ "$failures" -gt 0 ]; then
  echo "$failures test(s) failed."
  exit 1
fi
echo "All migration order tests passed."
