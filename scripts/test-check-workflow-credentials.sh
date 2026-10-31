#!/usr/bin/env bash
# Tests for scripts/check-workflow-credentials.sh against fixture workflows. No network, no
# credentials. Needs yq and jq, like the script.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-workflow-credentials.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# run_case name expected-exit  (workflow text on stdin)
run_case() {
  local name="$1" expected="$2" dir="$root/dir with space/$1"
  mkdir -p "$dir"
  cat >"$dir/w.yml"
  local actual=0
  bash "$script" "$dir" >/dev/null 2>&1 || actual=$?
  if [ "$actual" = "$expected" ]; then pass "$name"; else fail "$name (expected exit $expected, got $actual)"; fi
}

# ── violations ────────────────────────────────────────────────────────
run_case pr-with-secret 1 <<'YML'
on:
  pull_request:
    types: [labeled]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo
        env:
          KEY: ${{ secrets.DEEPSEEK_API_KEY }}
YML

run_case pr-target-with-secret 1 <<'YML'
on:
  pull_request_target:
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case inline-pr-with-secret 1 <<'YML'
on: [push, pull_request]
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case string-form-pr 1 <<'YML'
on: pull_request
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case quoted-on-key 1 <<'YML'
"on":
  pull_request:
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case true-as-on-key 1 <<'YML'
true:
  pull_request:
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case quoted-event-name 1 <<'YML'
on:
  "pull_request":
  'push':
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case multi-line-flow-sequence 1 <<'YML'
on: [
  push,
  "pull_request"
]
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case multi-line-block-sequence 1 <<'YML'
on:
  - push
  - pull_request
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case expression-split-over-lines 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - env:
          KEY: ${{
            secrets.X }}
YML

run_case format-expression 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - env:
          KEY: ${{ format('{0}', secrets.X) }}
YML

run_case hash-earlier-on-the-same-line 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - run: echo "a # b ${{ secrets.X }}"
YML

run_case pr-github-token-plus-other-secret 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.GITHUB_TOKEN || secrets.DEEPSEEK_API_KEY }}
YML

run_case pr-toJSON-secrets 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - run: echo '${{ toJSON(secrets) }}'
YML

run_case secrets-inherit 1 <<'YML'
on:
  workflow_dispatch:
  pull_request:
jobs:
  a:
    uses: ./.github/workflows/other.yml
    secrets: inherit
YML

run_case pr-calls-local-workflow 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    uses: ./.github/workflows/other.yml
YML

run_case secrets-in-a-comment-fails-closed 1 <<'YML'
on:
  pull_request:
# Uses secrets nowhere.
jobs:
  a:
    steps:
      - run: echo ok
YML

for event in pull_request_review pull_request_review_comment issue_comment; do
  run_case "event-$event" 1 <<YML
on:
  $event:
jobs:
  a:
    steps:
      - env:
          KEY: \${{ secrets.X }}
YML
done

run_case workflow-run-without-branches 1 <<'YML'
on:
  workflow_run:
    workflows: [CI]
    types: [completed]
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case workflow-run-other-branches 1 <<'YML'
on:
  workflow_run:
    workflows: [CI]
    branches: [main, feature/**]
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case workflow-run-star-branches 1 <<'YML'
on:
  workflow_run:
    workflows: [CI]
    branches: ["**"]
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

# ── allowed ───────────────────────────────────────────────────────────
run_case workflow-run-main-only 0 <<'YML'
on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [main]
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
YML

run_case workflow-run-main-string 0 <<'YML'
on:
  workflow_run:
    workflows: [CI]
    branches: main
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
YML

run_case pr-github-token-only 0 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
YML

run_case pr-without-the-word 0 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - name: Scan full git history for leaked credentials
        run: echo ok
YML

run_case dispatch-only-with-secret 0 <<'YML'
on:
  workflow_dispatch:
    inputs:
      model:
        required: false
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.DEEPSEEK_API_KEY }}
YML

run_case push-and-call-with-secret 0 <<'YML'
on:
  push:
    branches: [main]
  workflow_call:
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

run_case pr-word-only-in-input-description 0 <<'YML'
on:
  workflow_dispatch:
    inputs:
      note:
        description: pull_request is not a trigger here
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.X }}
YML

# The real workflows pass.
repo="$(cd "$(dirname "$script")/.." && pwd)"
if bash "$script" "$repo/.github/workflows" >/dev/null 2>&1; then
  pass "repository workflows"
else
  fail "repository workflows"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "All tests passed"
