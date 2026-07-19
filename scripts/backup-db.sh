#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backup_base="$repo_root/.tooling/backups"
date_stamp="$(date '+%Y-%m-%d')"
backup_dir="$backup_base/$date_stamp"

usage() {
  cat <<EOF
Usage: backup-db.sh [OPTIONS]

Dump the hosted Supabase database via the session pooler and save a
timestamped backup with SHA-256 manifest.

Options:
  --data-only     Data only (pg_dump --data-only), requires pg_dump and pooler
  --schema-only   Schema only via supabase db dump (default, no password needed)
  -h, --help      Show this help

Environment:
  PGPASSWORD       Pooler password (required for --data-only)
  POOLER_HOST      Pooler host (default: aws-0-ap-southeast-1.pooler.supabase.com)
  POOLER_PORT      Pooler port (default: 6543)
  PROJECT_REF      Supabase project ref (default: qsfzzsjenopqqqhvpyaw)
EOF
  exit 0
}

MODE="schema"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-only)   MODE="data" ;;
    --schema-only) MODE="schema" ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

mkdir -p "$backup_dir"

if [[ "$MODE" == "data" ]]; then
  if ! command -v pg_dump &>/dev/null; then
    echo "pg_dump not found. Install PostgreSQL client tools or use --schema-only." >&2
    exit 1
  fi
  if [[ -z "${PGPASSWORD:-}" ]]; then
    echo "PGPASSWORD env var is required for --data-only." >&2
    exit 1
  fi
  pooler_host="${POOLER_HOST:-aws-1-ap-southeast-1.pooler.supabase.com}"
  pooler_port="${POOLER_PORT:-6543}"
  project_ref="${PROJECT_REF:-qsfzzsjenopqqqhvpyaw}"
  pooler_user="postgres.${project_ref}"
  pg_dump \
    "postgresql://${pooler_user}:${PGPASSWORD}@${pooler_host}:${pooler_port}/postgres" \
    --no-owner --no-acl --data-only \
    > "$backup_dir/database_data.sql"
  echo "Data dump saved to $backup_dir/database_data.sql"
else
  "$repo_root/scripts/supabase.sh" db dump --linked \
    > "$backup_dir/database_schema.sql"
  echo "Schema dump saved to $backup_dir/database_schema.sql"
fi

manifest="$backup_dir/SHA256SUMS"
if command -v shasum &>/dev/null; then
  (cd "$backup_dir" && shasum -a 256 *.sql > "$manifest")
elif command -v sha256sum &>/dev/null; then
  (cd "$backup_dir" && sha256sum *.sql > "$manifest")
else
  echo "No sha256 tool found, skipping manifest." >&2
fi

echo "Backup complete: $backup_dir"
