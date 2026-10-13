#!/usr/bin/env bash
# npm for the website in site/, with the npm cache kept on the external SSD (.tooling).
#   ./scripts/site.sh install | run dev | run build | run preview
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tool/versions.env
source "$ROOT/tool/versions.env"
have="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo none)"
if [ "$have" != "$NODE_MAJOR" ]; then
  echo "site.sh: Node $NODE_MAJOR is required, found ${have}." >&2
  exit 1
fi
export npm_config_cache="$ROOT/.tooling/npm-cache"
export ASTRO_TELEMETRY_DISABLED=1
cd "$ROOT/site"
exec npm "$@"
