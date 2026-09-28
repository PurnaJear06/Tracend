#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
Usage: verify-live-function.sh <function_name|--all>

Confirm that production runs this checkout's code for one Edge Function. The
deployed source is downloaded (read-only) and every file is compared byte for
byte with supabase/functions/ in this checkout. --all checks every function
directory in the checkout. A new version can take a moment
to become live, so a mismatch is retried before it fails.

A successful deploy command is not proof: on 2026-09-28 Supabase reported
success for all nine functions but kept the previous version of four.

Environment:
  SUPABASE_ACCESS_TOKEN     Required in CI (locally, the wrapper's login is used)
  SUPABASE_CLI              CLI command (default: scripts/supabase.sh; CI sets supabase)
  PROJECT_REF               Supabase project ref (default: qsfzzsjenopqqqhvpyaw)
  VERIFY_ATTEMPTS           Downloads before giving up (default: 6)
  VERIFY_INTERVAL_SECONDS   Seconds between downloads (default: 10)
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$1" == "--all" ]]; then
  failed=0
  found=0
  for entry in "$repo_root"/supabase/functions/*/index.ts; do
    [[ -f "$entry" ]] || continue
    found=$((found + 1))
    function_name="$(basename "$(dirname "$entry")")"
    "$repo_root/scripts/verify-live-function.sh" "$function_name" || failed=1
  done
  if ((found == 0)); then
    echo "No Edge Function directories found in this checkout." >&2
    exit 1
  fi
  exit "$failed"
fi

function_name="$1"
supabase_cli="${SUPABASE_CLI:-$repo_root/scripts/supabase.sh}"
project_ref="${PROJECT_REF:-qsfzzsjenopqqqhvpyaw}"
attempts="${VERIFY_ATTEMPTS:-6}"
interval="${VERIFY_INTERVAL_SECONDS:-10}"
local_functions="$repo_root/supabase/functions"

if [[ ! -f "$local_functions/$function_name/index.ts" ]]; then
  echo "Function not found in this checkout: supabase/functions/$function_name" >&2
  exit 2
fi

fail() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::error::$1"
  else
    echo "$1" >&2
  fi
  exit 1
}

# Every downloaded file must exist in this checkout with identical bytes. A
# file the checkout added or changed also changes a file that imports it, so
# comparing the downloaded files is enough to catch an older live version.
matches_checkout() {
  local live_functions="$1/supabase/functions"
  local file relative files=0 differences=0
  if [[ ! -f "$live_functions/$function_name/index.ts" ]]; then
    echo "  The download has no $function_name/index.ts."
    return 1
  fi
  while IFS= read -r -d '' file; do
    relative="${file#"$live_functions"/}"
    files=$((files + 1))
    if [[ ! -f "$local_functions/$relative" ]]; then
      echo "  Live only: supabase/functions/$relative"
      differences=$((differences + 1))
    elif ! cmp -s "$file" "$local_functions/$relative"; then
      echo "  Differs: supabase/functions/$relative"
      differences=$((differences + 1))
    fi
  done < <(find "$live_functions" -type f -print0)
  if ((differences > 0)); then
    return 1
  fi
  echo "$function_name: the live code matches this checkout ($files files)."
}

mkdir -p "$repo_root/.tooling"
scratch="$(mktemp -d "$repo_root/.tooling/verify-live-function.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

for ((attempt = 1; attempt <= attempts; attempt++)); do
  workdir="$scratch/$attempt"
  mkdir -p "$workdir/supabase/functions"
  if "$supabase_cli" functions download "$function_name" \
    --project-ref "$project_ref" --use-api --workdir "$workdir" >"$workdir.log" 2>&1; then
    if matches_checkout "$workdir"; then
      exit 0
    fi
  else
    echo "  Download failed:"
    tail -n 5 "$workdir.log" | sed 's/^/    /'
  fi
  if ((attempt < attempts)); then
    echo "$function_name: attempt $attempt of $attempts did not match; retrying in ${interval}s."
    sleep "$interval"
  fi
done

fail "$function_name: the live code does not match this checkout after $attempts attempts."
