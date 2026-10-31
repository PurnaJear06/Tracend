#!/usr/bin/env bash
# Tests for scripts/check-workflow-secrets.sh against fixture workflows. No network, no secrets.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-workflow-secrets.sh"
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

run_case dispatch-and-pr-secrets-inherit 1 <<'YML'
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

run_case pr-toJSON-secrets 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - run: echo '${{ toJSON(secrets) }}'
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

run_case pr-secret-only-in-comment 0 <<'YML'
on:
  pull_request:
# Uses secrets.DEEPSEEK_API_KEY nowhere.
jobs:
  a:
    steps:
      - run: echo ok # secrets.X would be wrong here
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

run_case workflow-run-with-secret 0 <<'YML'
on:
  workflow_run:
    workflows: [CI]
    branches: [main]
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
YML

run_case pr-in-input-description-only 0 <<'YML'
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

run_case pr-github-token-plus-other-secret 1 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - env:
          KEY: ${{ secrets.GITHUB_TOKEN || secrets.DEEPSEEK_API_KEY }}
YML

run_case pr-word-secrets-outside-expression 0 <<'YML'
on:
  pull_request:
jobs:
  a:
    steps:
      - name: Scan full git history for secrets
        run: bash scripts/check-workflow-secrets.sh
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
