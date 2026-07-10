#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tool/versions.env"

export HOME="$repo_root/.tooling/home"
export COLIMA_HOME="$repo_root/.tooling/colima-home"
export COLIMA_CACHE_HOME="$repo_root/.tooling/colima-cache"
export LIMA_HOME="$repo_root/.tooling/lima-home"
export DOCKER_CONFIG="$repo_root/.tooling/docker-config"
export PATH="$repo_root/.tooling/bin:$repo_root/.tooling/lima/$LIMA_VERSION/bin:$repo_root/.tooling/docker/$DOCKER_CLI_VERSION/docker:$PATH"

mkdir -p "$HOME" "$DOCKER_CONFIG"

colima="$repo_root/.tooling/bin/colima"

if [[ ! -x "$colima" ]]; then
  echo "Container runtime is missing. Run ./scripts/bootstrap-container-runtime.sh first." >&2
  exit 1
fi

if [[ "${1:-}" == "start" ]]; then
  shift
  exec "$colima" start \
    --runtime docker \
    --vm-type vz \
    --cpu 4 \
    --memory 6 \
    --disk 40 \
    --mount "$repo_root:w" \
    "$@"
fi

exec "$colima" "$@"
