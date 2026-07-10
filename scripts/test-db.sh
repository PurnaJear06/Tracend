#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests_dir="$repo_root/supabase/tests/database"
container_id=""

cleanup() {
  if [[ -n "$container_id" ]]; then
    "$repo_root/scripts/docker.sh" rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ ! -d "$tests_dir" ]]; then
  echo "Database test directory is missing: $tests_dir" >&2
  exit 1
fi

container_id="$("$repo_root/scripts/docker.sh" create \
  --network container:supabase_db_Tracend \
  --env PGPASSWORD=postgres \
  public.ecr.aws/supabase/pg_prove:3.36 \
  sh -lc 'pg_prove -h 127.0.0.1 -U postgres -d postgres /tests/*_test.sql')"

"$repo_root/scripts/docker.sh" cp "$tests_dir/." "$container_id:/tests"
"$repo_root/scripts/docker.sh" start --attach "$container_id"
