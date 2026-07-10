#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tool/versions.env"

docker_bin="$repo_root/.tooling/docker/$DOCKER_CLI_VERSION/docker/docker"
colima_socket="$repo_root/.tooling/home/.colima/default/docker.sock"

if [[ ! -x "$docker_bin" ]]; then
  echo "Docker CLI is missing. Run ./scripts/bootstrap-container-runtime.sh first." >&2
  exit 1
fi

if [[ ! -S "$colima_socket" ]]; then
  echo "Project-local Docker socket is missing. Run ./scripts/container.sh start first." >&2
  exit 1
fi

export HOME="$repo_root/.tooling/home"
export DOCKER_HOST="unix://$colima_socket"
export DOCKER_CONFIG="$repo_root/.tooling/docker-config"
mkdir -p "$DOCKER_CONFIG"

exec "$docker_bin" "$@"
