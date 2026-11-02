#!/usr/bin/env bash
# Redeploy one Edge Function from an earlier release.
#
# Usage: rollback-function.sh <function_name> [--to <release-tag>] [--dry-run] [--list]
#
# A release is a tag that deploy.yml (v2026.10.31-1853) or hotfix.yml (hf-v2026.10.31-1853)
# created after everything was live. The default target is the newest release tag whose bundle of
# this function differs from origin/main's: its own folder plus every file it imports, followed
# through relative imports into _shared. A release that changed only another function is skipped,
# because rolling back to identical code would change nothing. The tag's whole supabase/functions
# tree is checked out in a temporary worktree, so the function and the shared code it imports
# come from the same release. The function
# is deployed from there with --use-api, then scripts/verify-live-function.sh compares what is
# live with that tree. Your checkout is not touched.
#
# This puts back old code only. The next deploy.yml run on main deploys main's code again, so
# revert the bad pull request on main right after (see docs/CI_CD_DEPLOYMENT.md). Migrations
# stay applied; they are additive, so older code keeps working against them.
#
# Options:
#   --to <tag>      Roll back to this release tag instead of the default. Refused when that
#                   release's bundle of the function is identical to origin/main's, unless --force
#   --force         Allow --to a release whose bundle of the function is identical
#   -n, --dry-run   Print what would be deployed and a summary of the difference; deploy nothing
#   -l, --list      List the recent release tags and whether their code matches origin/main
#                   (the named function's bundle, or the whole tree without a name)
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
force=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      shift
      [[ $# -gt 0 ]] || die "--to needs a release tag"
      target_tag="$1"
      ;;
    -n | --dry-run) dry_run=true ;;
    --force) force=true ;;
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

# The files that make up one function's deployed bundle at a git ref, one "path blob" line each:
# every non-test file in its folder, the functions-wide deno.json, and every file reached by
# following relative imports (from, import, export ... from, import()) from those. Nothing is
# checked out: files are read from the git objects.
bundle_files() { # ref function
  python3 -I - "$repo_root" "$1" "$2" <<'BUNDLE_PY'
import posixpath
import re
import subprocess
import sys

repo, ref, name = sys.argv[1:4]
base = "supabase/functions"
specifier = re.compile(r"""(?:\bfrom\s*|\bimport\s*\(?\s*)["'](\.{1,2}/[^"']+)["']""")


def git(*args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, check=False)


def is_test(path):
    return path.endswith("_test.ts")


# One listing gives every path and blob at the ref; file contents come from one cat-file process.
blobs = {}
for line in git("ls-tree", "-r", ref, base).stdout.decode().splitlines():
    meta, path = line.split("\t", 1)
    blobs[path] = meta.split()[2]
reader = subprocess.Popen(
    ["git", "-C", repo, "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE
)


def read(sha):
    reader.stdin.write(sha.encode() + b"\n")
    reader.stdin.flush()
    size = int(reader.stdout.readline().split()[2])
    data = reader.stdout.read(size)
    reader.stdout.read(1)
    return data.decode("utf-8", "replace")


pending = [p for p in blobs if p.startswith(f"{base}/{name}/") and not is_test(p)]
if f"{base}/deno.json" in blobs:
    pending.append(f"{base}/deno.json")
seen = {}
while pending:
    path = pending.pop()
    if path in seen:
        continue
    sha = blobs.get(path)
    seen[path] = sha or "missing"
    if not sha or not path.endswith((".ts", ".tsx", ".js", ".mjs")):
        continue
    for rel in specifier.findall(read(sha)):
        target = posixpath.normpath(posixpath.join(posixpath.dirname(path), rel))
        if target.startswith(base + "/") and not is_test(target):
            pending.append(target)
reader.stdin.close()
reader.wait()
for path in sorted(seen):
    print(path, seen[path])
BUNDLE_PY
}

bundle_digest() { # ref function
  bundle_files "$1" "$2" | git hash-object --stdin
}

# Whether a function's folder exists at a ref.
has_function() { # ref function
  git cat-file -e "$1:supabase/functions/$2/index.ts" 2>/dev/null
}

main_tree="$(functions_tree refs/remotes/origin/main)"
[[ -n "$main_tree" ]] || die "origin/main has no supabase/functions"

# Release tags, newest first.
release_tags() {
  git tag --list 'v[0-9]*' 'hf-v[0-9]*' --sort=-creatordate | grep -E "$tag_pattern" || true
}

if [[ "$list_only" == "true" ]]; then
  if [[ -n "$function_name" ]]; then
    main_digest="$(bundle_digest refs/remotes/origin/main "$function_name")"
  fi
  release_tags | sed -n '1,10p' | while IFS= read -r tag; do
    marker="differs from origin/main"
    if [[ -n "$function_name" ]]; then
      if ! has_function "refs/tags/$tag" "$function_name"; then
        marker="$function_name did not exist"
      elif [[ "$(bundle_digest "refs/tags/$tag" "$function_name")" == "$main_digest" ]]; then
        marker="same $function_name code as origin/main"
      fi
    elif [[ "$(functions_tree "refs/tags/$tag")" == "$main_tree" ]]; then
      marker="same code as origin/main"
    fi
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
has_function refs/remotes/origin/main "$function_name" || die "no function named $function_name on origin/main"
main_digest="$(bundle_digest refs/remotes/origin/main "$function_name")"

if [[ -n "$target_tag" ]]; then
  [[ "$target_tag" =~ $tag_pattern ]] || die "$target_tag is not a release tag (v... or hf-v...)"
  git rev-parse --verify -q "refs/tags/$target_tag" >/dev/null || die "no tag named $target_tag"
  has_function "refs/tags/$target_tag" "$function_name" || die "$function_name did not exist in $target_tag"
  if [[ "$(bundle_digest "refs/tags/$target_tag" "$function_name")" == "$main_digest" && "$force" != "true" ]]; then
    die "$target_tag has the same $function_name code as origin/main, so deploying it would change nothing. Use --force to deploy it anyway."
  fi
else
  while IFS= read -r tag; do
    has_function "refs/tags/$tag" "$function_name" || continue
    if [[ "$(bundle_digest "refs/tags/$tag" "$function_name")" != "$main_digest" ]]; then
      target_tag="$tag"
      break
    fi
  done < <(release_tags)
  [[ -n "$target_tag" ]] ||
    die "no release tag has different $function_name code than origin/main (its folder and the files it imports); nothing to roll back to. Name a release with --to <tag> (and --force if its code is identical)."
fi

target_commit="$(git rev-parse --short "refs/tags/$target_tag^{commit}")"
echo "Origin main: $(git rev-parse --short refs/remotes/origin/main)"
echo "Rolling back $function_name to $target_tag ($target_commit, $(git log -1 --format=%cs "refs/tags/$target_tag^{commit}"))"
echo "Its whole supabase/functions tree from that release is deployed: the function and the shared code it imports."

if [[ "$dry_run" == "true" ]]; then
  echo ""
  echo "Dry run: nothing will be deployed."
  changed="$(diff <(bundle_files "refs/tags/$target_tag" "$function_name") <(bundle_files refs/remotes/origin/main "$function_name") |
    sed -n 's/^[<>] \([^ ]*\) .*/\1/p' | sort -u)" || true
  echo "Files of the $function_name bundle that differ between $target_tag and origin/main (rolling back reverts these):"
  if [[ -n "$changed" ]]; then
    printf '%s\n' "$changed" | sed 's/^/  /'
  else
    echo "  (none: the bundles are identical)"
  fi
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
