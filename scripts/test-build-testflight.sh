#!/usr/bin/env bash
# Tests for the guards of scripts/build-testflight.sh and the build number of
# scripts/app-version.sh, in throwaway git repositories. Nothing is built or uploaded: every run
# uses --check. The working directory contains a space on purpose: the primary checkout path has one.
set -euo pipefail

scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
expect_ok() { # name command...
  local name="$1"
  shift
  if "$@" >"$base/out.txt" 2>&1; then pass "$name"; else fail "$name ($(tr '\n' ' ' <"$base/out.txt"))"; fi
}
expect_fail() { # name expected-message command...
  local name="$1" message="$2"
  shift 2
  if "$@" >"$base/out.txt" 2>&1; then
    fail "$name (it succeeded)"
  elif grep -qF -- "$message" "$base/out.txt"; then
    pass "$name"
  else
    fail "$name (wrong message: $(tr '\n' ' ' <"$base/out.txt"))"
  fi
}

git init -q --bare "$base/origin.git"
git --git-dir="$base/origin.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$base/repo"
repo="$base/repo"
mkdir -p "$repo/scripts" "$repo/ios/Runner.xcodeproj"
cp "$scripts/build-testflight.sh" "$scripts/app-version.sh" "$repo/scripts/"
printf 'version: 1.0.0+1\n' >"$repo/pubspec.yaml"
printf '.tooling\nbuild\n' >"$repo/.gitignore"
team_lines() { printf '\t\t\t\tDEVELOPMENT_TEAM = %s;\n' "$@"; }
team_lines TEAM123456 TEAM123456 >"$repo/ios/Runner.xcodeproj/project.pbxproj"
git -C "$repo" add -A
git -C "$repo" commit -q -m one
git -C "$repo" remote add origin "$base/origin.git"
git -C "$repo" push -q origin main
git -C "$repo" fetch -q origin

env_file="$base/.env"
write_env() { printf 'SUPABASE_URL=%s\nSUPABASE_PUBLISHABLE_KEY=%s\n' "$1" "$2" >"$env_file"; }
write_env https://example.supabase.co secret-publishable-key
run() { env TRACEND_ENV_FILE="$env_file" "$@" bash "$repo/scripts/build-testflight.sh" --check; }
commit_on_main() { # message
  git -C "$repo" add -A
  git -C "$repo" commit -q --allow-empty -m "$1"
  git -C "$repo" push -q origin main
}

expect_ok "a clean origin/main tip passes the guards" run
grep -q 'Tracend 1.0.0 (1) from' "$base/out.txt" && pass "it reports the version and the commit count as the build number" || fail "version line: $(cat "$base/out.txt")"
grep -q 'secret-publishable-key' "$base/out.txt" && fail "the publishable key must not be printed" || pass "the publishable key is not printed"

printf 'x' >"$repo/untracked.txt"
expect_fail "an untracked file is refused" "working tree is not clean" run
rm "$repo/untracked.txt"
printf 'changed\n' >>"$repo/pubspec.yaml"
expect_fail "an edited tracked file is refused" "working tree is not clean" run
git -C "$repo" checkout -q -- pubspec.yaml

git -C "$repo" commit -q --allow-empty -m "local only"
expect_fail "a commit that is not on origin/main is refused" "is not the origin/main tip" run
git -C "$repo" reset -q --hard origin/main

git clone -q "$base/origin.git" "$base/other"
git -C "$base/other" commit -q --allow-empty -m "newer main"
git -C "$base/other" push -q origin main
expect_fail "an old commit behind the origin/main tip is refused" "is not the origin/main tip" run
git -C "$repo" pull -q --ff-only origin main

expect_fail "a manual build number is refused" "TRACEND_BUILD_NUMBER is set" run TRACEND_BUILD_NUMBER=5
expect_fail "a manual build name is refused" "TRACEND_BUILD_NAME is set" run TRACEND_BUILD_NAME=9.9.9
printf 'TRACEND_BUILD_NUMBER=5\n' >>"$env_file"
expect_fail "a build number set in .env is refused" "TRACEND_BUILD_NUMBER is set" run
write_env https://example.supabase.co secret-publishable-key
printf 'TRACEND_BUILD_NAME=9.9.9\n' >>"$env_file"
expect_fail "a build name set in .env is refused" "TRACEND_BUILD_NAME is set" run
write_env https://example.supabase.co secret-publishable-key

write_env "" secret-publishable-key
expect_fail "an empty SUPABASE_URL is refused" "must both be set" run
write_env https://example.supabase.co ""
expect_fail "an empty SUPABASE_PUBLISHABLE_KEY is refused" "must both be set" run
write_env http://127.0.0.1:54321 secret-publishable-key
expect_fail "a non-https SUPABASE_URL is refused" "must start with https://" run
rm "$env_file"
expect_fail "a missing .env is refused" "missing" run
write_env https://example.supabase.co secret-publishable-key

mkdir -p "$repo/.tooling"
printf '99 1.0.0 %s 2026-11-01T00:00:00Z\n' "0000000000000000000000000000000000000000" >"$repo/.tooling/testflight-builds.txt"
expect_fail "a build number below the last one made is refused" "is not higher than the last build" run
number="$("$repo/scripts/app-version.sh" number)"
printf '%s 1.0.0 %s 2026-11-01T00:00:00Z\n' "$number" "0000000000000000000000000000000000000000" >"$repo/.tooling/testflight-builds.txt"
expect_fail "the same number from a different commit is refused" "is not higher than the last build" run
printf '%s 1.0.0 %s 2026-11-01T00:00:00Z\n' "$number" "$(git -C "$repo" rev-parse HEAD)" >"$repo/.tooling/testflight-builds.txt"
expect_ok "rebuilding the same commit is allowed" run
printf '1 1.0.0 %s 2026-11-01T00:00:00Z\n' "0000000000000000000000000000000000000000" >"$repo/.tooling/testflight-builds.txt"
expect_ok "a higher number than the last build passes" run
rm -rf "$repo/.tooling"

team_lines TEAM123456 OTHERTEAM99 >"$repo/ios/Runner.xcodeproj/project.pbxproj"
commit_on_main "two teams"
expect_fail "two development teams are refused" "exactly one DEVELOPMENT_TEAM" run
team_lines TEAM123456 TEAM123456 >"$repo/ios/Runner.xcodeproj/project.pbxproj"
commit_on_main "one team again"
expect_ok "one development team passes" run

# The build number follows origin/main, so a branch with more commits cannot outrun main.
main_number="$("$repo/scripts/app-version.sh" number)"
git -C "$repo" checkout -q -b feature
for i in 1 2 3 4 5; do git -C "$repo" commit -q --allow-empty -m "branch $i"; done
expect_ok "a branch build takes main's number" test "$("$repo/scripts/app-version.sh" number)" = "$main_number"
git -C "$repo" checkout -q main
git -C "$repo" commit -q --allow-empty -m "unpushed"
git -C "$repo" push -q origin main
expect_ok "the number grows with each commit on main" test "$("$repo/scripts/app-version.sh" number)" -gt "$main_number"

rm -rf "$repo/.git/refs/remotes"
expect_ok "without origin/main the number falls back to the commit count" \
  test "$("$repo/scripts/app-version.sh" number)" = "$(git -C "$repo" rev-list --count HEAD)"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All build-testflight checks passed"
