# Onboarding Handoff — new-user plan

**Status:** PR 1 (owner-facing fixes, [#60](https://github.com/PurnaJear06/Tracend/pull/60)) and
PR 2 (server) are in review. PR 3 (app) follows PR 2.

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

## PR 2 — server

Branch `claude/onboarding-ai-server`, stacked on PR 1. It deploys safely before the app: nothing
calls `onboarding-plan` until PR 3, and older builds keep `onboarding-propose-plan` with v1 approval.
v1 approval now refuses 2.0 proposals.

**Migrations**

- `20261002090000_ai_consent_notices.sql`:
  - Notices are server data, current per purpose.
  - `ai-coaching-v1` (today's text) stays current for the Coach chat and the daily decision.
  - `ai-coaching-v2` adds the starting plan and is current only for `onboarding_plan`.
  - `has_ai_coaching_consent(uuid, purpose)` counts a grant only for the current notice; the
    one-argument form means the Coach chat.
- `20261002091000_exercise_catalog.sql`:
  - 72 exercises, `catalog-v1`, mirrored from `_shared/onboarding/catalog.ts`.
  - `planned_exercises.exercise_slug`.
- `20261002092000_onboarding_plan_v2.sql`:
  - Profile columns that only approval writes, with column grants for the step-0 fields.
  - 2.0 proposals.
  - `onboarding_generations` with claim, fail and status functions.
  - `persist_onboarding_proposal_v2` and `respond_to_onboarding_proposal_v2`.
  - The seed skips `ai`/`rules` plans.
  - Onboarding usage counts toward the AI budget.
  - v1 guards.
- `20261002093000_coach_profile_context.sql`: the Coach sees sex, age, activity, equipment and the
  athlete's notes.

**Edge**

- `onboarding-plan` (`handler.ts` plus `index.ts`) answers 202 and generates in
  `EdgeRuntime.waitUntil`.
- `_shared/onboarding/`: answers, catalog, policy, contract (28 rules), rules plan, generator.
- `_shared/providers/onboarding_plan_provider.ts`: any OpenAI-compatible provider by settings.

**Tests**

- 226 Deno tests. The rules plan is valid in all 3,600 combinations tested.
- `onboarding_plan_v2_test.sql`: 44 pgTAP checks, including consent per purpose, stale workers,
  catalog refusal, exact workouts on approval, column grants and cross-user access.

**Rollout after merge** (deploy is automatic; nothing is visible until PR 3):

1. Run the Onboarding Eval workflow (Actions → Onboarding Eval → Run workflow; provider
   `deepseek`, model `deepseek-flash`). It needs the `DEEPSEEK_API_KEY` repository secret. The gate
   is at least 90% valid model plans and p95 under 60 s.
2. If it passes, set the secrets `ONBOARDING_PLAN_PROVIDER=deepseek`,
   `ONBOARDING_PLAN_MODEL=deepseek-flash` and `ONBOARDING_PLAN_MODEL_EVALUATED=true`. The
   DeepSeek key is already set for the Coach.
3. Then run `./scripts/verify-live-function.sh --all` from the deployed commit.
4. Until then every new athlete gets the rules plan, which is still built from their answers.

**Switching provider or model later** (AI_SAFETY_SPEC §10):

1. Run the eval for the candidate.
2. Set its key and the `ONBOARDING_PLAN_*` secrets, including prices for Groq or Gemini.
3. Publish a new notice naming the provider:

   ```sql
   select private.publish_ai_notice('ai-coaching-v3', 'Provider', array['coach_chat','daily_coaching','onboarding_plan'], 'Notice text');
   ```

**Owner queries** (SQL editor):

- `select metadata from audit_events where action_code = 'onboarding.plan.generated' order by created_at desc limit 20;`
  shows origin, model and fallback reason.
- `select status, error_code, created_at from onboarding_generations order by created_at desc limit 20;`

## PR 3 — app (after PR 2)

- New onboarding steps: about you, schedule, equipment.
- Resumable generation.
- Revision note.
- A proposal screen that shows every workout and how the targets were calculated.
- Server-rendered AI notice.
