#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: deploy-function.sh <function_name>

Deploy one Edge Function with --use-api. Supabase's deploy service sometimes
answers "unexpected deploy status 500" ("Function deploy failed due to an
internal error"); on 2026-09-29 coach-chat and health-sync failed this way and
passed on a manual rerun. A 5xx answer is retried after a wait that doubles
each time. Any other failure (a bundling error, a bad token) fails at once.

A successful deploy is still not proof the code is live: follow it with
scripts/verify-live-function.sh.

Environment:
  SUPABASE_CLI           CLI command (default: scripts/supabase.sh; CI sets supabase)
  PROJECT_REF            Supabase project ref (default: qsfzzsjenopqqqhvpyaw)
  DEPLOY_ATTEMPTS        Deploys before giving up (default: 3)
  DEPLOY_RETRY_SECONDS   Wait before the first retry, doubled each time (default: 30)
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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
function_name="$1"
cli="${SUPABASE_CLI:-$repo_root/scripts/supabase.sh}"
project_ref="${PROJECT_REF:-qsfzzsjenopqqqhvpyaw}"
attempts="${DEPLOY_ATTEMPTS:-3}"
wait_seconds="${DEPLOY_RETRY_SECONDS:-30}"

if [[ ! -f "$repo_root/supabase/functions/$function_name/index.ts" ]]; then
  echo "No function named $function_name in supabase/functions." >&2
  exit 2
fi

output="$(mktemp)"
trap 'rm -f "$output"' EXIT

for ((attempt = 1; attempt <= attempts; attempt++)); do
  if "$cli" functions deploy "$function_name" --project-ref "$project_ref" --use-api 2>&1 |
    tee "$output"; then
    exit 0
  fi
  if ! grep -qE 'unexpected deploy status 5[0-9]{2}' "$output"; then
    echo "Deploying $function_name failed with an error that a retry would not fix." >&2
    exit 1
  fi
  if ((attempt == attempts)); then
    echo "Deploying $function_name failed with a server error $attempts times." >&2
    exit 1
  fi
  echo "::warning::Supabase answered a server error while deploying $function_name (attempt $attempt of $attempts). Retrying in ${wait_seconds}s."
  sleep "$wait_seconds"
  wait_seconds=$((wait_seconds * 2))
done
