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

# Knobs the tests change one at a time; write_files writes them out.
foo_jwt=true
foo_comment="first"
foo_json=1
foo_unimported=1
write_config() {
  mkdir -p "$repo/supabase"
  cat >"$repo/supabase/config.toml" <<TOML
[api]
port = 54321

# $foo_comment
[functions.foo]
verify_jwt = $foo_jwt

[functions.bar]
verify_jwt = true
entrypoint = "./functions/bar/main.ts"

[functions.baz]
verify_jwt = true
TOML
}

write_files() { # a-version inner-version foo-version bar-version
  write_config
  printf '{"v": %s}\n' "$foo_json" >"$fns/foo/data.json"
  printf 'export const golden = %s;\n' "$foo_unimported" >"$fns/foo/legacy_harness.ts"
  printf '{"golden": %s}\n' "$foo_unimported" >"$fns/foo/legacy_golden.json"
  printf 'import "../_shared/b.ts";\nconsole.log(%s);\n' "$4" >"$fns/bar/main.ts"
  printf 'import { inner } from "./a_inner.ts";\nexport const a = %s;\n' "$1" >"$fns/_shared/a.ts"
  printf 'export const inner = %s;\n' "$2" >"$fns/_shared/a_inner.ts"
  printf 'export const b = 1;\n' >"$fns/_shared/b.ts"
  printf 'import { a } from "../_shared/a.ts";\nimport "./helper.ts";\nimport data from "./data.json" with { type: "json" };\nconsole.log(%s, data);\n' "$3" >"$fns/foo/index.ts"
  printf 'export const helper = 1;\n' >"$fns/foo/helper.ts"
  printf 'import { b } from "../_shared/b.ts";\nconsole.log(%s);\n' "$4" >"$fns/bar/index.ts"
}

write_files 1 1 1 1
printf 'import { x } from "../_shared/a.ts";\n' >"$fns/foo/index_test.ts"
commit "release one"
tag v2026.10.02-1000
# Release two changes foo's own code and, through _shared/a.ts's own import, what foo imports.
mkdir -p "$fns/baz"
write_files 1 2 2 1
echo 'baz' >"$fns/baz/index.ts"
commit "release two"
tag v2026.10.03-1000
# Release three changes only bar.
write_files 1 2 2 3
commit "release three"
tag v2026.10.04-1000

# 1. A release that changed only another function is skipped: foo's code is the same in releases
# three and two as on main, so the target is release one. bar changed in release three.
expect_out "a release that changed only another function is skipped" \
  "Rolling back foo to v2026.10.02-1000" run foo --dry-run
expect_out "the target for the function that changed is the release before the change" \
  "Rolling back bar to v2026.10.03-1000" run bar --dry-run
expect_out "the bundle diff names the file reached through a transitive import" "_shared/a_inner.ts" run foo --dry-run
expect_out "the bundle diff names the function's own file" "foo/index.ts" run foo --dry-run
expect_out "a dry run deploys nothing" "Dry run: nothing will be deployed." run foo --dry-run
if [ "$(git -C "$repo" worktree list | wc -l | tr -d ' ')" = "1" ]; then pass "a dry run leaves no worktree behind"; else fail "a dry run left a worktree"; fi
if [ ! -e "$repo/.tooling" ]; then pass "a dry run creates no scratch directory"; else fail "a dry run created .tooling"; fi
if run foo --dry-run | grep -q "bar/index.ts"; then fail "the diff must list only foo's bundle"; else pass "the diff lists only foo's bundle"; fi

# 1b. Config-only changes: the function's own stanza counts (a verify_jwt regression can be
# rolled back), comments and other functions' stanzas do not.
foo_jwt=false
write_files 1 2 2 3
commit "foo verify_jwt flipped (config only)"
expect_out "a config-only change to the function's stanza moves the target" \
  "Rolling back foo to v2026.10.04-1000" run foo --dry-run
expect_out "the diff names the config stanza" "config.toml#functions.foo" run foo --dry-run
foo_jwt=true
write_files 1 2 2 3
commit "foo verify_jwt back"
foo_comment="a different comment"
write_files 1 2 2 3
commit "comment-only config change"
expect_out "a comment-only config change does not move the target" "Rolling back foo to v2026.10.02-1000" run foo --dry-run
if run bar --dry-run | grep -q "functions.foo"; then fail "another function's stanza must not appear"; else pass "another function's stanza does not appear"; fi

# 1c. Only what the entrypoint reaches is bundled: files in the folder that nothing imports do
# not count, imported JSON does.
foo_unimported=2
write_files 1 2 2 3
commit "unimported harness and golden data changed"
expect_out "unimported files in the folder do not move the target" "Rolling back foo to v2026.10.02-1000" run foo --dry-run
if run foo --dry-run | grep -q "legacy_"; then fail "unimported files must not appear in the diff"; else pass "unimported files do not appear in the diff"; fi
foo_json=2
write_files 1 2 2 3
commit "imported JSON changed"
expect_out "imported JSON counts as part of the bundle" "foo/data.json" run foo --dry-run
foo_json=1
write_files 1 2 2 3
commit "imported JSON back"

# 1d. A config entrypoint replaces index.ts as the seed: bar's index.ts is not reached, main.ts is.
printf 'console.log("not bundled, %s");\n' "changed" >"$fns/bar/index.ts"
commit "bar index.ts changed, but bar's entrypoint is main.ts"
expect_out "a file that is not the configured entrypoint does not count" "Rolling back bar to v2026.10.03-1000" run bar --dry-run
write_files 1 2 2 7
commit "bar main.ts changed"
expect_out "the configured entrypoint's files count" "bar/main.ts" run bar --dry-run

# 2. A file that is not reachable from the function and a test file do not count as a change.
printf 'export const unrelated = 1;\n' >"$fns/_shared/unrelated.ts"
printf 'import { x } from "../_shared/a.ts";\nexport const y = 2;\n' >"$fns/foo/index_test.ts"
commit "unrelated shared file and a test change"
expect_out "unreachable files and tests do not move the target" "Rolling back foo to v2026.10.02-1000" run foo --dry-run

# 3. An untagged change on main (a deploy that stopped before the tag): the newest release that
# differs is the target.
write_files 1 2 9 3
commit "bad change to foo, deploy stopped before the tag"
expect_out "an untagged change on main rolls back to the newest release" \
  "Rolling back foo to v2026.10.04-1000" run foo --dry-run

# 4. Explicit target, listing and refusals.
expect_out "--to picks the named release" "Rolling back foo to v2026.10.02-1000" run foo --to v2026.10.02-1000 --dry-run
write_files 1 2 2 3
commit "foo back to its release code"
expect_fail "--to refuses a release whose bundle is identical to main's" "would change nothing" run foo --to v2026.10.04-1000 --dry-run
expect_out "--force allows an identical release" "Rolling back foo to v2026.10.04-1000" run foo --to v2026.10.04-1000 --force --dry-run
expect_fail "--to refuses a name that is not a release tag" "is not a release tag" run foo --to main --dry-run
expect_fail "--to refuses a tag that does not exist" "no tag named" run foo --to v2026.01.01-0000 --dry-run
expect_fail "an unknown function is refused" "no function named nope" run nope --dry-run
expect_fail "a function that did not exist in the release is refused" "did not exist in v2026.10.02-1000" run baz --to v2026.10.02-1000 --dry-run
expect_fail "a missing function name is refused" "Missing function name" run --dry-run
expect_fail "a bad function name is refused" "invalid function name" run "../etc" --dry-run
expect_out "--list shows the release tags" "v2026.10.03-1000" run --list
expect_out "--list for a function says which releases match main's code" "same foo code as origin/main" run foo --list
expect_out "--list for a function says which differ" "differs from origin/main" run foo --list
expect_out "--list says when the function did not exist" "baz did not exist" run baz --list
expect_out "--help describes the options" "--force" run --help

# 5. When no release differs the script refuses and points to --to.
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
