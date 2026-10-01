# Onboarding Handoff — new-user plan

**Status:** PR 1 (owner-facing fixes) is in review. PR 2 (server) and PR 3 (app) follow.

Plan (owner-approved 2026-10-01, revised after a GPT review):
`/Users/purnajear/.claude/plans/smooth-munching-castle.md`.

## Why

A 2026-10-01 audit of sign-up → onboarding → plan for a new user found:

- **The plan is not AI and ignores most answers.** `onboarding-propose-plan` is the Phase-2 mock.
  It uses only path, day count and weight (kcal = kg × 30, protein 2 g/kg, fat 70 g). Fat loss and
  muscle gain produce identical targets. Equipment, session length, limits and the current plan
  are ignored.
- **The approved plan is not delivered.** Approval seeds a generic Push/Pull/Leg gym set instead
  of the approved structure.
- **Reopening on the proposal step spins forever.**
- **Answers end up in the wrong place:**
  - the profile keeps step-0 defaults;
  - the goal stays `draft`, so every reader (which wants `active`) misses it;
  - the onboarding weight is never stored.
  The Coach therefore sees no goal, equipment or limits.

The owner chose an AI-proposed plan:

- Deterministic code calculates the safe ranges, validates the model's plan and builds the workouts.
- The user approves before anything activates.
- The provider and model are server settings, and the owner can rewrite the AI notice whenever the
  provider changes.

## PR 1 — fixes that affect the owner today

Branch `claude/today-workout-fixes`, migration
`20261001100000_today_workout_for_target_date.sql`.

- **Today's workout follows the requested date.** `get_my_daily_brief(target_date)` took
  `today_workout` from `get_my_training_hub`, which uses the database's UTC `current_date`. From
  00:00 to 05:30 IST, Today showed the previous weekday's workout, or none, which disabled Start
  session.
  - Both now use `private.planned_workout_for_date(user, date)`, ordered by `workout_order`.
  - The hub still uses the server date for its own field; Train uses the phone's weekday.
- **Start session opens that workout.** Today pushed `WorkoutDetailScreen` with no workout, so it
  fell back to `PlannedWorkout.fixture` (id `fixture-push`), and starting it failed.
  - `_openWorkout` now parses the brief's workout with `PlannedWorkout.fromHubJson`, the hub
    parser made public.
  - It passes the brief's date and reloads the brief after completion.
- **Coach "[object Object]".** Plan proposals reached the model as `String(object)`.
  `formatPlanProposal` prints a one-line summary for text and structured proposals.
- **Seeded workouts.**
  - Sessions spread across the week (5 → Mon/Tue/Wed/Fri/Sat; 6 → Mon–Sat) instead of stacking
    workouts 4–7 on Sunday.
  - Each name matches its exercises.
  - The owner's plan is `imported`, so this doesn't change it.

Tests: `today_workout_target_date_test.sql` (9 pgTAP checks, including `target_date` ≠ server
date), the Today Start-session widget test, and the Coach proposal-line Deno test.

After merge: deploy is automatic. Install the app from merged `main` for Start session. Then, on the
phone, open Today after midnight IST and tap Start session; it should open today's real workout.

## PR 2 — server (next)

- Per-purpose AI notice that the owner can rewrite.
- Exercise catalog.
- `onboarding-policy-v1`.
- Durable generation jobs.
- Provider-agnostic `onboarding-plan` function with validation, repair and rules fallback.
- Approval that builds the proposed workouts and activates goal, profile and weight.
- Onboarding eval.

Old app builds keep using `onboarding-propose-plan` and the v1 approval, unchanged.

## PR 3 — app (after PR 2)

- New onboarding steps: about you, schedule, equipment.
- Resumable generation.
- Revision note.
- A proposal screen that shows every workout and how the targets were calculated.
- Server-rendered AI notice.
