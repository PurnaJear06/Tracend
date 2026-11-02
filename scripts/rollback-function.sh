#!/usr/bin/env bash
# Redeploy one Edge Function from an earlier release.
#
# Usage: rollback-function.sh <function_name> [--to <release-tag>] [--dry-run] [--list]
#
# A release is a tag that deploy.yml (v2026.10.31-1853) or hotfix.yml (hf-v2026.10.31-1853)
# created after everything was live. The default target is the newest release tag whose
# supabase/functions tree differs from origin/main's: rolling back to identical code would change
# nothing. The tag's whole supabase/functions tree is checked out in a temporary worktree, so
# the function and the shared code it imports (_shared) come from the same release. The function
# is deployed from there with --use-api, then scripts/verify-live-function.sh compares what is
# live with that tree. Your checkout is not touched.
#
# This puts back old code only. The next deploy.yml run on main deploys main's code again, so
# revert the bad pull request on main right after (see docs/CI_CD_DEPLOYMENT.md). Migrations
# stay applied; they are additive, so older code keeps working against them.
#
# Options:
#   --to <tag>      Roll back to this release tag instead of the default
#   -n, --dry-run   Print what would be deployed and a summary of the difference; deploy nothing
#   -l, --list      List the recent release tags and whether their code matches origin/main
#   -h, --help      Show this help
#
# Environment:
#   SUPABASE_ACCESS_TOKEN   Required for deploy (or log in with the supabase wrapper)
#   PROJECT_REF             Supabase project ref (default: qsfzzsjenopqqqhvpyaw)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag_pattern='^(hf-)?v[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]{4}$'

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

die() {
  echo "rollback-function: $*" >&2
  exit 1
}

function_name=""
target_tag=""
dry_run=false
list_only=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      shift
      [[ $# -gt 0 ]] || die "--to needs a release tag"
      target_tag="$1"
      ;;
    -n | --dry-run) dry_run=true ;;
    -l | --list) list_only=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      [[ -z "$function_name" ]] || die "one function name at a time"
      function_name="$1"
      ;;
  esac
  shift
done

cd "$repo_root"
git fetch -q --tags origin main || die "cannot fetch origin"

functions_tree() { git rev-parse --verify -q "$1:supabase/functions" || true; }

main_tree="$(functions_tree refs/remotes/origin/main)"
[[ -n "$main_tree" ]] || die "origin/main has no supabase/functions"

# Release tags, newest first.
release_tags() {
  git tag --list 'v[0-9]*' 'hf-v[0-9]*' --sort=-creatordate | grep -E "$tag_pattern" || true
}

if [[ "$list_only" == "true" ]]; then
  release_tags | sed -n '1,10p' | while IFS= read -r tag; do
    marker="differs from origin/main"
    [[ "$(functions_tree "refs/tags/$tag")" != "$main_tree" ]] || marker="same code as origin/main"
    printf '%s  %s  %s\n' "$tag" "$(git rev-parse --short "refs/tags/$tag^{commit}")" "$marker"
  done
  exit 0
fi

[[ -n "$function_name" ]] || {
  echo "Missing function name." >&2
  usage >&2
  exit 2
}
[[ "$function_name" =~ ^[a-z0-9-]+$ ]] || die "invalid function name: $function_name"
git cat-file -e "refs/remotes/origin/main:supabase/functions/$function_name/index.ts" 2>/dev/null ||
  die "no function named $function_name on origin/main"

if [[ -n "$target_tag" ]]; then
  [[ "$target_tag" =~ $tag_pattern ]] || die "$target_tag is not a release tag (v... or hf-v...)"
  git rev-parse --verify -q "refs/tags/$target_tag" >/dev/null || die "no tag named $target_tag"
else
  while IFS= read -r tag; do
    if [[ "$(functions_tree "refs/tags/$tag")" != "$main_tree" ]]; then
      target_tag="$tag"
      break
    fi
  done < <(release_tags)
  [[ -n "$target_tag" ]] || die "no release tag has different function code than origin/main; nothing to roll back to"
fi

git cat-file -e "refs/tags/$target_tag:supabase/functions/$function_name/index.ts" 2>/dev/null ||
  die "$function_name did not exist in $target_tag"

target_commit="$(git rev-parse --short "refs/tags/$target_tag^{commit}")"
echo "Origin main: $(git rev-parse --short refs/remotes/origin/main)"
echo "Rolling back $function_name to $target_tag ($target_commit, $(git log -1 --format=%cs "refs/tags/$target_tag^{commit}"))"
echo "Its whole supabase/functions tree from that release is deployed: the function and _shared."

if [[ "$dry_run" == "true" ]]; then
  echo ""
  echo "Dry run: nothing will be deployed."
  echo "Changed between $target_tag and origin/main (rolling back reverts these):"
  git diff --stat "refs/tags/$target_tag" refs/remotes/origin/main -- supabase/functions | sed 's/^/  /'
  echo "Functions whose own folder differs:"
  git diff --name-only "refs/tags/$target_tag" refs/remotes/origin/main -- supabase/functions |
    awk -F/ 'NF >= 4 && $3 != "_shared" && $3 != "_tests" { print $3 }' | sort -u | sed 's/^/  /'
  echo "Run again without --dry-run to deploy $function_name from $target_tag."
  exit 0
fi

project_ref="${PROJECT_REF:-qsfzzsjenopqqqhvpyaw}"
mkdir -p "$repo_root/.tooling"
scratch="$(mktemp -d "$repo_root/.tooling/rollback-function.XXXXXX")"
tree="$scratch/tree"
cleanup() {
  git -C "$repo_root" worktree remove --force "$tree" >/dev/null 2>&1 || true
  rm -rf "$scratch"
  git -C "$repo_root" worktree prune
}
trap cleanup EXIT

git worktree add -q --detach "$tree" "refs/tags/$target_tag"
ln -s "$repo_root/.tooling" "$tree/.tooling"
# The tag's tree is the code to deploy; the deploy and verify scripts are today's, so an old
# release cannot bring an old (or missing) copy of them.
cp "$repo_root/scripts/deploy-function.sh" "$repo_root/scripts/verify-live-function.sh" "$tree/scripts/"

echo "Deploying $function_name to $project_ref from $target_tag ..."
(cd "$tree" && PROJECT_REF="$project_ref" scripts/deploy-function.sh "$function_name")
echo "Confirming what is live matches $target_tag ..."
(cd "$tree" && PROJECT_REF="$project_ref" scripts/verify-live-function.sh "$function_name")

echo ""
echo "$function_name now runs the code from $target_tag."
echo "The next deploy.yml run puts main's code back. Revert the bad pull request on main now."
