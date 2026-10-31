#!/usr/bin/env bash
# Fails when a workflow that pull requests can trigger reads a repository secret.
#
#   scripts/check-workflow-secrets.sh [workflow-dir]   (default: .github/workflows)
#
# A pull request runs the branch's own code, so anything that code can reach it can leak. A
# workflow with a `pull_request` or `pull_request_target` trigger may therefore not reference
# `secrets` at all, apart from `secrets.GITHUB_TOKEN` (which `permissions:` already limits), and
# may not call another local workflow (which could receive secrets). Live model evaluations and
# deployments run from `workflow_dispatch`, `workflow_run` on main or `workflow_call` workflows
# that no pull request triggers. Comments are ignored.
set -euo pipefail

dir="${1:-.github/workflows}"
failures=0
checked=0

# The text of a workflow without YAML comments (whole-line and trailing ` #...`).
strip_comments() { sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]+#.*$//' "$1"; }

# True when the `on:` block (or the inline form) names a pull_request trigger.
triggers_on_pull_request() {
  strip_comments "$1" | awk '
    /^on:/ {
      inline = $0
      sub(/^on:[[:space:]]*/, "", inline)
      if (inline ~ /pull_request/) { found = 1 }
      inside = 1
      next
    }
    /^[^[:space:]]/ { inside = 0 }
    inside && /^[[:space:]]+(pull_request|pull_request_target)[[:space:]]*:/ { found = 1 }
    inside && /^[[:space:]]*-[[:space:]]*(pull_request|pull_request_target)[[:space:]]*$/ { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

shopt -s nullglob
for file in "$dir"/*.yml "$dir"/*.yaml; do
  checked=$((checked + 1))
  triggers_on_pull_request "$file" || continue

  # `secrets` inside an expression (`${{ ... }}`), or a `secrets:` key (`secrets: inherit`).
  secrets="$(strip_comments "$file" | grep -nE '(\$\{\{[^}]*\bsecrets\b|^[[:space:]]*(-[[:space:]]*)?secrets[[:space:]]*:)' |
    grep -vE '^[0-9]+:[^$]*\$\{\{[[:space:]]*secrets\.GITHUB_TOKEN[[:space:]]*\}\}[^$]*$' || true)"
  if [ -n "$secrets" ]; then
    while IFS= read -r line; do
      echo "::error file=$file::A pull request can trigger this workflow, so it may not read secrets: ${line}"
      failures=$((failures + 1))
    done <<<"$secrets"
  fi

  calls="$(strip_comments "$file" | grep -nE '^[[:space:]]*uses:[[:space:]]*\./' || true)"
  if [ -n "$calls" ]; then
    while IFS= read -r line; do
      echo "::error file=$file::A pull request can trigger this workflow, so it may not call a local workflow: ${line}"
      failures=$((failures + 1))
    done <<<"$calls"
  fi
done

if [ "$checked" -eq 0 ]; then
  echo "::error::No workflow files found in $dir" >&2
  exit 2
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures violation(s). Move the secret-using job to a workflow_dispatch workflow." >&2
  exit 1
fi
echo "Checked $checked workflow file(s): no pull-request workflow reads a secret."
