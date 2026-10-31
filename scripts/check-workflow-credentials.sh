#!/usr/bin/env bash
# Fails when a workflow that untrusted events can start reads a repository secret.
#
#   scripts/check-workflow-credentials.sh [workflow-dir]   (default: .github/workflows)
#
# A pull request, an issue, a discussion, a comment or a run of another workflow can carry an
# outsider's code or text,
# so anything that code can reach it can leak. A workflow with an untrusted trigger may therefore
# not mention `secrets` at all, apart from the exact token `secrets.GITHUB_TOKEN` (which
# `permissions:` already limits), and may not call a local reusable workflow (which could receive
# secrets). Untrusted triggers: every `pull_request*` event (pull_request, pull_request_target,
# pull_request_review, pull_request_review_comment), `issues`, `issue_comment`, `discussion`,
# `discussion_comment`, `fork`, `watch`, `gollum` and `workflow_run`. One
# `workflow_run` is trusted: the one limited to `branches: [main]`, because it then runs main's
# code (deploy.yml). Live model evaluations run from `workflow_dispatch`, which only an account
# with write access can start.
#
# The trigger is read with yq (mikefarah v4, preinstalled on GitHub's ubuntu runners), so quoted
# keys, `"on"` versus `true`, strings, lists, flow sequences and maps all read the same way. The
# file is then searched as raw text, comments included: the guard fails closed, so a comment that
# says the word `secrets` in such a workflow is a violation too.
set -euo pipefail

dir="${1:-.github/workflows}"
failures=0
checked=0

if ! command -v yq >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "::error::check-workflow-credentials.sh needs yq (mikefarah v4) and jq on PATH. Install: brew install yq jq" >&2
  exit 2
fi

# The untrusted trigger events of a workflow, one per line.
untrusted_events() {
  yq -o=json '.' "$1" | jq -r '
    (if has("on") then .on elif has("true") then .["true"] else null end) as $on
    | ($on | if type == "string" then [.]
             elif type == "array" then .
             elif type == "object" then keys
             else [] end) as $events
    | $events[]
    | select(test("^pull_request") or
             IN("issues", "issue_comment", "discussion", "discussion_comment",
                "fork", "watch", "gollum", "workflow_run"))
    | if . == "workflow_run" and
         (($on | type) == "object") and
         (($on.workflow_run.branches // null) as $b
           | $b == "main" or $b == ["main"])
      then empty else . end'
}

shopt -s nullglob
for file in "$dir"/*.yml "$dir"/*.yaml; do
  checked=$((checked + 1))
  events="$(untrusted_events "$file")"
  [ -n "$events" ] || continue
  event_list="$(printf '%s' "$events" | paste -sd, -)"

  # Every mention of `secrets` except the exact token secrets.GITHUB_TOKEN.
  mentions="$(sed -E 's/secrets\.GITHUB_TOKEN([^A-Za-z0-9_]|$)/\1/g' "$file" | grep -inE 'secrets' || true)"
  if [ -n "$mentions" ]; then
    while IFS= read -r line; do
      echo "::error file=$file::Triggered by $event_list, so it may not mention secrets: ${line}"
      failures=$((failures + 1))
    done <<<"$mentions"
  fi

  calls="$(grep -nE '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*["'"'"']?\./' "$file" || true)"
  if [ -n "$calls" ]; then
    while IFS= read -r line; do
      echo "::error file=$file::Triggered by $event_list, so it may not call a local workflow: ${line}"
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
echo "Checked $checked workflow file(s): no untrusted-trigger workflow reads a secret."
