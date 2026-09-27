# Backend Handoff — FLUTTER-8 Coach Reliability

**Status:** implementation and verification complete; PR review/owner merge pending
**Branch:** `codex/coach-chat-validation-reliability`
**Scope:** Edge Functions and additive SQL only; no Flutter change and no device reinstall expected

## Current change

- Coach answer validation exposes finite internal rules and JSON paths while public failures retain
  the stable sanitized error code.
- The model-facing schema and validator share one set of limits and the request's exact evidence
  whitelist. One targeted non-thinking repair remains fail-closed.
- `prepare_coach_chat_v7` computes the coaching date fresh, renders those same scores, and derives
  chat evidence through the same helper as `prepare_daily_coaching`.
- NULL recovery emits no recovery code. Daily and chat health availability both mean a HealthKit row
  on the coaching date; stale two-day health no longer becomes current evidence.
- Required truth sections render before history and are never cut. The question is sent once.
- Classifier patterns use word boundaries and include HRV, heart rate, readiness, tired, and
  exhausted without false matches such as `will`, `interest`, or `great`.

## Verification

- Deno format/lint: clean; Deno tests: 130 passed with the local database contract environment.
- Fresh local database reset: all migrations applied, including
  `20260927120000_coach_chat_reliability_v7.sql`.
- pgTAP: 34 files, 948 assertions, all passed.
- Flutter: 422 tests passed; analysis clean; unsigned iOS release build passed.
- Linked production migration dry-run passed and lists only the new v7 migration.
- PR CI: all seven required checks passed, including fresh-database pgTAP and the macOS iOS build.

## Post-deploy acceptance

Keep FLUTTER-8 open until the nine prompts in the PR checklist pass on the owner's iPhone, quoted
numbers match Today exactly, missing metrics are called not measured, no plan activates without
approval, and any terminal failure shows finite rule names in Edge Sentry.

## Recorded follow-ups — out of scope

- Add short per-request row evidence aliases (`E1…En`) mapped server-side; never expose UUIDs to the
  model.
- Replace the legacy `CHECK_IN_RECOVERY_MIXED` name for the 40–49 recovery band only through a
  coordinated whitelist/prompt migration.
- Add log-only numeric-grounding telemetry that counts answer numbers absent from context without
  logging content.
- Add an on-demand live evaluation for first-pass validity, route accuracy, and the device
  acceptance prompts.
