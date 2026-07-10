#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deno="$repo_root/.tooling/deno/node_modules/.bin/deno"

if [[ ! -x "$deno" ]]; then
  echo "Deno is missing. Run ./scripts/bootstrap-tools.sh first." >&2
  exit 1
fi

export DENO_DIR="$repo_root/.tooling/deno-cache"
exec "$deno" "$@"
