#!/usr/bin/env bash
# Compare privileges in the deploy restore drill's database with the state the migrations create.
#
# `supabase db dump` comments out every GRANT and REVOKE line that names a schema it leaves out of
# the dump (auth, extensions, net, pgmq, storage, vault, ...; see `supabase db dump --dry-run`). A
# function whose signature uses a type from such a schema therefore comes back from a restore with
# default privileges: EXECUTE for PUBLIC, anon and authenticated. The drill's table count cannot see
# that, so deploy.yml runs this script after the restore.
#
# Usage:
#   scripts/restore-privileges.sh versions <migration-list-output>
#       Print the versions in the Remote column of `supabase migration list`, one per line.
#   scripts/restore-privileges.sh history <applied-versions>
#       Print the version to reset to when the local migrations are ahead of those applied, or
#       "current" when they match. Fails when the applied history is not a prefix of the local one.
#   scripts/restore-privileges.sh snapshot
#       Print the privilege snapshot of the local Supabase database.
#   scripts/restore-privileges.sh report <migrations-snapshot> <restored-snapshot>
#       Print every difference between two snapshots. Fails when there is one.
#   scripts/restore-privileges.sh compare <migrations-snapshot> <applied-versions>
#       Snapshot the restored database, reset it to the applied version when migrations are pending
#       (the migrations snapshot then comes from that reset), and report the differences. Run it
#       from the repository root: it calls `supabase db reset` and `supabase migration list`.
#
# A snapshot covers the public and private schemas: schema USAGE and CREATE, function EXECUTE,
# table, view and sequence privileges for anon and authenticated, and the RLS enabled and forced
# flags. Extension members are skipped because their extensions own them. Every query reads the
# catalogs only, so the output names objects and never contains rows.
#
# Environment:
#   MIGRATIONS_DIR  migration files to compare the applied history with (default: supabase/migrations)
set -euo pipefail

die() { echo "restore-privileges: $*" >&2; exit 1; }

tab="$(printf '\t')"
export LC_ALL=C

parse_versions() {
  awk -F'|' 'NF >= 3 { gsub(/[[:space:]]/, "", $2); if ($2 ~ /^[0-9]{14}$/) print $2 }' "$1" | sort -u
}

local_versions() {
  local dir="${MIGRATIONS_DIR:-supabase/migrations}" file
  [ -d "$dir" ] || die "migration directory not found: $dir"
  for file in "$dir"/*.sql; do
    [ -e "$file" ] || continue
    file="$(basename "$file")"
    printf '%s\n' "${file%%_*}"
  done | sort -u
}

target_version() {
  local applied="$1" latest_applied latest_local expected
  [ -s "$applied" ] || die "no applied migration versions in $applied"
  latest_applied="$(tail -n 1 "$applied")"
  latest_local="$(local_versions | tail -n 1)"
  expected="$(local_versions | awk -v latest="$latest_applied" '$0 <= latest')"
  if [ "$expected" != "$(cat "$applied")" ]; then
    echo "Applied and local migration histories differ up to $latest_applied:" >&2
    { diff <(printf '%s\n' "$expected") "$applied" || true; } |
      sed -n 's/^</  local only:/p; s/^>/  applied only:/p' >&2
    die "the applied migrations are not a prefix of the local migrations"
  fi
  if [ "$latest_applied" = "$latest_local" ]; then
    echo current
  else
    echo "$latest_applied"
  fi
}

db_container() {
  local container
  container="$(docker ps --filter 'name=supabase_db_' --format '{{.Names}}' | head -1)"
  [ -n "$container" ] || die "local Supabase database container not found"
  printf '%s' "$container"
}

snapshot() {
  local container
  container="$(db_container)"
  docker exec -i "$container" psql --username postgres --dbname postgres \
    --no-psqlrc --quiet --tuples-only --no-align --field-separator "$tab" \
    --variable ON_ERROR_STOP=1 <<'SQL' | sort
with roles(role_name) as (values ('anon'), ('authenticated')),
schemas as (
  select oid, nspname from pg_namespace where nspname in ('public', 'private')
),
functions as (
  select p.oid,
    format('function %I.%I(%s)', s.nspname, p.proname, pg_get_function_identity_arguments(p.oid))
      as object
  from pg_proc as p
  join schemas as s on s.oid = p.pronamespace
  where not exists (
    select 1 from pg_depend as d
    where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e'
  )
),
relations as (
  select c.oid, c.relkind, c.relrowsecurity, c.relforcerowsecurity,
    format('%s %I.%I',
      case c.relkind
        when 'S' then 'sequence'
        when 'v' then 'view'
        when 'm' then 'materialized view'
        when 'f' then 'foreign table'
        else 'table'
      end,
      s.nspname, c.relname) as object
  from pg_class as c
  join schemas as s on s.oid = c.relnamespace
  where c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
    and not exists (
      select 1 from pg_depend as d
      where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e'
    )
),
entries(entry, granted) as (
  select format('schema %I: %s %s', s.nspname, r.role_name, v.privilege),
    has_schema_privilege(r.role_name, s.oid, v.privilege)
  from schemas as s cross join roles as r
  cross join (values ('USAGE'), ('CREATE')) as v(privilege)
  union all
  select format('%s: %s EXECUTE', f.object, r.role_name),
    has_function_privilege(r.role_name, f.oid, 'EXECUTE')
  from functions as f cross join roles as r
  union all
  select format('%s: %s %s', t.object, r.role_name, v.privilege),
    has_table_privilege(r.role_name, t.oid, v.privilege)
  from relations as t cross join roles as r
  cross join (
    values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
  ) as v(privilege)
  where t.relkind <> 'S'
  union all
  select format('%s: %s %s', t.object, r.role_name, v.privilege),
    has_sequence_privilege(r.role_name, t.oid, v.privilege)
  from relations as t cross join roles as r
  cross join (values ('USAGE'), ('SELECT'), ('UPDATE')) as v(privilege)
  where t.relkind = 'S'
  union all
  select format('%s: row level security', t.object), t.relrowsecurity
  from relations as t where t.relkind in ('r', 'p')
  union all
  select format('%s: forced row level security', t.object), t.relforcerowsecurity
  from relations as t where t.relkind in ('r', 'p')
)
select entry, case when granted then 'yes' else 'no' end from entries;
SQL
}

report() {
  local expected="$1" restored="$2" differences
  [ -s "$expected" ] || die "migrations snapshot is missing or empty: $expected"
  [ -s "$restored" ] || die "restored snapshot is missing or empty: $restored"
  differences="$(join -t "$tab" -a 1 -a 2 -e absent -o 0,1.2,2.2 \
    <(sort -t "$tab" -k1,1 "$expected") <(sort -t "$tab" -k1,1 "$restored") |
    awk -F'\t' '$2 != $3 { printf "  %s (migrations: %s, restored: %s)\n", $1, $2, $3 }')"
  if [ -n "$differences" ]; then
    echo "Restored privileges differ from the migrations:"
    printf '%s\n' "$differences"
    return 1
  fi
  echo "Restored privileges match the migrations ($(wc -l <"$expected" | tr -d ' ') entries)."
}

compare() {
  local expected="$1" applied="$2" target pending reached
  target="$(target_version "$applied")"
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  snapshot >"$work/restored.tsv"
  if [ "$target" != current ]; then
    # `db reset --version` is taken as the CLI's global --version flag (2.101.0), so reset with
    # --last, which leaves out the newest N local migrations, and confirm where it stopped.
    pending="$(local_versions | awk -v latest="$target" '$0 > latest' | wc -l | tr -d ' ')"
    echo "Production has applied migrations up to $target; this commit adds $pending more."
    echo "Resetting the drill database to $target for the migrations snapshot."
    supabase db reset --last "$pending" >"$work/reset.log" 2>&1 || {
      cat "$work/reset.log" >&2
      die "supabase db reset --last $pending failed"
    }
    supabase migration list --local >"$work/migration-list.txt"
    reached="$(parse_versions "$work/migration-list.txt" | tail -n 1)"
    [ "$reached" = "$target" ] || die "the drill database reset to ${reached:-nothing}, not $target"
    snapshot >"$work/migrations.tsv"
    expected="$work/migrations.tsv"
  fi
  report "$expected" "$work/restored.tsv"
}

[ "$#" -ge 1 ] || die "usage: $0 versions|history|snapshot|report|compare ..."
command="$1"
shift
case "$command" in
  versions)
    [ "$#" -eq 1 ] || die "usage: $0 versions <migration-list-output>"
    versions="$(parse_versions "$1")"
    [ -n "$versions" ] || die "no applied migration versions found in $1"
    printf '%s\n' "$versions"
    ;;
  history)
    [ "$#" -eq 1 ] || die "usage: $0 history <applied-versions>"
    target_version "$1"
    ;;
  snapshot)
    [ "$#" -eq 0 ] || die "usage: $0 snapshot"
    snapshot
    ;;
  report)
    [ "$#" -eq 2 ] || die "usage: $0 report <migrations-snapshot> <restored-snapshot>"
    report "$1" "$2"
    ;;
  compare)
    [ "$#" -eq 2 ] || die "usage: $0 compare <migrations-snapshot> <applied-versions>"
    compare "$1" "$2"
    ;;
  *) die "unknown command: $command" ;;
esac
