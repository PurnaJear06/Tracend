#!/usr/bin/env bash
# Tests for scripts/store-backup.sh against local bare repositories. No network, no secrets.
# The working directory contains a space on purpose: the primary checkout path has one.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/store-backup.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
base="$root/dir with space"
mkdir -p "$base/in"

export BACKUP_RETRY_DELAY=0
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
expect_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected: $2 | actual: $3)"; fi
}

new_remote() {
  local path="$base/$1.git"
  git init -q --bare "$path"
  git --git-dir="$path" symbolic-ref HEAD refs/heads/main
  printf '%s' "$path"
}

make_backup() { # stamp body
  local file="$base/in/database-backup-$1.tar.gz.enc"
  printf 'Salted__%s' "$2" >"$file"
  printf '%s' "$file"
}

remote_backups() { git --git-dir="$1" ls-tree --name-only main backups/ | sed 's#backups/##' | tr '\n' ' '; }
remote_commits() { git --git-dir="$1" rev-list --count main; }
store() { # remote file [env...]
  local remote="$1" file="$2"
  shift 2
  env BACKUP_REPO_URL="$remote" "$@" bash "$script" "$file"
}

# 1. First backup into an empty remote.
r="$(new_remote first)"
f1="$(make_backup 2026-10-01T010000 one)"
store "$r" "$f1" >/dev/null
expect_eq "first backup lands in an empty repository" "database-backup-2026-10-01T010000.tar.gz.enc " "$(remote_backups "$r")"
expect_eq "stored bytes are identical" "$(shasum -a 256 <"$f1")" "$(git --git-dir="$r" show main:backups/database-backup-2026-10-01T010000.tar.gz.enc | shasum -a 256)"

# 2. A second backup is added and history stays a single commit.
f2="$(make_backup 2026-10-01T020000 two)"
store "$r" "$f2" >/dev/null
expect_eq "second backup is added next to the first" \
  "database-backup-2026-10-01T010000.tar.gz.enc database-backup-2026-10-01T020000.tar.gz.enc " "$(remote_backups "$r")"
expect_eq "history is squashed to one commit" "1" "$(remote_commits "$r")"

# 3. Re-storing the identical file is harmless.
store "$r" "$f2" >/dev/null
expect_eq "re-storing the same file keeps the same set" "2" "$(git --git-dir="$r" ls-tree --name-only main backups/ | grep -c .)"

# 3b. A relative path works from another directory: the deploy workflow passes a bare file name.
f3="$(make_backup 2026-10-01T030000 three)"
(cd "$(dirname "$f3")" && store "$r" "$(basename "$f3")" >/dev/null)
expect_eq "a bare file name resolves from the caller's directory" \
  "database-backup-2026-10-01T010000.tar.gz.enc database-backup-2026-10-01T020000.tar.gz.enc database-backup-2026-10-01T030000.tar.gz.enc " \
  "$(remote_backups "$r")"

# 4. The same name with different content is refused and the remote is untouched.
before="$(git --git-dir="$r" rev-parse main)"
changed="$base/in/changed/database-backup-2026-10-01T020000.tar.gz.enc"
mkdir -p "$(dirname "$changed")"
printf 'Salted__different' >"$changed"
if store "$r" "$changed" >/dev/null 2>&1; then fail "different content under an existing name must fail"; else pass "different content under an existing name fails"; fi
expect_eq "remote unchanged after the refused overwrite" "$before" "$(git --git-dir="$r" rev-parse main)"

# 5. Retention keeps only the newest N and deletes the oldest.
r="$(new_remote retention)"
for hour in 01 02 03 04 05; do
  store "$r" "$(make_backup "2026-10-02T${hour}0000" "body$hour")" BACKUP_KEEP=3 >/dev/null
done
expect_eq "retention keeps the newest 3" \
  "database-backup-2026-10-02T030000.tar.gz.enc database-backup-2026-10-02T040000.tar.gz.enc database-backup-2026-10-02T050000.tar.gz.enc " \
  "$(remote_backups "$r")"

# 6. A backup older than the retained window is refused.
old="$(make_backup 2026-09-01T000000 ancient)"
if store "$r" "$old" BACKUP_KEEP=3 >/dev/null 2>&1; then fail "a backup older than the retained window must fail"; else pass "a backup older than the retained window fails"; fi
expect_eq "retained set unchanged after the refusal" "3" "$(git --git-dir="$r" ls-tree --name-only main backups/ | grep -c .)"

# 7. Files other than backups survive (README, notes inside backups/).
r="$(new_remote preserve)"
seed="$base/seed"
git init -q "$seed"
(cd "$seed" && mkdir backups && echo readme >README.md && echo note >backups/NOTES.txt \
  && git add -A && git -c user.name=t -c user.email=t@example.com commit -q -m seed \
  && git push -q "$r" HEAD:refs/heads/main)
store "$r" "$(make_backup 2026-10-03T010000 keep)" >/dev/null
expect_eq "README and non-backup files are preserved" "README.md backups/NOTES.txt backups/database-backup-2026-10-03T010000.tar.gz.enc" \
  "$(git --git-dir="$r" ls-tree -r --name-only main | tr '\n' ' ' | sed 's/ $//')"

# 8. An unreachable remote fails closed with no partial write.
if store "$base/does-not-exist.git" "$f1" >/dev/null 2>&1; then fail "an unreachable remote must fail"; else pass "an unreachable remote fails"; fi

# 9. Input validation.
if store "$r" "$base/in/not-a-backup.txt" >/dev/null 2>&1; then fail "a wrongly named file must fail"; else pass "a wrongly named file fails"; fi
: >"$base/in/database-backup-2026-10-04T010000.tar.gz.enc"
if store "$r" "$base/in/database-backup-2026-10-04T010000.tar.gz.enc" >/dev/null 2>&1; then fail "an empty file must fail"; else pass "an empty file fails"; fi
if env -u BACKUP_REPO_URL -u BACKUP_REPO -u BACKUP_REPO_DEPLOY_KEY bash "$script" "$f1" >/dev/null 2>&1; then
  fail "missing configuration must fail"
else
  pass "missing configuration fails"
fi
if env -u BACKUP_REPO_URL BACKUP_REPO="not a repo" BACKUP_REPO_DEPLOY_KEY=x bash "$script" "$f1" >/dev/null 2>&1; then
  fail "a malformed BACKUP_REPO must fail"
else
  pass "a malformed BACKUP_REPO fails"
fi
if store "$r" "$f1" BACKUP_KEEP=0 >/dev/null 2>&1; then fail "BACKUP_KEEP=0 must fail"; else pass "BACKUP_KEEP=0 fails"; fi

# 10. Deploy key and host key handling, with a stub ssh so nothing touches the network: the key
# file is private (mode 600), ends with a newline even when the secret lost it, and is never
# printed; host keys are checked strictly against exactly GitHub's three published fingerprints
# (https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
mkdir -p "$base/bin"
cat >"$base/bin/ssh" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in
    -i) key="$2"; shift 2 ;;
    -o)
      case "$2" in
        StrictHostKeyChecking=*) strict="${2#*=}" ;;
        UserKnownHostsFile=*) hosts="${2#*=}" ;;
      esac
      shift 2 ;;
    *) shift ;;
  esac
done
mode="$(stat -c %a "$key" 2>/dev/null || stat -f %Lp "$key")"
last="$(tail -c 1 "$key" | od -An -c | tr -d ' ')"
prints="$(ssh-keygen -lf "$hosts" | awk '{print $2}' | LC_ALL=C sort | tr '\n' ' ')"
printf 'mode=%s lastbyte=%s strict=%s fingerprints=%s\n' "$mode" "$last" "$strict" "$prints" >>"$STUB_LOG"
exit 255
STUB
chmod +x "$base/bin/ssh"
export STUB_LOG="$base/ssh-stub.log"
: >"$STUB_LOG"
output="$(env -u BACKUP_REPO_URL PATH="$base/bin:$PATH" BACKUP_REPO="owner/missing" \
  BACKUP_REPO_DEPLOY_KEY="SECRET-KEY-MATERIAL" bash "$script" "$f1" 2>&1 || true)"
expect_eq "ssh gets a mode 600 key ending in a newline" "mode=600 lastbyte=\\n" "$(sort -u "$STUB_LOG" | sed -E 's/ strict=.*//')"
expect_eq "host key checking is strict and pinned to GitHub's three published keys" \
  "strict=yes fingerprints=SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s " \
  "$(sort -u "$STUB_LOG" | sed -E 's/^mode=[0-9]+ lastbyte=[^ ]+ //')"
case "$output" in
  *SECRET-KEY-MATERIAL*) fail "the deploy key must never be printed" ;;
  *) pass "the deploy key is never printed" ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All store-backup checks passed"
