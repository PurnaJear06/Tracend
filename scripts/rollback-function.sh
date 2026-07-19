#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
Usage: rollback-function.sh <function_name>

Redeploy the prior version of a Supabase Edge Function by checking out the
previous git revision for that function's directory.

Options:
  -n, --dry-run   Show what would be deployed without actually deploying
  -l, --list      List recent commits for the function (last 10)
  -h, --help      Show this help

Environment:
  SUPABASE_ACCESS_TOKEN   Required for deploy (or set via supabase login)
  PROJECT_REF             Supabase project ref (default: qsfzzsjenopqqqhvpyaw)
EOF
  exit 0
}

if [[ $# -eq 0 ]]; then
  echo "Missing function name." >&2
  usage
fi

FUNCTION_NAME="$1"
DRY_RUN=false
LIST_ONLY=false
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=true ;;
    -l|--list)    LIST_ONLY=true ;;
    -h|--help)    usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

FUNCTION_DIR="supabase/functions/$FUNCTION_NAME"
if [[ ! -d "$repo_root/$FUNCTION_DIR" ]]; then
  echo "Function directory not found: $FUNCTION_DIR" >&2
  exit 1
fi

if [[ "$LIST_ONLY" == "true" ]]; then
  git -C "$repo_root" log --oneline -10 -- "$FUNCTION_DIR"
  exit 0
fi

PREV_COMMIT=$(git -C "$repo_root" log --oneline -2 -- "$FUNCTION_DIR" | tail -1 | cut -d' ' -f1)
if [[ -z "$PREV_COMMIT" ]]; then
  echo "No prior commit found for $FUNCTION_DIR" >&2
  exit 1
fi

PREV_MSG=$(git -C "$repo_root" log --oneline -1 -- "$PREV_COMMIT")
CURRENT_HEAD=$(git -C "$repo_root" rev-parse --short HEAD)

echo "Current HEAD: $CURRENT_HEAD"
echo "Rolling back to: $PREV_COMMIT ($PREV_MSG)"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run — would deploy $FUNCTION_NAME from $PREV_COMMIT"
  git -C "$repo_root" diff --stat "$PREV_COMMIT"..HEAD -- "$FUNCTION_DIR"
  exit 0
fi

echo "Checking out $FUNCTION_DIR from $PREV_COMMIT ..."
git -C "$repo_root" checkout "$PREV_COMMIT" -- "$FUNCTION_DIR"

project_ref="${PROJECT_REF:-qsfzzsjenopqqqhvpyaw}"
echo "Deploying $FUNCTION_NAME to $project_ref ..."
if "$repo_root/scripts/supabase.sh" functions deploy "$FUNCTION_NAME" \
  --project-ref "$project_ref" --use-api; then
  echo "Deploy succeeded."
else
  echo "Deploy failed — restoring working tree." >&2
  git -C "$repo_root" checkout HEAD -- "$FUNCTION_DIR"
  exit 1
fi

echo ""
echo "Restore your working tree when ready:"
echo "  git checkout HEAD -- $FUNCTION_DIR"
