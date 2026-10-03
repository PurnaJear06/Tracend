# Redesign Handoff: Graphite + Lime, App-Wide

**Status:** Phase 0 prototype round 3 is with the owner for signature picks. PR 1 (backend data)
is in review.

**Plan:** `/Users/purnajear/.claude/plans/hey-uh-in-my-tender-allen.md` (owner-approved
2026-10-03). Owner-chosen direction: palette A, graphite + lime, from the prototype at
https://claude.ai/artifact/CQuLCcrwPUH6bwHfd8rSMh (round 3 adds the signature switches).

**Worktree:** `/Volumes/Crucial X9/dev/.tracend-worktrees/redesign` (remove after the last merge).

## Status by PR

| PR | Scope | Branch | State |
| -- | ----- | ------ | ----- |
| Phase 0 | Prototype round 3: signature options, rebuilt load sheet, launch motion, icon | (artifact) | Waiting for the owner's picks |
| 1 | Backend data: exercise history, effort and completion provenance, hub 1.6, discard | `claude/redesign-backend` | In review |
| 2a | Tokens, typography, theme | | Not started. 🔒 device checkpoint after |
| 2b | Shared widgets: sheets, toasts, confirmations, haptics, skeleton, loader | | Not started |
| 2c | App icon, launch screen, intro, brand loader | | Not started. 🔒 device checkpoint after |
| 3 | Workout logging and the rest alert | | Not started. Install only after PR 1 is live. 🔒 device checkpoint after |
| 4 | Train screen and load sheet | | Not started |
| 5 | Today | | Not started |
| 6 | Coach | | Not started |
| 7 | Nutrition and Progress alignment | | Not started |
| 8 | Account, onboarding, auth | | Not started |

## Phase 0 picks

Waiting for the owner. Options in round 3:

1. Logging style: focus mode (one exercise per screen) or the table.
2. Muscle map: on or off. It turns in 3D (Front and Back control, tap to turn, no phone tilt) with
   the muscle chips as its text equivalent; worked muscles use lime plus a hatch pattern.
3. New best: big moment (burst, stamp, screenshot-worthy finish card) or quiet.
4. Week: the week line or the day boxes.
5. Rebuilt Training load sheet, launch motion, and icon (Lime, or White and lime).

The muscle map needs planned exercises linked to the catalog. Older plans have no slug, so the
owner runs a read-only count (dashboard SQL editor) before it is built. Unlinked exercises show no
muscles; nothing is guessed.

## PR 1: backend data

Migration `20261003100000_train_redesign_data.sql` (additive):

- `workout_sessions.completion_source` (`manual`, `healthkit`) and `session_effort_source`
  (`athlete`, `legacy_default`, `healthkit_default`), backfilled from the `workout.completed` and
  `workout.auto_completed` audit codes. Never inferred from notes.
- `complete_workout_v2(session_id, client_revision, duration_seconds, session_effort, notes,
  session_energy default null)`: the athlete's whole-number 1–10 rating, energy optional. The old
  `complete_workout` keeps working for installed builds and records its fixed 8 as
  `legacy_default`. Both share `private.complete_workout_session`; a discarded session cannot be
  finished (55000).
- `abandon_workout(p_session_id)`: open → `abandoned` with a `workout.abandoned` audit event; a
  repeat returns `replayed: true`; a completed session is refused (22023); another athlete's is
  not found (P0002). Rows stay; every read counts completed sessions only, and
  `get_my_workout_session` no longer returns a discarded session.
- `exercise_performances.exercise_slug`, kept by a trigger: the planned exercise's slug for a
  prescribed performance, none for substitutions and extras.
- `get_my_exercise_history(p_keys, p_sessions default 8)` 1.0: 1–20 keys of 1–120 characters
  (repeats answered once), sessions clamped to 1–12, violations 22023. Per key: `kind` (`load` or
  `reps`), `last_session`, `best_set` (heaviest, then most reps, then earliest; most reps for
  bodyweight) and `top_sets` (heaviest set per completed session, newest first).
- `get_my_training_hub` 1.6 adds `local_today`; `active_plan.effective_date` (falls back to the
  local approval day), `approved_on` and `progression_rule`; each exercise's `exercise_slug` and
  `primary_muscles`; `completion_source` and `effort_source` on recent sessions; and `daily_load`
  (28 local days, ALGORITHMS §4 "Day Level").

Deviation from the plan, on purpose: the day-level reference set uses only days whose effort the
athlete reported, so the default efforts of the first 28 days never shape the personal
percentiles. The plan's "28 days before, zero days excluded" rule is otherwise as written.

Not in PR 1: the name → slug backfill for older planned exercises. It changes approved plan rows,
so it waits for the owner's count and decision.

Verification: pgTAP `train_redesign_data_test.sql` (63 checks) through CI, because the local
Colima VM hung on start again; Dart contract fixtures `training_hub_v1_6.json` and
`exercise_history_v1_0.json`; `db_contract_test.ts` updated for 1.6 and the history RPC. No app
change, so no reinstall. After the deploy, confirm the live hub reports `schema_version` 1.6 with a
read-only dashboard query.

## Deferred

- Move a workout to another day (schedule-override table, RPC, audit).
- Live Activity lock-screen timer (widget extension and signing).
- Add or remove a set mid-workout (sync RPC change).
- A true 3D body model (licensed asset and renderer), only if the 2.5D map is loved.

## Public-release blocker

Terms and Privacy checkboxes in onboarding are not linked to hosted notices
(SECURITY_PRIVACY.md open release item). Acceptable for the owner-only beta; must be resolved
before any public release. PR 8 records it in the SECURITY_PRIVACY release checklist.
