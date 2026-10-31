#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: retire-functions.sh [--check]

Without arguments: delete from production every Edge Function named in
scripts/retired-functions.txt that is still deployed. A name that is not
deployed is a no-op, so reruns are safe. Nothing outside that list is ever
deleted, and a listed name that still has a directory in supabase/functions is
refused (the list and the checkout must not disagree).

--check (read-only): fail when production has a deployed function that is
neither a directory in supabase/functions nor in the retired list, so a
leftover is caught by scripts/verify-live-function.sh --all.

Environment:
  SUPABASE_ACCESS_TOKEN   Required in CI (locally, the wrapper's login is used)
  SUPABASE_CLI            CLI command (default: scripts/supabase.sh; CI sets supabase)
  PROJECT_REF             Supabase project ref (default: qsfzzsjenopqqqhvpyaw)
  FUNCTIONS_DIR           Function directories (default: supabase/functions)
  RETIRED_FUNCTIONS_FILE  The retired list (default: scripts/retired-functions.txt)
EOF
}

mode=retire
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="${SUPABASE_CLI:-$repo_root/scripts/supabase.sh}"
project_ref="${PROJECT_REF:-qsfzzsjenopqqqhvpyaw}"
functions_dir="${FUNCTIONS_DIR:-$repo_root/supabase/functions}"
retired_file="${RETIRED_FUNCTIONS_FILE:-$repo_root/scripts/retired-functions.txt}"

fail() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "::error::$1"
  else
    echo "$1" >&2
  fi
  exit 1
}

retired=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="${line//[[:space:]]/}"
  [[ -n "$line" ]] || continue
  if [[ ! "$line" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    fail "Not a function name in $retired_file: $line"
  fi
  if [[ -d "$functions_dir/$line" ]]; then
    fail "$line is in the retired list but still has a directory in $functions_dir."
  fi
  retired+=("$line")
done <"$retired_file"

stderr_log="$(mktemp)"
trap 'rm -f "$stderr_log"' EXIT

# The slugs of the functions deployed to production (read-only).
live_functions() {
  local json
  if ! json="$("$cli" functions list --project-ref "$project_ref" -o json 2>"$stderr_log")"; then
    tail -n 5 "$stderr_log" >&2
    fail "Could not list the deployed Edge Functions."
  fi
  jq -r '.[].slug' <<<"$json" || fail "Could not read the list of deployed Edge Functions."
}

is_retired() {
  local name="$1" entry
  for entry in ${retired[@]+"${retired[@]}"}; do
    [[ "$entry" == "$name" ]] && return 0
  done
  return 1
}

if [[ "$mode" == "check" ]]; then
  live="$(live_functions)"
  unexpected=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ -d "$functions_dir/$name" ]] || is_retired "$name"; then
      continue
    fi
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      echo "::error::$name is deployed but has no directory in supabase/functions and is not in scripts/retired-functions.txt."
    else
      echo "$name is deployed but has no directory in supabase/functions and is not in scripts/retired-functions.txt." >&2
    fi
    unexpected=1
  done <<<"$live"
  if ((unexpected)); then
    exit 1
  fi
  echo "Every deployed function is in this checkout or retired."
  exit 0
fi

if ((${#retired[@]} == 0)); then
  echo "No retired functions."
  exit 0
fi

live="$(live_functions)"
for name in "${retired[@]}"; do
  if ! grep -qxF -- "$name" <<<"$live"; then
    echo "$name: not deployed, nothing to retire."
    continue
  fi
  echo "$name: deployed; deleting it from production."
  "$cli" functions delete "$name" --project-ref "$project_ref"
done

live="$(live_functions)"
for name in "${retired[@]}"; do
  if grep -qxF -- "$name" <<<"$live"; then
    fail "$name is still deployed after deleting it."
  fi
done
echo "Retired functions are gone from production."
