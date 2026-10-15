#!/usr/bin/env bash
# Tests for the parts of scripts/restore-privileges.sh that need no database: reading
# `supabase migration list`, checking the applied history, and reporting snapshot differences.
# The working directory contains a space on purpose: the primary checkout path has one.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/restore-privileges.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
base="$root/dir with space"
mkdir -p "$base/migrations"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
expect_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected: $2 | actual: $3)"; fi
}
run() { # args... -> "status|output"
  local output status=0
  output="$(bash "$script" "$@" 2>&1)" || status=$?
  printf '%s|%s' "$status" "$output"
}

for version in 20260101000000 20260102000000 20260103000000; do
  touch "$base/migrations/${version}_step.sql"
done
export MIGRATIONS_DIR="$base/migrations"

cat >"$base/list.txt" <<'LIST'

   Local          | Remote         | Time (UTC)
  ----------------|----------------|---------------------
   20260101000000 | 20260101000000 | 2026-01-01 00:00:00
   20260102000000 | 20260102000000 | 2026-01-02 00:00:00
   20260103000000 |                | 2026-01-03 00:00:00

LIST
expect_eq "versions reads the Remote column only" \
  "0|20260101000000
20260102000000" "$(run versions "$base/list.txt")"

printf 'Connecting to remote database...\n' >"$base/empty-list.txt"
case "$(run versions "$base/empty-list.txt")" in
  1\|*"no applied migration versions"*) pass "versions fails when it finds none" ;;
  *) fail "versions must fail when it finds none" ;;
esac

printf '20260101000000\n20260102000000\n20260103000000\n' >"$base/all.txt"
expect_eq "history is current when every local migration is applied" \
  "0|current" "$(run history "$base/all.txt")"

printf '20260101000000\n20260102000000\n' >"$base/behind.txt"
expect_eq "history names the applied version when migrations are pending" \
  "0|20260102000000" "$(run history "$base/behind.txt")"

printf '20260101000000\n20260103000000\n' >"$base/gap.txt"
case "$(run history "$base/gap.txt")" in
  1\|*"local only: 20260102000000"*) pass "history fails on a local migration missing before the applied head" ;;
  *) fail "history must fail on a local migration missing before the applied head" ;;
esac

printf '20260101000000\n20260102000000\n20260102120000\n' >"$base/remote-only.txt"
case "$(run history "$base/remote-only.txt")" in
  1\|*"applied only: 20260102120000"*) pass "history fails on an applied migration with no local file" ;;
  *) fail "history must fail on an applied migration with no local file" ;;
esac

printf 'function private.f(uuid): anon EXECUTE\tno\ntable public.t: row level security\tyes\n' \
  >"$base/expected.tsv"
cp "$base/expected.tsv" "$base/same.tsv"
case "$(run report "$base/expected.tsv" "$base/same.tsv")" in
  0\|*"match the migrations (2 entries)"*) pass "report passes identical snapshots" ;;
  *) fail "report must pass identical snapshots" ;;
esac

printf 'function private.f(uuid): anon EXECUTE\tyes\nfunction public.extra(): anon EXECUTE\tyes\n' \
  >"$base/restored.tsv"
expect_eq "report names every difference and fails" \
  "1|Restored privileges differ from the migrations:
  function private.f(uuid): anon EXECUTE (migrations: no, restored: yes)
  function public.extra(): anon EXECUTE (migrations: absent, restored: yes)
  table public.t: row level security (migrations: yes, restored: absent)" \
  "$(run report "$base/expected.tsv" "$base/restored.tsv")"

: >"$base/empty.tsv"
case "$(run report "$base/expected.tsv" "$base/empty.tsv")" in
  1\|*"missing or empty"*) pass "report fails on an empty snapshot" ;;
  *) fail "report must fail on an empty snapshot" ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All restore-privileges checks passed"
