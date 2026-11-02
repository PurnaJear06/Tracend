#!/usr/bin/env bash
# Tests for scripts/backup-progress-photos.sh and scripts/encrypt-backup.sh with a stub Supabase
# CLI. No network, no secrets. The working directory contains a space on purpose: the primary
# checkout path has one.
set -euo pipefail

scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
base="$root/dir with space"
mkdir -p "$base"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
expect_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected: $2 | actual: $3)"; fi
}

# The stub CLI answers `db query` with the count in $base/count and `storage cp` by copying the
# files of $base/bucket into the destination, printing every name the way the real CLI does.
cat >"$base/cli" <<'STUB'
#!/usr/bin/env bash
base="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$*" >>"$base/calls"
if [[ "$1 $2" == "db query" ]]; then
  [[ ! -f "$base/count-fails" ]] || exit 1
  echo "photos:$(cat "$base/count")"
elif [[ "$1 $2" == "storage cp" ]]; then
  dst="${*: -1}"
  [[ ! -f "$base/download-fails" ]] || { echo "boom account-secret-id" >&2; exit 1; }
  cp -R "$base/bucket/." "$dst/"
  (cd "$base/bucket" && find . -type f | sed 's#^\./#Uploading #')
else
  exit 2
fi
STUB
chmod +x "$base/cli"

export SUPABASE_CLI="$base/cli"
export BACKUP_ARCHIVE_PASSPHRASE="test passphrase"
out="$base/out"

run() { bash "$scripts/backup-progress-photos.sh" "$out"; }
set_bucket() { # count, then name=content pairs
  local count="$1"
  shift
  rm -rf "$base/bucket"
  mkdir -p "$base/bucket"
  printf '%s' "$count" >"$base/count"
  local pair
  for pair in "$@"; do
    mkdir -p "$base/bucket/$(dirname "${pair%%=*}")"
    printf '%s' "${pair#*=}" >"$base/bucket/${pair%%=*}"
  done
}
backups() { find "$out" -maxdepth 1 -name 'photo-backup-*.tar.gz.enc' 2>/dev/null | sort; }

# 1. An empty bucket is not downloaded but still writes an archive (with no files in it), so the
# store step runs and retention keeps advancing.
set_bucket 0
: >"$base/calls"
run >/dev/null
empty="$(backups)"
expect_eq "an empty bucket still writes one archive" "1" "$(printf '%s\n' "$empty" | grep -c .)"
expect_eq "the empty archive holds no files" "0" \
  "$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$empty" -pass env:BACKUP_ARCHIVE_PASSPHRASE | tar -tzf - | grep -vc '/$')"
if grep -q 'storage cp' "$base/calls"; then fail "an empty bucket must not be downloaded"; else pass "an empty bucket is not downloaded"; fi
rm -rf "$out"

# 2. Photos become one encrypted archive that decrypts to the same files.
set_bucket 2 "user-a/front.jpg=photo one" "user-b/side.jpg=photo two"
answer="$(run)"
first="$(backups)"
expect_eq "one archive is written" "1" "$(printf '%s\n' "$first" | grep -c .)"
case "$(basename "$first")" in
  photo-backup-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9].tar.gz.enc) pass "the archive name carries a UTC stamp" ;;
  *) fail "unexpected archive name: $first" ;;
esac
mkdir -p "$base/restored"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$first" -pass env:BACKUP_ARCHIVE_PASSPHRASE | tar -xzf - -C "$base/restored"
expect_eq "the archive restores the photos' paths and bytes" "photo one|photo two" \
  "$(cat "$base/restored/user-a/front.jpg")|$(cat "$base/restored/user-b/side.jpg")"
case "$answer" in
  *user-a*|*front.jpg*|*Uploading*) fail "the output must not name accounts or files: $answer" ;;
  *) pass "the output names no accounts or files" ;;
esac
case "$answer" in
  *"test passphrase"*) fail "the passphrase must never be printed" ;;
  *) pass "the passphrase is never printed" ;;
esac

# 4. Failures stop the run and write nothing.
rm -rf "$out"
touch "$base/download-fails"
set_bucket 1 "user-a/front.jpg=photo one"
if answer="$(run 2>&1)"; then fail "a failed download must fail"; else pass "a failed download fails"; fi
case "$answer" in
  *account-secret-id*) fail "the download's own output must be withheld: $answer" ;;
  *) pass "the download's own output is withheld" ;;
esac
rm "$base/download-fails"
set_bucket 3 "user-a/front.jpg=photo one"
if run >/dev/null 2>&1; then fail "a download that misses photos must fail"; else pass "a download that misses photos fails"; fi
set_bucket 1 "user-a/front.jpg=a" "user-a/back.jpg=b"
if run >/dev/null 2>&1; then pass "photos added during the download are fine"; else fail "extra files must not fail the run"; fi
touch "$base/count-fails"
if run >/dev/null 2>&1; then fail "an uncountable bucket must fail"; else pass "an uncountable bucket fails"; fi
rm "$base/count-fails"
set_bucket 1 "user-a/front.jpg=a"
if env -u BACKUP_ARCHIVE_PASSPHRASE bash "$scripts/backup-progress-photos.sh" "$out" >/dev/null 2>&1; then
  fail "a missing passphrase must fail"
else
  pass "a missing passphrase fails"
fi

# 5. encrypt-backup.sh refuses a missing archive and an archive that is not a tar.gz.
if bash "$scripts/encrypt-backup.sh" "$base/missing.tar.gz" "$base/x.enc" >/dev/null 2>&1; then fail "a missing archive must fail"; else pass "a missing archive fails"; fi
printf 'not an archive' >"$base/plain.txt"
if bash "$scripts/encrypt-backup.sh" "$base/plain.txt" "$base/plain.enc" >/dev/null 2>&1; then
  fail "a file that is not a tar.gz must fail the readability check"
else
  pass "a file that is not a tar.gz fails the readability check"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All backup-progress-photos checks passed"
