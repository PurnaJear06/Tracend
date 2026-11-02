#!/usr/bin/env bash
# Tests for scripts/rollback-function.sh in throwaway git repositories. Only --dry-run and --list
# run: nothing is deployed and no Supabase CLI is involved. The working directory contains a
# space on purpose: the primary checkout path has one.
set -euo pipefail

script_src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rollback-function.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
base="$root/dir with space"
mkdir -p "$base"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
expect_out() { # name expected-fragment command...
  local name="$1" fragment="$2"
  shift 2
  if ! "$@" >"$base/out.txt" 2>&1; then
    fail "$name (command failed: $(tr '\n' ' ' <"$base/out.txt"))"
  elif grep -qF -- "$fragment" "$base/out.txt"; then
    pass "$name"
  else
    fail "$name (missing '$fragment' in: $(tr '\n' ' ' <"$base/out.txt"))"
  fi
}
expect_fail() { # name expected-fragment command...
  local name="$1" fragment="$2"
  shift 2
  if "$@" >"$base/out.txt" 2>&1; then
    fail "$name (it succeeded)"
  elif grep -qF -- "$fragment" "$base/out.txt"; then
    pass "$name"
  else
    fail "$name (wrong message: $(tr '\n' ' ' <"$base/out.txt"))"
  fi
}

git init -q --bare "$base/origin.git"
git --git-dir="$base/origin.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$base/repo"
repo="$base/repo"
fns="$repo/supabase/functions"
mkdir -p "$repo/scripts" "$fns/_shared" "$fns/foo" "$fns/bar"
cp "$script_src" "$repo/scripts/rollback-function.sh"
git -C "$repo" remote add origin "$base/origin.git"

day=1
commit() { # message  (commits everything with the next day's date)
  day=$((day + 1))
  git -C "$repo" add -A
  GIT_AUTHOR_DATE="2026-10-0${day}T10:00:00" GIT_COMMITTER_DATE="2026-10-0${day}T10:00:00" \
    git -C "$repo" commit -q --allow-empty -m "$1"
  git -C "$repo" push -q origin main
}
tag() { git -C "$repo" tag "$1" && git -C "$repo" push -q origin "$1"; }
run() { bash "$repo/scripts/rollback-function.sh" "$@"; }

echo 'export const shared = 1' >"$fns/_shared/a.ts"
echo 'foo one' >"$fns/foo/index.ts"
echo 'bar one' >"$fns/bar/index.ts"
commit "release one"
tag v2026.10.02-1000
mkdir -p "$fns/baz"
echo 'export const shared = 2' >"$fns/_shared/a.ts"
echo 'foo two' >"$fns/foo/index.ts"
echo 'baz one' >"$fns/baz/index.ts"
commit "release two"
tag v2026.10.03-1000

# 1. Main's functions equal the newest release: the previous release is the target.
expect_out "the default target skips a release with the same code as main" \
  "Rolling back foo to v2026.10.02-1000" run foo --dry-run
expect_out "the diff names the shared file that goes back too" "_shared/a.ts" run foo --dry-run
expect_out "the diff summary names the function folders that differ" "  foo" run foo --dry-run
expect_out "a dry run deploys nothing" "Dry run: nothing will be deployed." run foo --dry-run
if [ "$(git -C "$repo" worktree list | wc -l | tr -d ' ')" = "1" ]; then pass "a dry run leaves no worktree behind"; else fail "a dry run left a worktree"; fi
if [ ! -e "$repo/.tooling" ]; then pass "a dry run creates no scratch directory"; else fail "a dry run created .tooling"; fi

# 2. A merge that changed function code and was never tagged (a deploy that stopped): the newest
# release is the target.
echo 'foo three' >"$fns/foo/index.ts"
commit "bad change, deploy stopped before the tag"
expect_out "an untagged change on main rolls back to the newest release" \
  "Rolling back foo to v2026.10.03-1000" run foo --dry-run

# 3. A later release whose code equals main's is skipped, and a commit that changes nothing under
# supabase/functions does not move the target.
tag v2026.10.04-1000
echo 'select 1' >"$repo/note.sql"
commit "sql only"
tag v2026.10.05-1000
expect_out "releases with main's code are skipped, the newest different one is the target" \
  "Rolling back foo to v2026.10.03-1000" run foo --dry-run

# 4. Explicit target, listing and refusals.
expect_out "--to picks the named release" "Rolling back foo to v2026.10.02-1000" run foo --to v2026.10.02-1000 --dry-run
expect_fail "--to refuses a name that is not a release tag" "is not a release tag" run foo --to main --dry-run
expect_fail "--to refuses a tag that does not exist" "no tag named" run foo --to v2026.01.01-0000 --dry-run
expect_fail "an unknown function is refused" "no function named nope" run nope --dry-run
expect_fail "a function that did not exist in the release is refused" "did not exist in v2026.10.02-1000" run baz --to v2026.10.02-1000 --dry-run
expect_fail "a missing function name is refused" "Missing function name" run --dry-run
expect_fail "a bad function name is refused" "invalid function name" run "../etc" --dry-run
expect_out "--list shows the release tags" "v2026.10.03-1000" run --list
expect_out "--list says which releases match main's code" "same code as origin/main" run --list
expect_out "--list says which differ" "differs from origin/main" run --list
expect_out "--help describes the options" "--dry-run" run --help

# 5. When every release has main's code there is nothing to roll back to.
for old in v2026.10.02-1000 v2026.10.03-1000; do
  git -C "$repo" tag -d "$old" >/dev/null
  git --git-dir="$base/origin.git" tag -d "$old" >/dev/null
done
expect_fail "with no release that differs there is nothing to roll back to" "nothing to roll back to" run foo --dry-run

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All rollback-function checks passed"
