#!/usr/bin/env bash
# Download the private progress-photo bucket and write it as one encrypted archive.
#
# Usage: scripts/backup-progress-photos.sh <output-directory>
#
# Writes <output-directory>/photo-backup-<UTC stamp>.tar.gz.enc and prints its name. An empty
# bucket gives an archive with no files, so retention keeps advancing and archives holding
# deleted photos age out. Meal photos (meal-images) are not backed up: the
# app deletes them about 7 days after they are taken. Every night's archive is stored, not only
# a changed one, so a deleted account's photos leave the backups within the 30 retained nights.
#
# The Storage file names hold account IDs and the deploy log is public, so the download's own
# output is never shown: only counts and the archive's name are printed.
#
# Environment:
#   BACKUP_ARCHIVE_PASSPHRASE   Passphrase for scripts/encrypt-backup.sh (required)
#   SUPABASE_CLI                CLI command (default: scripts/supabase.sh; CI sets supabase)
#   SUPABASE_ACCESS_TOKEN       Required in CI; the CLI reads the bucket through the project's own
#                               API keys, so no service key is stored anywhere
#   PHOTO_BUCKET                Bucket to back up (default: progress-photos)
#   PHOTO_WARN_BYTES            Warn when the archive passes this size (default: 26214400, 25 MiB)
set -euo pipefail

die() { echo "backup-progress-photos: $*" >&2; exit 1; }

[ "$#" -eq 1 ] || die "usage: $0 <output-directory>"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="${SUPABASE_CLI:-$repo_root/scripts/supabase.sh}"
bucket="${PHOTO_BUCKET:-progress-photos}"
warn_bytes="${PHOTO_WARN_BYTES:-26214400}"
mkdir -p "$1"
out_dir="$(cd "$1" && pwd)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The number of stored photos, from the database: a bucket that lists nothing must not pass for
# an empty one.
photo_count() {
  local answer
  answer="$("$cli" db query --linked \
    "select 'photos:' || count(*) from storage.objects where bucket_id = '$bucket'" 2>/dev/null |
    grep -oE 'photos:[0-9]+' | head -n 1)" || true
  [ -n "$answer" ] || die "could not count the photos in $bucket"
  echo "${answer#photos:}"
}

mkdir -p "$scratch/photos"
before="$(photo_count)"
if [ "$before" -gt 0 ]; then
  if ! "$cli" storage cp --experimental --linked -r "ss:///$bucket" "$scratch/photos" >"$scratch/download.log" 2>&1; then
    die "the download failed (its output is withheld: it names accounts)"
  fi
  after="$(photo_count)"
  downloaded="$(find "$scratch/photos" -type f | wc -l | tr -d ' ')"
  # Photos can be added or deleted while the download runs, so only a shortfall against the
  # smaller of the two counts means the download missed some.
  expected="$before"
  [ "$after" -ge "$expected" ] || expected="$after"
  [ "$downloaded" -ge "$expected" ] ||
    die "downloaded $downloaded files but the bucket holds at least $expected"
else
  # An empty bucket still stores an archive with no files in it: the newest 30 nights are kept,
  # so a night that stored nothing would leave the archives that hold a deleted account's
  # photos in the backups for ever.
  downloaded=0
fi

stamp="$(date -u +%Y-%m-%dT%H%M%S)"
name="photo-backup-${stamp}.tar.gz.enc"

tar -czf "$scratch/photos.tar.gz" -C "$scratch/photos" .
"$repo_root/scripts/encrypt-backup.sh" "$scratch/photos.tar.gz" "$out_dir/$name"

size="$(wc -c <"$out_dir/$name" | tr -d ' ')"
if [ "$size" -gt "$warn_bytes" ]; then
  echo "::warning::The photo backup is $size bytes. The private backups repository keeps 30 copies and rejects a file over 90 MiB: move photo backups to object storage before it gets there."
fi
echo "Backed up $downloaded progress photo(s) (about $size bytes encrypted)."
echo "$name"
