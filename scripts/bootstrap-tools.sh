#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tool/versions.env"

tooling_dir="$repo_root/.tooling"
supabase_dir="$tooling_dir/supabase"
deno_dir="$tooling_dir/deno"

mkdir -p "$tooling_dir/home" "$supabase_dir" "$deno_dir"

npm install \
  --prefix "$supabase_dir" \
  "supabase@$SUPABASE_CLI_VERSION" \
  --no-save

npm install \
  --prefix "$deno_dir" \
  "deno@$DENO_VERSION" \
  --no-save

actual_version="$(
  HOME="$tooling_dir/home" \
    "$supabase_dir/node_modules/.bin/supabase" --version
)"

if [[ "$actual_version" != "$SUPABASE_CLI_VERSION" ]]; then
  echo "Expected Supabase CLI $SUPABASE_CLI_VERSION, found $actual_version" >&2
  exit 1
fi

actual_deno_version="$(
  "$deno_dir/node_modules/.bin/deno" --version | awk 'NR == 1 { print $2 }'
)"

if [[ "$actual_deno_version" != "$DENO_VERSION" ]]; then
  echo "Expected Deno $DENO_VERSION, found $actual_deno_version" >&2
  exit 1
fi

echo "Project-local Supabase CLI $actual_version and Deno $actual_deno_version are ready."
