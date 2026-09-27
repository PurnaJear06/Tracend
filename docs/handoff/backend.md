# Backend Handoff — FLUTTER-8 Coach Reliability

**Status:** implementation and verification complete; PR review/owner merge pending
**Branch:** `codex/coach-chat-validation-reliability`
**Scope:** Edge Functions, additive SQL, and the Flutter tooling wrapper only; no app code change and
no device reinstall expected

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
- Classifier patterns use word boundaries and include HRV, heart rate, readiness, tired, exhausted,
  slept, and sleepless without false matches such as `will`, `interest`, or `great`.

Review follow-ups on the same branch:

- The live DeepSeek prompt had been reduced to a four-line persona. All providers now share one
  `coachChatPersona` constant (coaching approach, communication style, hard boundaries) placed
  before the null and output contracts. Its "celebrate wins" example now cites only numbers the
  context shows, consistent with the no-new-statistics rule.
- `prepare_coach_chat_v7` guards the score computation and evidence derivation like
  `get_my_daily_brief`: a scoring failure yields `computed_metrics.unavailable` and only non-score
  evidence codes instead of failing the whole chat. The migration was unapplied, so it was amended
  in place.
- `scripts/flutter.sh` clears git's hook variables (`GIT_DIR` and related). Inside the pre-push hook
  Flutter had read the Tracend repository as its own SDK checkout, reported an unknown version, and
  failed dependency resolution.

## Verification

- Deno format/lint: clean; Deno tests: 124 passed and 7 database-dependent tests ignored without a
  local database (131 with the database contract environment).
- Fresh local database reset: all migrations applied, including
  `20260927120000_coach_chat_reliability_v7.sql`.
- pgTAP: 34 files, 951 assertions; `coach_chat_v7_test.sql` has 23, including the simulated
  scoring failure.
- Flutter: 422 tests passed; analysis clean; unsigned iOS release build passed.
- Linked production migration dry-run passed and lists only the new v7 migration.
- PR CI: the seven required checks gate every push to this branch; the PR shows the latest run.

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
