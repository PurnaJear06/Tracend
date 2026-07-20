#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COLIMA=true
RESET=true
CLEANUP=true
STEPS="pg,tap,deno,flutter,analyze,build,dryrun"
COLOUR_CLEAN="${COLOUR_CLEAN:-}"

BOLD=""; GREEN=""; RED=""; YELLOW=""; CYAN=""; RESET=""
if [[ -t 2 ]] || [[ "${COLOUR_CLEAN:-false}" == "false" ]]; then
  BOLD="\033[1m"; GREEN="\033[32m"; RED="\033[31m"
  YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"
fi

usage() {
  cat <<EOF
Usage: pre-deploy.sh [OPTIONS]

Run the full pre-deploy verification sequence before pushing to production.
Exits non-zero on the first failure. Pass --help for options.

Options:
  --skip-colima         Skip Colima start/stop (use if already running)
  --skip-reset          Skip 'supabase db reset' (use if DB is already current)
  --no-cleanup          Keep Colima + Supabase running after the gate
  --deno-only           Run only Deno (fmt + lint + test)
  --flutter-only        Run only Flutter (analyze + test + build)
  --db-only             Run only pgTAP (requires running Colima + Supabase)
  --list                Print the step list without running anything
  -h, --help            Show this help

Environment:
  COLOUR_CLEAN=true     Emit plain text (no ANSI sequences)
  CONTRACT_URL          Supabase URL for contract tests (default: local)
  CONTRACT_ANON_KEY     Supabase anon key for contract tests (default: local)
EOF
  exit 0
}

# ── parse flags ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-colima) COLIMA=false ;;
    --skip-reset)  RESET=false ;;
    --no-cleanup)  CLEANUP=false ;;
    --deno-only)   STEPS="deno" ;;
    --flutter-only) STEPS="analyze,flutter,build" ;;
    --db-only)     STEPS="pg,tap" ;;
    --list)        STEPS="list" ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
  shift
done

if [[ "$STEPS" == "list" ]]; then
  echo "Available step groups: pg (Colima+Supabase start), tap (pgTAP), deno (fmt+lint+test), analyze, flutter (test), build, dryrun"
  exit 0
fi

# ── helpers ───────────────────────────────────────────────────────────────
now() { date '+%H:%M:%S'; }
pass()  { echo -e "  ${GREEN}✓${RESET} $* ($(now))"; }
fail()  { echo -e "  ${RED}✗${RESET} $* ($(now))" >&2; }
warn()  { echo -e "  ${YELLOW}!${RESET} $* ($(now))"; }
info()  { echo -e "  ${CYAN}→${RESET} $*"; }
step()  { echo -e "${BOLD}═══ $* ═══${RESET}"; }

FAILURES=0

die() {
  fail "$*"
  FAILURES=$((FAILURES + 1))
}

cleanup() {
  if [[ "$CLEANUP" == "true" ]]; then
    echo ""
    step "CLEANUP"
    info "Stopping local Supabase ..."
    "$repo_root/scripts/supabase.sh" stop >/dev/null 2>&1 || true
    info "Stopping Colima ..."
    "$repo_root/scripts/container.sh" stop >/dev/null 2>&1 || true
    pass "Colima + Supabase stopped"
  fi
}

# ── step 1: Colima + Supabase start (when needed) ─────────────────────────
if echo "$STEPS" | grep -q "pg"; then
  step "1 — LOCAL SUPABASE"

  if [[ "$COLIMA" == "true" ]]; then
    info "Starting Colima ..."
    "$repo_root/scripts/container.sh" start 2>&1 | while IFS= read -r line; do
      echo "    $line"
    done
    pass "Colima running"
  fi

  info "Starting Supabase ..."
  "$repo_root/scripts/supabase.sh" start 2>&1 | while IFS= read -r line; do
    echo "    $line"
  done
  pass "Supabase running"

  # Derive local Supabase URL + anon key for contract tests
  CONTRACT_URL="${CONTRACT_URL:-http://127.0.0.1:54321}"
  export CONTRACT_URL

  if [[ -z "${CONTRACT_ANON_KEY:-}" ]]; then
    CONTRACT_ANON_KEY="$("$repo_root/scripts/supabase.sh" status --output json 2>/dev/null | \
      "$repo_root/scripts/deno.sh" eval "const d=JSON.parse(await Deno.readAll(Deno.stdin)); console.log(d.anon_key||'')" 2>/dev/null || true)"
    CONTRACT_ANON_KEY="${CONTRACT_ANON_KEY:-}"
  fi
  export CONTRACT_ANON_KEY

  if [[ "$RESET" == "true" ]]; then
    info "Applying all migrations (db reset) ..."
    if "$repo_root/scripts/supabase.sh" db reset 2>&1 | while IFS= read -r line; do
      echo "    $line"
    done; then
      pass "db reset succeeded"
    else
      fail "db reset failed — migrations do not apply cleanly"
      cleanup
      exit 1
    fi
  else
    info "Skipped db reset (--skip-reset)"
  fi
fi

# ── step 2: pgTAP ─────────────────────────────────────────────────────────
if echo "$STEPS" | grep -q "tap"; then
  step "2 — pgTAP TESTS"
  if "$repo_root/scripts/test-db.sh" 2>&1 | while IFS= read -r line; do
    echo "    $line"
  done; then
    pass "pgTAP passed"
  else
    fail "pgTAP failed"
    cleanup
    exit 1
  fi
fi

# ── step 3: Deno (fmt + lint + test) ──────────────────────────────────────
if echo "$STEPS" | grep -q "deno"; then
  step "3 — DENO (Edge Functions)"

  info "deno fmt --check ..."
  if "$repo_root/scripts/deno.sh" fmt --check supabase/functions 2>&1; then
    pass "fmt clean"
  else
    die "fmt issues — run: ./scripts/deno.sh fmt supabase/functions"
  fi

  info "deno lint ..."
  if "$repo_root/scripts/deno.sh" lint supabase/functions 2>&1; then
    pass "lint clean"
  else
    die "lint issues"
  fi

  info "deno test --allow-env --allow-net ..."
  if "$repo_root/scripts/deno.sh" test --allow-env --allow-net supabase/functions 2>&1 | while IFS= read -r line; do
    echo "    $line"
  done; then
    pass "Deno tests passed"
  else
    die "Deno tests failed"
  fi

  if [[ "$FAILURES" -gt 0 ]]; then
    echo ""
    fail "$FAILURES Deno step(s) failed"
    cleanup
    exit 1
  fi
fi

# ── step 4: Flutter static analysis ───────────────────────────────────────
if echo "$STEPS" | grep -q "analyze"; then
  step "4 — FLUTTER STATIC ANALYSIS"

  "$repo_root/scripts/flutter.sh" pub get 2>&1 | while IFS= read -r line; do
    echo "    $line"
  done

  info "flutter analyze ..."
  if "$repo_root/scripts/flutter.sh" analyze 2>&1; then
    pass "analyze clean"
  else
    die "analyze failed"
    cleanup
    exit 1
  fi
fi

# ── step 5: Flutter tests ─────────────────────────────────────────────────
if echo "$STEPS" | grep -q "flutter"; then
  step "5 — FLUTTER TESTS"

  info "flutter test ..."
  if "$repo_root/scripts/flutter.sh" test 2>&1 | while IFS= read -r line; do
    echo "    $line"
  done; then
    pass "Flutter tests passed"
  else
    die "Flutter tests failed"
    cleanup
    exit 1
  fi
fi

# ── step 6: Flutter iOS release build ─────────────────────────────────────
if echo "$STEPS" | grep -q "build"; then
  step "6 — FLUTTER iOS BUILD"

  info "flutter build ios --release --no-codesign ..."
  if "$repo_root/scripts/flutter.sh" build ios --release --no-codesign 2>&1 | while IFS= read -r line; do
    echo "    $line"
  done; then
    pass "iOS release build succeeded"
  else
    die "iOS release build failed"
    cleanup
    exit 1
  fi
fi

# ── step 7: dry-run against production ────────────────────────────────────
if echo "$STEPS" | grep -q "dryrun"; then
  step "7 — PRODUCTION DRY-RUN"

  info "supabase db push --linked --dry-run ..."
  if "$repo_root/scripts/supabase.sh" db push --linked --dry-run 2>&1 | while IFS= read -r line; do
    echo "    $line"
  done; then
    pass "Dry-run matches — safe to deploy"
  else
    die "Dry-run failed — review before deploying"
    cleanup
    exit 1
  fi
fi

# ── final report ──────────────────────────────────────────────────────────
echo ""
step "GATE RESULT"
echo -e "  ${GREEN}All checks passed${RESET} — ${BOLD}safe to deploy to production${RESET}  ($(date))"
cleanup
exit 0
