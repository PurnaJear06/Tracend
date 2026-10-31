#!/usr/bin/env bash
# Tests for scripts/retire-functions.sh with a stub Supabase CLI. No network, no secrets.
# The working directory contains a space on purpose: the primary checkout path has one.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/retire-functions.sh"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
base="$root/dir with space"
mkdir -p "$base/functions"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
expect_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected: $2 | actual: $3)"; fi
}

# The stub keeps the "deployed" names in $base/live (one per line), answers
# `functions list -o json` from it, removes a name on `functions delete`, and
# records every call in $base/calls.
cat >"$base/cli" <<'STUB'
#!/usr/bin/env bash
base="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$*" >>"$base/calls"
if [[ "$1 $2" == "functions list" ]]; then
  if [[ -f "$base/list-fails" ]]; then
    echo "boom" >&2
    exit 1
  fi
  jq -R '{slug: ., name: .}' <"$base/live" | jq -s '.'
elif [[ "$1 $2" == "functions delete" ]]; then
  grep -vxF -- "$3" "$base/live" >"$base/live.next" || true
  mv "$base/live.next" "$base/live"
else
  exit 2
fi
STUB
chmod +x "$base/cli"

for name in coach-chat health-check; do mkdir -p "$base/functions/$name"; done
printf '# retired\nold-one\n' >"$base/retired.txt"

run() { # args...
  SUPABASE_CLI="$base/cli" FUNCTIONS_DIR="$base/functions" \
    RETIRED_FUNCTIONS_FILE="$base/retired.txt" bash "$script" "$@"
}
reset() { # live names...
  : >"$base/calls"
  rm -f "$base/list-fails"
  printf '%s\n' "$@" >"$base/live"
}
deletes() { grep -c 'functions delete' "$base/calls" || true; }

# 1. A retired function that is deployed is deleted; the others are untouched.
reset coach-chat health-check old-one
run >/dev/null
expect_eq "deletes the retired function" "1" "$(deletes)"
expect_eq "targets the project" "functions delete old-one --project-ref qsfzzsjenopqqqhvpyaw" \
  "$(grep 'functions delete' "$base/calls")"
expect_eq "keeps every other function" "coach-chat health-check" "$(tr '\n' ' ' <"$base/live" | sed 's/ $//')"

# 2. Idempotent: nothing deployed, nothing deleted.
reset coach-chat health-check
run >/dev/null
expect_eq "absent retired function is a no-op" "0" "$(deletes)"

# 3. Never deletes a function that is not listed, even when it has no directory.
reset coach-chat health-check old-one stray-one
run >/dev/null
expect_eq "only the listed name is deleted" "1" "$(deletes)"
expect_eq "an unlisted stray stays" "yes" "$(grep -qx stray-one "$base/live" && echo yes || echo no)"

# 4. Refuses a listed name that still has a directory.
mkdir -p "$base/functions/old-one"
reset coach-chat old-one
if run >/dev/null 2>&1; then fail "a retired name with a directory is refused"; else pass "a retired name with a directory is refused"; fi
expect_eq "nothing deleted when refused" "0" "$(deletes)"
rmdir "$base/functions/old-one"

# 5. A failed listing fails the run without deleting.
reset coach-chat old-one
touch "$base/list-fails"
if run >/dev/null 2>&1; then fail "a failed listing fails"; else pass "a failed listing fails"; fi
expect_eq "nothing deleted when the listing fails" "0" "$(deletes)"

# 6. --check: clean production passes, a leftover fails, a retired one is allowed.
reset coach-chat health-check old-one
if run --check >/dev/null 2>&1; then pass "check allows directories and retired names"; else fail "check allows directories and retired names"; fi
reset coach-chat health-check surprise
if run --check >/dev/null 2>&1; then fail "check fails on an unknown deployed function"; else pass "check fails on an unknown deployed function"; fi
expect_eq "check never deletes" "0" "$(deletes)"

# 7. A malformed name in the list is rejected.
printf 'old-one\n../coach-chat\n' >"$base/retired.txt"
reset coach-chat old-one
if run >/dev/null 2>&1; then fail "a malformed list entry is rejected"; else pass "a malformed list entry is rejected"; fi
expect_eq "nothing deleted for a malformed list" "0" "$(deletes)"

if ((failures > 0)); then
  echo "$failures failure(s)"
  exit 1
fi
echo "All retire-functions tests passed."
