# Onboarding Handoff — new-user plan

**Status:** the final onboarding batch (#65 thinking, #69 Apple Health summary, #67 Apple Health
step, #68 recovery and UI) is merged and deployed (c35946c, 2026-10-02) and installed. The owner's
fresh-account test worked (AI plan, thinking, 38 s) but the plan felt generic. The **coach-quality
batch** follows in three PRs (plan: `/Users/purnajear/.claude/plans/sprightly-splashing-dolphin.md`,
revised after an external review):

1. **Coach intake** (this branch, `claude/coach-intake`): training years, barbell top sets →
   starting loads, focus muscles with weekly set minimums, the coach's follow-up questions, and
   Apple Health usual months vs the last 28 days. See "Coach intake" below.
2. **Physique check**: Groq vision on the athlete's own progress photos, its own consent notice,
   owner-only until a broader evaluation; confirmed focus muscles only.
3. **Calibration and re-plan**: after two weeks of logged sets, a stale-safe plan version N+1.

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
- `_shared/onboarding/`: answers, catalog, policy, contract (29 rules), rules plan, generator.
- `_shared/providers/onboarding_plan_provider.ts`: any OpenAI-compatible provider by settings.

**Tests**

- 242 Deno tests. The rules plan is valid in all 3,600 schedule combinations, its nutrition in
  14,400 body-size combinations, and with any one movement avoided.
- `onboarding_plan_v2_test.sql`: 44 pgTAP checks, including consent per purpose, stale workers,
  catalog refusal, exact workouts on approval, column grants and cross-user access.
- `onboarding_review_fixes_test.sql`: 15 pgTAP checks for the review fixes below.

**Review fixes** (2026-10-02, `20261002094000_onboarding_review_fixes.sql` and the Edge code):

1. **Movements to avoid** are a structured answer (`avoid_patterns`), required when the athlete
   writes a limitation. The prompt, the catalog sent, the validator (`exercise_avoided`), the rules
   plan and `persist_onboarding_proposal_v2` all enforce them.
2. **Daily coaching** checks its own notice: coach-decide passes `daily_coaching`, coach-chat
   passes `coach_chat`, and the purpose is now required in `aiCoachingConsent`.
3. **Nutrition bounds** equal the database check; calories are capped at 6,000 kcal and the fat
   minimum uses the BMI-25 weight from BMI 30. The rules plan is validated before any model call;
   infeasible answers get 422 `onboarding_plan_infeasible` with the answers to change, and no
   generation starts.
4. **Usage:** empty and cut-off answers carry the provider's token counts, so every billed attempt,
   including the repair, counts toward the budget.
5. **Expiry:** `get_my_onboarding_generation` reports a pending proposal past its expiry as
   `expired` (with `proposal_expires_at`), and `respond_to_onboarding_proposal_v2` stores the
   expiry and returns status `expired` instead of raising. The same answers then start a fresh
   generation.

**Rollout after merge** (deploy is automatic; nothing is visible until PR 3):

1. Run the Onboarding Eval workflow (Actions → Onboarding Eval → Run workflow; provider
   `deepseek`, model `deepseek-flash`, route `direct`). It needs the `DEEPSEEK_API_KEY` repository
   secret (GitHub → Settings → Secrets and variables → Actions); the Supabase Edge secret of the
   same name is separate. The gate is at least 90% valid model plans and p95 under 60 s. Route
   `router` only smoke-tests through `EVAL_BASE_URL` and never counts as an evaluation.
   - **Eval runs on 2026-10-02.** The report now records every provider response: status,
     finish reason, token counts and the answer's length.
     - Run 1: the `EVAL_BASE_URL` variable sent all 12 calls to the router, which returned
       HTTP 404 for the model id `deepseek-flash`; the router calls it `deepseek-v4-flash`.
     - Run 2 (direct): stopped at once because the repository has no `DEEPSEEK_API_KEY` secret.
     - Router runs with `deepseek-v4-flash`: every answer was cut off at 6,000 tokens. The router
       ignores both `thinking: disabled` and `reasoning_effort: none`, and DeepSeek V4 wrote
       9,000–21,000 characters of reasoning per answer. Even the one answer that finished was a
       9,500-character 2-day plan, too long for a 6-day plan to fit.
     - Fix: tighter text limits (exercise notes 80 characters and usually empty, workout texts
       140, shorter assessment and lists) and compact JSON. Router runs get 24,000 output tokens
       for the reasoning they cannot turn off; production keeps 6,000 with thinking off.
     - Router result after the fix: 12/12 valid (one repaired), p95 49 s, $0.11 a run. Plans are
       3,900–8,200 characters, about 2,400 tokens for the largest.
     - Still needed: a direct run, which evaluates the production request (thinking off). The
       router run only shows that the prompt and limits produce valid plans.
2. If it passes, set the secrets `ONBOARDING_PLAN_PROVIDER=deepseek`,
   `ONBOARDING_PLAN_MODEL=deepseek-flash` and `ONBOARDING_PLAN_MODEL_EVALUATED=true`. The
   DeepSeek key is already set for the Coach.
3. Then run `./scripts/verify-live-function.sh --all` from the deployed commit.
4. Until then every new athlete gets the rules plan, which is still built from their answers.

**Thinking** (PR A, AI_SAFETY_SPEC §10):

- `ONBOARDING_PLAN_THINKING` is `on` when unset: the first attempt reasons (DeepSeek `thinking`
  enabled, `reasoning_effort: high`, no temperature, 24,000 output tokens) within 105 s of a 125 s
  deadline. The repair never thinks. The 140 s lease and the 150 s Edge background limit still
  cover the deadline plus storing.
- Why: the starting plan is the biggest decision in the app, it builds in the background, and the
  owner's router evals (which always think) are what passed. Coach chat already sends the same
  thinking request directly to DeepSeek for plan changes.
- Evals run through NaraRouter only (owner's decision, 2026-10-02: keep DeepSeek credits for
  production), so the first direct thinking plan is the owner's fresh-account test. Check it with
  the audit query below: `thinking`, `latency_ms`, `reasoning_units` and `finish_reason` are stored
  with every model plan.
- **Rollback:** `./scripts/supabase.sh secrets set ONBOARDING_PLAN_THINKING=off --project-ref
  qsfzzsjenopqqqhvpyaw`. A secret change creates a new version of every function: wait for it,
  then run `./scripts/verify-live-function.sh --all` from the deployed commit.

**Server: notice v4, time zone, Apple Health summary, profile** (PR B):

- **Notice `ai-coaching-v4`** is published by migration for all three purposes, with the
  Apple Health summary and movements to avoid in its text. It replaces the owner's v3 SQL step
  (do not run it). Before v4, the app showed v1 (current for the most purposes) while the plan
  checked v2, so a new athlete's grant never counted for the plan.
- **`set_my_timezone`** stores the device's zone (the app calls it from PR C); approval dates
  the plan, targets and onboarding weight with the athlete's local date.
- **Apple Health summary:** `onboarding-plan` reads the 28 days before the athlete's local today
  from `daily_health_summaries` and `health_workout_references`, summarises them
  (`_shared/onboarding/health_summary.ts`, ALGORITHMS §9), puts the summary in the snapshot (so in
  the hash), the prompt (`<health_summary>`), the proposal's `calculation.health` and evidence.
  Only short sleep changes a limit (RPE ceiling −0.5). No workouts found is missing information.
- **Profile:** approval keeps `avoid_patterns` and `equipment_note`; the Coach's profile shows
  them and is told never to suggest an avoided movement. `current_plan` is deliberately not kept.
- **No deload promise:** the app repeats one weekly template, so the prompt forbids it and
  `deload_week` is no longer stored.

**App: Apple Health step, per-athlete state, time zone** (PR C, needs an install):

- **Step 5 of 11, Apple Health** (optional), between Goal and About you. Connect runs
  `connectAndSync`; the draft records `health_import` (`connected`, `skipped` or `empty`), which
  the server never requires. About you prefills the weight from Apple Health (newest within 14
  days, never over an answered weight) and tags the daily-activity answer average steps point to
  (`lib/features/onboarding/health_activity.dart`, the same bands as the server).
- **First sync reads 31 dates** (`healthSyncStart`, today−30): the server's 28-day summary and
  the baselines have four weeks. A sync carries at most the newest 100 workouts.
- **Per-athlete health state** (`HealthPreferences`): keys include the user id. The older shared
  state is adopted only when its last sync is within 5 minutes of the account's newest server
  sync, then deleted either way, so another account never inherits "connected". The owner's
  phone keeps its connection; the next sync after the update reads the full 31 dates once.
- **Time zone:** a `com.tracend.app/time_zone` channel returns the device's IANA zone;
  `Phase2Gate` stores it with `set_my_timezone` when it differs.
- One `SupabaseHealthRepository` is shared by onboarding and the app.

**Onboarding recovery and UI** (PR D, needs an install):

- **Recovery:** a failed draft load shows **Try again** and saves nothing (it used to let
  Continue overwrite the draft with defaults); the load times out after 15 s; Sign out is
  available while loading. Eligibility writes only the eligibility answer (no more default
  training days) and adds terms and privacy records only when that version is not already
  granted. 422 `onboarding_draft_incomplete` opens Path; 503 says the builder is unavailable.
  Missing `mounted` checks added; Approve, Reject, Request changes, Build and Sign out ignore a
  second tap.
- **UI:** no preselected goal, goal descriptions; −/+ steppers with spoken values; birth-year
  keyboard closes; choice cards show selection; Review lists every answer with **Edit** (returns
  to Review), stacked at large text; **Step N of 11**; waiting copy says up to two minutes;
  Reject asks first; Request changes needs a note; RPE explained in reps left; **You're set.**
  after approval; Account › Profile and goals shows the onboarding answers and no longer tells
  athletes to ask the Coach for a proposal (no Coach plan-change path exists yet).
- **Not changed** (owner's choice or out of scope): lb/ft units, translations, links to the
  terms text, raw error text in beta.

**Switching provider or model later** (AI_SAFETY_SPEC §10):

1. Run the eval for the candidate.
2. Set its key and the `ONBOARDING_PLAN_*` secrets, including prices for Groq or Gemini.
3. Publish a new notice naming the provider:

   ```sql
   select private.publish_ai_notice('ai-coaching-v3', 'Provider', array['coach_chat','daily_coaching','onboarding_plan'], 'Notice text');
   ```

**Owner queries** (SQL editor):

- `select metadata from audit_events where action_code = 'onboarding.plan.generated' order by created_at desc limit 20;`
  shows origin, model and fallback reason, and for a model plan whether it thought, its latency,
  attempts, tokens (reasoning separately) and finish reason.
- `select status, error_code, created_at from onboarding_generations order by created_at desc limit 20;`

## PR 3 — app

Branch `claude/onboarding-ai-app`, stacked on PR 2. It needs PR 2 deployed first, because it calls
`onboarding-plan`, `get_my_onboarding_generation`, `respond_to_onboarding_proposal_v2` and
`get_current_ai_notice`.

**Onboarding** (`lib/features/onboarding/onboarding_flow.dart`)

- **The steps:** Eligibility → AI → Path → Goal → About you → Schedule → Equipment →
  Food & limits → Review → Plan.
- **The draft payload:**
  - New keys: `sex`, `birth_year`, `height_cm`, `weight_kg`, `target_weight_kg`,
    `daily_activity`, `training_weekdays`, `equipment_items`, `avoid_patterns` and
    `revision_note`.
  - `avoid_patterns` is written only once the athlete has passed Food & limits, so an older
    draft is never read as "nothing to avoid".
  - The old keys keep their types (`training_days` int, `equipment` string).
- **Older drafts:**
  - `context` maps to About you.
  - A draft without `sex` resumes at About you.
  - An old day count becomes an even spread of weekdays.
- **The Plan step** polls the server generation:
  - Running keeps waiting, and a finished proposal opens.
  - Failed shows **Try again**.
  - An answered or superseded generation returns to Review.
  - An expired proposal, at reopen or when answering it (`OnboardingProposalStale`), shows
    **Build a new plan** and **Back to review**; the same answers start a fresh generation.
  - `onboarding_plan_infeasible` opens the step to change with a message
    (`OnboardingPlanInfeasible`).
  - There is no state without a way out, and **Sign out** is in the app bar on every step.
- **The proposal screen** (`onboarding_proposal_view.dart`) shows provenance, confidence, the
  assessment, every day with its exercises, the nutrition targets with how they were calculated,
  kept/changed, assumptions and unknowns.
- **Request changes** sends a note, which is used in the next build.

**AI notice** (`lib/features/consent/ai_coaching_consent.dart`)

- The disclosure renders `get_current_ai_notice` and records that version. The built-in v1 text
  appears only when the server can't be reached.
- The consent gate asks again when the server's current version changes.

**Tests:** 17 onboarding widget tests and a generation-status test:

- the full journey and payload;
- the AI step: records only a changed answer, and shows the server notice;
- old-draft restores (section `context`, and `review` without the new answers);
- resume: running → proposal, answered → review, failed → Try again;
- request changes with a note;
- server-reported missing answers, including movements to avoid for an older draft;
- infeasible answers opening their step;
- an expired proposal at reopen and while approving, each rebuilt and approved;
- under-18 refused;
- Sign out.

Plus notice parsing and version tests.

**After merge and install** (owner):

1. ~~Publish v3 for every purpose~~: replaced by `ai-coaching-v4`, published by migration in
   PR B. The app asks once, and you accept.
2. Create a second test account on the phone and complete both paths:
   - close the app while the plan builds, then reopen;
   - request changes;
   - approve, then check that Train shows the approved days and exercises and that the Coach
     knows your goal and equipment.
3. Delete the test account in Account.

## Coach intake (coach-quality PR 1, 2026-10-02)

Branch `claude/coach-intake`, migration `20261002110000_coach_intake.sql`, policy
`onboarding-policy-v2`. Why: the owner's fresh account got a valid AI plan that "ChatGPT could
give from height, weight and goal". The experienced path reduced to one free-text box, nothing
asked for lifts or weak points, and Apple Health was a 28-day average that changed the plan only
for short sleep.

- **New steps** (found by key, so older drafts resume): Your training (years, current plan, what
  has worked and stalled), Current lifts (experienced, optional barbell top sets), Focus (both
  paths, up to two muscles to bring up and three strong), and Coach questions after Review.
  Experienced athletes see 15 steps, beginners 13.
- **Server** (`_shared/onboarding/`): `strength.ts` (Epley with reps in reserve, starting loads),
  `health_history.ts` (usual months, break rule), `questions.ts` (0–3 follow-up questions from an
  allowlist; `onboarding-plan` `mode: "questions"`), focus minimums in `policy.ts` with a rules-plan
  top-up that lowers a minimum only to what fits, and `priority_volume_missing` in the validator.
- **Database:** `user_profiles.training_years/priority_muscles/strong_muscles`,
  `planned_exercises.target_load_kg` (copied at approval; hub 1.5, brief 1.6),
  `onboarding_questions` + `claim_/store_/release_onboarding_questions` (service role; one request
  asks per hash, only model outcomes are stored), `health_history_months` +
  `save_health_history`, usage purpose `onboarding_questions`, Coach context v8 with the new
  profile fields. Both tables are in the privacy export.
- **App:** `lib/features/health/health_baseline.dart` reads workouts, sleep and weight for 11
  completed months (HealthKit `readMetrics`), sends monthly totals once a month, and the Apple
  Health step shows usual vs recent. The questions and the plan wait (up to 30 s) for that upload
  and retry a failed one, so a late upload never changes the answers' hash between them; Skip
  starts the plan once the running question request settles. The proposal shows **Start at ‹kg›** and a Focus line; Train
  pre-fills the kg field.
- **Deviation from the plan, on purpose:** strength ratios (row ÷ bench, deadlift ÷ squat) are
  passed to the model as data, but code states no norm: published ratio norms vary with build and
  technique, and an invented band would be a fact the code cannot back. Sleep months count from 20
  nights and weight months from 4 weigh-ins (20 weigh-ins a month is rarer than the review
  assumed).
- **Not changed:** proposal `schema_version` stays 2.0 (`start_load_kg` is an optional key the
  validator now checks); volume limits; nutrition.
- **Verify after deploy:** `./scripts/verify-live-function.sh --all`; owner device test on a new
  account (experienced path, lifts, chest focus, answer or skip questions); read-only SQL for the
  `onboarding.questions.generated` and `onboarding.plan.generated` audit telemetry.

