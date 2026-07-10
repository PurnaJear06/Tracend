#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_root/.tooling/supabase/node_modules/.bin/supabase"

if [[ ! -x "$cli" ]]; then
  echo "Supabase CLI is missing. Run ./scripts/bootstrap-tools.sh first." >&2
  exit 1
fi

export HOME="$repo_root/.tooling/home"
mkdir -p "$HOME"

colima_socket="$repo_root/.tooling/home/.colima/default/docker.sock"
if [[ -S "$colima_socket" ]]; then
  export DOCKER_HOST="unix://$colima_socket"
fi

exec "$cli" "$@"
