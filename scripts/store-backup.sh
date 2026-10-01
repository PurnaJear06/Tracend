#!/usr/bin/env bash
# Store one encrypted production database backup in the private backups repository.
#
# Usage: scripts/store-backup.sh <database-backup-YYYY-MM-DDTHHMMSS.tar.gz.enc>
#
# Environment:
#   BACKUP_REPO             owner/name of the private backups repository
#   BACKUP_REPO_DEPLOY_KEY  OpenSSH private key with write access to that repository only
#   BACKUP_REPO_URL         git remote override (tests use a local bare repository)
#   BACKUP_BRANCH           branch to write (default: main)
#   BACKUP_KEEP             newest backups to retain (default: 30)
#   BACKUP_RETRY_DELAY      seconds between network retries, multiplied by the attempt (default: 5)
#
# The target branch is rewritten as a single orphan commit on every run so the repository does
# not accumulate history. Before pushing, the script proves the only changes against the remote
# are the new backup and retention pruning of the oldest backups; anything else aborts the run.
# The push uses --force-with-lease, so a concurrent writer also aborts the run.
set -euo pipefail

die() { echo "store-backup: $*" >&2; exit 1; }

[ "$#" -eq 1 ] || die "usage: $0 <database-backup-*.tar.gz.enc>"
backup_file="$1"
backup_name="$(basename "$backup_file")"
branch="${BACKUP_BRANCH:-main}"
keep="${BACKUP_KEEP:-30}"
retry_delay="${BACKUP_RETRY_DELAY:-5}"

[ -s "$backup_file" ] || die "backup file is missing or empty: $backup_file"
case "$backup_name" in
  database-backup-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9].tar.gz.enc) ;;
  *) die "unexpected backup file name: $backup_name" ;;
esac
case "$keep" in
  '' | *[!0-9]* | 0) die "BACKUP_KEEP must be a positive integer" ;;
esac
case "$retry_delay" in
  '' | *[!0-9]*) die "BACKUP_RETRY_DELAY must be a non-negative integer" ;;
esac

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export GIT_TERMINAL_PROMPT=0
if [ -n "${BACKUP_REPO_URL:-}" ]; then
  remote_url="$BACKUP_REPO_URL"
else
  [ -n "${BACKUP_REPO:-}" ] || die "BACKUP_REPO is not set"
  [ -n "${BACKUP_REPO_DEPLOY_KEY:-}" ] || die "BACKUP_REPO_DEPLOY_KEY is not set"
  case "$BACKUP_REPO" in
    */*/* | */ | /* | *[!A-Za-z0-9_./-]*) die "BACKUP_REPO must look like owner/name" ;;
    */*) ;;
    *) die "BACKUP_REPO must look like owner/name" ;;
  esac
  remote_url="git@github.com:${BACKUP_REPO}.git"
  # A secret can lose its trailing newline; OpenSSH rejects a key without one.
  (umask 077 && printf '%s\n' "$BACKUP_REPO_DEPLOY_KEY" >"$workdir/deploy_key")
  printf -v GIT_SSH_COMMAND \
    'ssh -i %q -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=%q' \
    "$workdir/deploy_key" "$workdir/known_hosts"
  export GIT_SSH_COMMAND
fi

retry() {
  local attempt=1
  until "$@"; do
    [ "$attempt" -lt 3 ] || return 1
    echo "store-backup: attempt $attempt failed, retrying" >&2
    sleep $((retry_delay * attempt))
    attempt=$((attempt + 1))
  done
}

# An unreachable remote must abort: an empty answer is only trusted when the command succeeded.
remote_head_line="$(retry git ls-remote --heads "$remote_url" "refs/heads/$branch")" \
  || die "cannot reach the backups repository"
remote_head="${remote_head_line%%[[:space:]]*}"

repo="$workdir/repo"
git init -q "$repo"
cd "$repo"
git remote add origin "$remote_url"

previous_commit=""
if [ -n "$remote_head" ]; then
  retry git fetch -q --depth 1 origin "refs/heads/$branch" || die "cannot fetch $branch"
  previous_commit="$(git rev-parse FETCH_HEAD)"
  [ "$previous_commit" = "$remote_head" ] || die "remote moved while fetching; run again"
  git checkout -q -B work "$previous_commit"
else
  git checkout -q -B work
fi

mkdir -p backups
if [ -e "backups/$backup_name" ]; then
  cmp -s "$backup_file" "backups/$backup_name" \
    || die "backups/$backup_name already exists with different content; refusing to overwrite"
else
  cp "$backup_file" "backups/$backup_name"
fi

all_backups="$(find backups -maxdepth 1 -type f -name 'database-backup-*.tar.gz.enc' | sed 's#^backups/##' | sort)"
total="$(printf '%s\n' "$all_backups" | grep -c . || true)"
pruned=""
if [ "$total" -gt "$keep" ]; then
  pruned="$(printf '%s\n' "$all_backups" | head -n "$((total - keep))")"
  if printf '%s\n' "$pruned" | grep -qxF "$backup_name"; then
    die "$backup_name is older than the $keep newest backups; refusing to store it"
  fi
  while IFS= read -r old; do
    git rm -q -f "backups/$old"
  done <<<"$pruned"
fi

git checkout -q --orphan snapshot
git add -A
git -c user.name='Tracend CI' -c user.email='ci@users.noreply.github.com' \
  commit -q --allow-empty -m "Store $backup_name"

# Lists every change against the previous tree except adding the new backup and deleting pruned
# ones. Kept as a function: bash 3.2 (macOS) cannot parse a case statement inside $( ).
unexpected_changes() {
  local status path
  git diff --no-renames --name-status "$previous_commit" HEAD | while IFS=$'\t' read -r status path; do
    case "$status:$path" in
      "A:backups/$backup_name") ;;
      D:backups/database-backup-*.tar.gz.enc)
        printf '%s\n' "$pruned" | grep -qxF "${path#backups/}" || printf '%s %s\n' "$status" "$path"
        ;;
      *) printf '%s %s\n' "$status" "$path" ;;
    esac
  done
}

if [ -n "$previous_commit" ]; then
  unexpected="$(unexpected_changes)"
  [ -z "$unexpected" ] || die "unexpected changes against the remote, not pushing: $unexpected"
fi

new_commit="$(git rev-parse HEAD)"
retry git push -q --force-with-lease="refs/heads/$branch:$previous_commit" origin \
  "snapshot:refs/heads/$branch" || die "push failed"

verify_line="$(retry git ls-remote --heads "$remote_url" "refs/heads/$branch")" \
  || die "cannot verify the push"
[ "${verify_line%%[[:space:]]*}" = "$new_commit" ] || die "remote branch does not point at the pushed commit"

kept="$(git ls-tree --name-only HEAD backups/ | grep -c 'database-backup-' || true)"
echo "store-backup: stored $backup_name ($kept backups kept, newest $keep retained)"
