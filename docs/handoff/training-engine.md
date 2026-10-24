# Training Engine Handoff

**As of:** 2026-10-23

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

Deterministic, coach-grade training rules: templates, progression from the sets actually logged, deloads, joint-friendly modifications, a screening gate and a same-day readiness adjustment.

## Chunks

B0 (Phase 1); B1 (Phase 2); B2, B3, B6, B7 (Phase 3); B4, B5 (Phase 4)

## State

B0 is live (#105, 2026-10-15).

**B0 (live, #105; Edge Functions only, no SQL or app change).**

- **Mock decision obeys the policy.** The deterministic daily decision
  (`_shared/providers/mock_coach_model_provider.ts`) picked its action from the evidence alone, so
  `PROCEED_AS_PLANNED` under `request_data` (recovery within baseline, no check-in) and
  `ADJUST_TODAY` under `maintain_only` or `request_data` (training load elevated) failed
  `parseCoachDecision` and coach-decide answered 503. It now words a candidate decision per piece of
  evidence, most pressing first (escalation first, only when the policy escalates), and returns the
  first one the decision contract accepts under the request's policy outcome; the contract stays
  the only copy of the policy rules. Where a change is not allowed, the plan is kept and the
  evidence still reported (elevated load keeps its `elevated_load` flag). A holding decision asks
  for the gaps the policy named (`recovery_check_in`, `health_context`, `nutrition_data`), and for
  today's check-in only when it named none. Escalation cites its evidence only when permitted.
- **Rules plan ranks exercises.** `buildRulesPlan` took the first catalog exercise per slot, and
  catalog.ts lists bodyweight first (production reads the catalog in slug order, which put band rows
  and assisted pull-ups first instead), so a full-gym lifter got bodyweight squats and push-ups.
  The athlete's exercises are now ranked (`rankExercises`, `_shared/onboarding/rules_plan.ts`):
  loaded before bodyweight (an exercise needing only a bench or a pull-up bar counts as
  bodyweight), compound before isolation, regressions after every other form, equipment by
  experience (intermediate: barbell, dumbbells, pull-up bar, machines, cables, kettlebells, bands;
  beginner: dumbbells, machines, barbell, cables, kettlebells, bands, pull-up bar), standard form
  before variation, then slug. Within a slot, an exercise for a focus muscle still short of its
  weekly minimum comes first (least-served focus muscle, then the athlete's focus order), then
  loaded before bodyweight, then the slot's pattern order. Weekly variety never trades away a
  focus muscle, drops from loaded to bodyweight, or picks a regression. Movements to avoid, level
  filtering and every volume, time and set limit are unchanged.
- **Catalog ranking field.** `CatalogExercise.role` (`variation` or `regression`, absent for the
  standard form) is set on eight entries in `catalog.ts` (regressions: hands-elevated push-up,
  dumbbell floor press, assisted pull-up). The database catalog has no such column, so the rules
  plan reads it from catalog.ts by slug; no migration. **For B1:** a database catalog row with no
  catalog.ts entry ranks as a standard form; catalog v2 should carry the role (or ranking) itself.
- **Weekly volume, measured against the pre-B0 rules plan** (sweeps run outside the repo):
  - Single focus muscle (4,800 cases: 8 equipment sets x 2 levels x 1-6 days x 30/45/60/90 min x
    10 muscles): focus sets reached never fall (0 lower, 197 higher, total 36,037 to 36,639); no
    focus muscle drops to 0. B0's first commit had 54 lower and 18 dropped to 0 (glutes at 30 min
    with dumbbells, home or gym, hamstrings with kettlebells), because ranking ignored focus.
  - Several focus muscles (10,368 cases with movements to avoid): total focus sets 123,167 to
    123,476; 4 cases lower by one set (dumbbells, 5 days x 30 min, glutes + hamstrings), 127 higher;
    26 muscle-level decreases, 149 increases, none to 0.
  - All weekly sets (720 plans, no focus, glutes, chest + back): 37,120 to 36,587 (-1.4%); 165
    plans have fewer sets, 20 more, because loaded compounds rest longer than the bodyweight forms
    they replace. By target muscle: back +3.5% (barbell deadlift counts as back), hamstrings -13%,
    glutes -8%, shoulders -4%, others within 1-4%. The bodyweight share of exercises fell from 67%
    to 29%.
- **Review notes (2026-10-15).** The reviewer accepted a regression on preferred equipment beating
  a standard form on less-preferred equipment; regressions now rank after every other form anyway
  (this also turns an experienced lifter's assisted pull-up into a lat pulldown). A variation on
  preferred equipment still ranks above a standard form on less-preferred equipment (front squat
  before goblet squat for an experienced lifter). Bodyweight-only intermediates see slightly less
  weekly variety (accepted). Since pull-ups count as bodyweight, a full-gym lifter gets lat
  pulldowns rather than pull-ups, and core work rotates only among the loaded options the athlete
  has (a full gym repeats the cable crunch); B2's templates are the place to revisit both.
- **Tests.** `mock_coach_model_provider_test.ts`: every policy outcome x all 128 subsets of seven
  evidence codes x missing data x decision kind (2,560 cases) passes `parseCoachDecision`; expected
  actions per policy; holding decisions ask for the named gaps. `rules_plan_test.ts`: golden plans
  for an experienced lifter in a full gym, a beginner in a full gym (includes a barbell compound),
  dumbbells only (both levels), bodyweight only, a pull-up bar alone (core rotates), and a glute
  focus at 2 x 30 min (dumbbells only, full gym); a single main-movement focus (quads, glutes,
  hamstrings, chest, back) always gets sets when an exercise for it is offered; the database
  catalog (slug order, no roles) builds identical plans; without focus, a loaded form free for the
  session beats bodyweight. `plan_contract_test.ts` now expects the dumbbells-only plan to open with
  a goblet squat (it asserted the old bodyweight squat). Deno suite: 407 passed, 0 failed,
  8 ignored.

**B1 (review; catalog v2 and coaching-standard data; migration 21; no behaviour change).**

- **Catalog v2** (`_shared/onboarding/catalog_v2.ts`): `exerciseCatalogV2` / `catalogV2BySlug`
  are the 72 v1 exercises, unchanged and in order, plus `secondaryMuscles`, `jointStress`
  (knee, back, shoulder: low, moderate, high), `regressions`, `progressions`, `substitutes` and
  `loadStepKg`. Catalog v1 and its exports are untouched (`coach_chat_provider.ts`,
  `onboarding-plan` and the prompt still read them).
- **Database mirror** (`20261015170021_exercise_catalog_v2.sql`): the same fields plus
  `exercise_role` (B0's request) as additive columns on `public.exercise_catalog`. No reader
  selects them yet. The migration refuses an unrated row or a dangling link.
- **Coaching standard** (`_shared/training/standard/`): `sources.ts` (12 open sources, each
  checked against PubMed on 2026-10-15, plus a Tracend in-house entry), `prescription.ts` (goal
  emphasis, rep ranges by emphasis x experience x compound/isolation, reps in reserve, RPE
  mapping, rest), `volume.ts` (weekly sets: minimum 4, growth 10, maximum 12/20; indirect set =
  0.5, Pelland 2026; 2 sessions per muscle; strength 2-3 sets), `progression.ts` (2-10% load
  increase, double progression trigger, +1 rep a session, load steps by equipment),
  `joint_stress.ts` (rating method). Every value is a `Sourced` with sources and a basis in our
  own words.
- **In-house values (owner or coach review):** the equipment load steps (barbell 2.5, dumbbells
  2.5, kettlebells 4, machines 5, cables 2.5 kg), +1 rep a session, the beginner cap of 12 sets,
  every joint-stress rating, and the substitute/regression/progression links.
- **For B2:** the standard differs from today's rules plan in places it does not yet read: strength
  rest 180-300 s (policy cap 240 s), beginner strength reps 8-12 (rules plan 4-6), hypertrophy
  compound rest from 90 s. Reconcile in B2 with the policy and ALGORITHMS §9.
- **Tests.** `catalog_v2_test.ts`: links point at real, other exercises; progressions and
  regressions mirror each other inside a pattern, never drop a level, never loop; substitutes are
  mutual and share pattern or target; vocabularies; load steps; the migration mirrors the TS rows.
  `catalog_plans_test.ts`: SHA-256 digests of 10,080 rules-plan proposals and model prompts
  (7 equipment sets x 2 levels x 1-6 days x 5 goals x 4 lengths x avoid x focus) recorded on
  477da79 match with catalog v1 and with the v2 entries. `standard_test.ts`: every rule value
  has a known source and a basis, every source is cited with a DOI and PMID, ranges are ordered.
  pgTAP `exercise_catalog_v2_test.sql`: ratings, links, mirroring, constraints, read access.

**B2 (review; Edge Functions only, no SQL or app change).** Based on #125 (the Phase 3 briefs and
Contract 8).

- **Templates** (`_shared/training/templates/`): `weekTemplate` turns the policy's split (days 1-3
  full body, 4 upper/lower, 5 upper-lower-push-pull-legs, 6 push-pull-legs twice) into sessions of
  slots in priority order (main, support, accessory), tuned by goal (strength: few accessories;
  muscle gain; aesthetic: shoulders, rear delts and arms first; fat loss and recomposition:
  compound-led, trunk first), experience (a beginner keeps at most 2 accessories a session) and
  length (short <= 45 min, standard, long > 75; the session keeps as many slots as its exercise
  limit and set budget hold). 4 profiles x 6 day counts x 2 experiences x 3 length tiers = 144
  template ids. `buildRulesPlan` picks the exercise for each slot with B0's ranking.
- **Exercise choice.** Full-gym plans keep the lat pulldown for the vertical pull; the week's second
  vertical-pull slot rotates, so an intermediate with a pull-up bar gets the pull-up (3 full-body
  days or more). Core work rotates (a trunk exercise is not reused in a week while another is
  free, loaded or bodyweight alike): distinct trunk exercises per rotating week went 54% -> 78%.
- **Fractional volume** (`templates/volume.ts`): `setWeights` (1 for the catalog's muscles, 0.5 for
  catalog v2 `secondaryMuscles`, read by slug), `fractionalWeeklySets`, `weeklyTargets` (strength
  6; growth 10, stretching to 11/15 with spare room; trunk 4). The rules plan starts exercises at
  2 sets, lifts the main lifts to 3, then adds sets where the weekly shortfall is largest, inside
  the session set budget, session length, exercise count, the policy's direct weekly maximum and
  the standard's maximum for the target muscle. The validator and policy are unchanged (direct
  sets on the target muscle stay the hard limit).
- **Reconciliation** (all recorded with reasons in ALGORITHMS §9): strength compound rest 120 s
  (<= 45 min), 180 s, 240 s (>= 90 min; policy cap kept, the standard's 300 s not used); beginner
  strength reps 8-12 (was 4-6), intermediate strength 3-6 (was 4-6); hypertrophy compound rest 90 s
  (<= 45 min) or 120 s (was 120/150 s); intermediate hypertrophy compound reps 6-12 (was 6-10);
  isolation reps from the standard (strength 6-12/8-12; hypertrophy 10-15); effort from the
  standard's reps in reserve (compound mid-range, isolation 2).
- **Contract 8.** `PlanPolicies.screening?: ScreeningOutcome` (missing = cleared). `policiesFor` and
  `generateOnboardingProposal` take it as a last optional argument; `trainingPolicy` takes it as a
  fourth. `moderate_until_cleared`: RPE <= 7 (range 6-7), reps floor 6, rest <= 180 s, the strength
  goal builds the `general` template with hypertrophy reps; a first note in the plan's assumptions;
  a line in the model prompt; `calculation.screening` in the proposal. The rules plan contains no
  conditioning. `see_professional`: `PlanBlockedByScreeningError` (exported from `plan_contract.ts`)
  from `buildRulesPlan`, `validRulesPlan`, `validateOnboardingPlan` and `generateOnboardingProposal`,
  before any model call; `policiesFor` does not throw. **For B6 / the lead:** the exclusion today
  lives only in the app (`onboarding_flow.dart` stops at the eligibility step), so nothing on the
  server maps this error yet. `onboarding-plan/handler.ts` (not B2's file) must catch it, in both
  the pre-check around `validRulesPlan(policiesFor(...))` and the background generation, and answer
  with professional guidance (not `generation_failed`), and must pass the stored outcome as the
  last argument of `policiesFor` and `generateOnboardingProposal`.
- **Digest change** (`catalog_plans_test.ts`, same 10,080 cases, re-recorded on purpose; none refused
  before or after). Plans by split are unchanged (full body 5,040; upper/lower 1,680; upper-lower-
  push-pull-legs 1,680; push-pull-legs 1,680), because the policy still chooses the split.
  Prompts: byte-identical for the 3,360 cases without a focus muscle; the 6,720 with one differ
  where a lowered focus minimum changed (416 cases, all higher, total 75,290 -> 75,926 sets;
  `policiesFor` now repeats the lowering until the plan reaches every minimum). Plans, per plan
  (average over the 10,080), before -> after:
  - sets 48.8 -> 47.4 (-3%); session estimate 46.5 -> 42.5 min (shorter rests);
  - direct weekly sets by target muscle: back 8.2 -> 8.7, chest 6.3 -> 7.5, quads 8.9 -> 9.3,
    shoulders 6.3 -> 5.8, glutes 5.7 -> 5.2, hamstrings 3.1 -> 2.9, calves 2.2 -> 2.1, biceps
    1.7 -> 1.4, triceps 1.6 -> 1.2, core 4.9 -> 3.4;
  - with indirect sets at half: back 9.7 -> 10.3, chest 6.5 -> 7.6, quads 9.0 -> 9.4, biceps
    9.6 -> 9.9, triceps 10.8 -> 11.3, shoulders 12.8 -> 13.1, glutes 17.8 -> 17.6, hamstrings
    11.9 -> 11.3, core 8.9 -> 7.6, calves 2.4 -> 2.2;
  - exercises 17.1 -> 17.4 a plan: compound 12.1 -> 12.1, isolation 5.0 -> 5.3, bodyweight (incl.
    pull-up bar and bench only) 6.1 -> 6.7, dumbbells 5.05 -> 5.15, cables 1.62 -> 1.49, barbell
    0.59 -> 0.60, machines 1.37 -> 1.36; lat pulldown 2,480 -> 2,640 uses, pull-up family 0 -> 1,080.
- **In-house values needing owner or coach review:** the slot orders and accessories per goal; the
  beginner accessory limit of 2; the 120/90 s hypertrophy rests and the 120 s short-session strength
  rest (below the standard's 180 s); counting the catalog's second and third muscles as full sets
  (the standard's rule) makes arms look served by rows and presses, so direct biceps and triceps
  sets fell 19-26% (a size goal can still get isolation work through the stretch target) and glutes
  pass the standard's maximum in 59% of plans (54% before) when counted fractionally (squats, lunges and hinges
  all count them; only the direct count is limited); the strength target of 6; the stretch halfway
  to the maximum; the per-exercise cap of 4 sets (3 for strength); the main-lift bonus. The upper
  sessions have no trunk work on purpose, so an athlete avoiding every upper-body movement is
  still refused as infeasible.
- **Tests.** `templates_test.ts` (shape of every goal x days x experience x length, golden week
  outlines, set weights, fractional sums, targets); `rules_plan_templates_test.ts` (valid plans for
  every goal x days x experience x length x three equipment sets x screening outcome, 5,400 cases;
  prescription equals the standard; rests by length; lat pulldown and pull-up; core rotation;
  beginner accessories; main lifts at 3 sets; an independent fractional count; the growth level
  reached; a golden 3-day size plan; moderate effort end to end including a model plan above the
  cap being refused; `see_professional` builds nothing and spends no model call). Existing goldens
  in `rules_plan_test.ts` moved to the new exercise mixes. The loaded-beats-bodyweight sweep now
  exempts trunk work and the pull-up family, which rotate by design.

**B6 (review; screening gate; migration 26; app change; B2 (#127) is on main).**

- **Questions and mapping** (ACSM 2015 preparticipation logic, our own words; plain wording, no
  diagnosis). Four yes/no questions in a new onboarding step, **Health check**, right after the
  boundary and terms: exercises regularly now; knows of a heart, metabolic or kidney condition;
  notices a sign or symptom now; and, only with a known condition and no symptom, a professional
  has cleared them. `screeningOutcome` (`_shared/training/screening/screening.ts`, pure, 16-row
  table test): any symptom gives `see_professional` (even after an earlier clearance: the
  symptom is current); a known condition with no clearance gives `see_professional` when not
  exercising regularly and `moderate_until_cleared` when exercising regularly; everything else is
  `cleared`. `outcome.ts` (Contract 8) is unchanged. Missing screening reads as `cleared`
  (`screeningOutcomeOf`).
- **Where the answers live.** The app saves them in the onboarding draft payload (`screening`:
  `exercises_regularly`, `known_disease`, `symptoms`, `cleared_by_professional`), and
  `parseOnboardingAnswers` reads them into the optional `OnboardingAnswers.screening`. Absent
  (an older app build) is fine; present but malformed asks again (`missing: ["screening"]`, 422,
  the app reopens the step). `answersSnapshot` adds `screening` (answers + outcome) only when
  present, so snapshots and hashes of drafts without it are unchanged and changing an answer
  builds new questions and a new plan.
- **Schema** (`20261017050226_onboarding_screening.sql`, additive). `public.onboarding_screenings`:
  `id`, `user_id` (cascade from `user_accounts`), the four answers, `outcome`, `screened_at`.
  Rows are only added (a new row per distinct set of answers); the newest row is current; no row
  is `cleared`. A check constraint (`private.screening_outcome`) keeps a stored outcome in line
  with its answers. RLS enabled and forced, owner read (`user_id = auth.uid()`), no client
  insert/update/delete. `record_screening_v1(exercises_regularly, known_disease, symptoms,
  cleared_by_professional default false)` (authenticated, security definer) works out the outcome
  in the database, adds no row for the same answers as the newest row, audits
  `onboarding_screening_recorded` (outcome only) and returns `{schema_version "1.0", outcome,
  screened_at}`. The SQL rule and the TS rule carry the same sixteen-row table in their tests.
- **Export and deletion.** `privacy-export` lists `onboarding_screenings` (`dataTables`, with a
  test); account deletion cascades from `user_accounts` (pgTAP deletes the auth user and counts
  rows). SECURITY_PRIVACY, DATA_MODEL, PRD, AI_SAFETY_SPEC and UX_FLOWS §4.1 updated.
- **App.** New step key `screening` (index 1; other steps shift by one, drafts restore by key).
  Continue calls `record_screening_v1`; `cleared` goes on, `moderate_until_cleared` shows "Your
  plan will stay at moderate effort." and goes on with a second Continue, `see_professional`
  shows "Please see a health professional first." and keeps Continue closed until an answer
  changes. The app mirrors no rule: it shows what the server returns. A draft past the step
  without answers returns to it. Contract fixture `test/contract/fixtures/record_screening_v1_0.json`
  with a complete-key-list test.
- **Server wiring** (built on B2, #127, now on main; the lead granted `onboarding-plan/handler.ts`). The
  handler reads the stored outcome through `OnboardingStore.screening()` (the newest
  `onboarding_screenings` row for the user; no row is `cleared`) once per request and passes it as
  the last argument of `policiesFor`, `preparePlan` (gateway.ts, one optional argument added) and
  `generateOnboardingProposal`. `see_professional` answers 422
  `onboarding_screening_see_professional` from the pre-check, in both plan and questions mode,
  before the claim, consent, budget, any model call or a generation row, so it cannot surface as
  `generation_failed`; the same request is refused every time. A limiting outcome is added to the
  generation snapshot (`screening`) so a changed outcome builds a new plan; a cleared athlete's
  snapshot and hash are unchanged. The Dart repository maps the code to
  `OnboardingScreeningBlocked`, and the flow returns to the health check showing "Please see a
  health professional first.". The stored row, not the draft, decides the outcome; the draft's
  answers only feed the snapshot and the app's restore. Tests: handler (cleared/no row, moderate
  with an RPE cap and its own hash, see_professional with nothing spent in both modes), gateway
  (policies carry the outcome), Flutter (refused plan shows the guidance).
- **A stricter outcome ends what was built under a weaker one** (review fix; all in migration 26,
  additive, same signatures, `schema_version` unchanged, so older builds keep working; no
  screening row means cleared and nothing changes for that athlete). Helpers in `private`
  (no client grant): `screening_rank` (cleared 0, moderate 1, see_professional 2),
  `current_screening_outcome` (newest row, else cleared) and `assert_screening_allows(user,
  built_under)`, which raises 55000 for `see_professional` ("a health professional must clear
  this athlete first") and for a current outcome stricter than the one the plan was built under
  ("the plan was built before the health check changed"; built-under is the snapshot's
  `screening` field, absent meaning cleared). Where it is enforced:
  - `record_screening_v1`: when it stores a stricter outcome it expires the athlete's pending
    2.0 proposals built under a less strict one and supersedes a running generation, so a plan
    started while cleared cannot outlive the symptoms recorded afterwards.
  - `persist_onboarding_proposal_v3` (`create or replace`, body as in 20261002110000 plus the
    guard): a worker that finishes after the outcome changed cannot store a plan.
  - `respond_to_onboarding_proposal_v2` (`create or replace`, body as in 20261002110000 plus the
    guard, on accept only): `see_professional` refuses approval and `moderate_until_cleared`
    refuses a plan built as cleared; reject and revision still work. The 55000 is read by the app
    as "this proposal can no longer be answered" and answered with a rebuild, which the Edge
    Function then builds as moderate (or refuses).
  - `get_my_screening_v1()` (authenticated, `schema_version "1.0"`) returns the current screening;
    on reopening, when the draft points past the health check, the app reads it and a stored
    `see_professional` returns to the check instead of resuming the generation or the proposal.
    If it cannot be read the app resumes, and the server still refuses at approval.
  - pgTAP `onboarding_screening_gate_test.sql`: symptoms after a cleared plan (pending proposal
    expired, cannot be approved), a running generation superseded, `see_professional` and moderate
    refusals at store and approval, reject still allowed, a cleared plan stays approvable, a
    moderate plan built as moderate is approved, no row is unaffected, grants checked with
    `has_function_privilege`.
  - Stale response: while the answers are being recorded `_answerScreening` ignores changes
    (pointer and VoiceOver), and the response is applied only when the answers still equal the
    submitted ones. Widget tests cover both the lock and the reopening.
- **Open.** (a) Should a professional's clearance override a current symptom? Today it does not
  (conservative). (b) The question texts and "regularly" definition (30 minutes, 3 days, 3 months)
  are ours; a coach or the owner should review them. (c) Re-screening later (a yearly or
  after-injury prompt) is not built.

**B3 (review; progression from the sets actually logged; migration 23; hub 1.7; Train change; based on #130).**

- **Where the rules live: SQL.** The training hub, which Train reads, is a SQL function, and the sets
  live in the database, so the targets are computed in the hub's transaction by
  `private.next_session_targets(user)` and the pure `private.progression_decision(...)`
  (`20261017140023_progression_targets.sql`). A Deno module would have needed a new Edge Function
  and a second copy of the rules for the app. The Deno side (`_shared/training/progression/
  targets.ts`) holds the payload types, a strict parser and the words Coach is given, with tests
  that keep it and the migration from drifting.
- **Hub 1.7 (additive).** `schema_version` is `1.7` and there is one new top-level key,
  `next_targets`, an array of `{planned_exercise_id, exercise_key, name, action, reason, load_kg,
  reps, sets, confidence, basis: {last_date, recent[]}}` in plan order. Every 1.6 key is unchanged.
  The hub body is copied from `20261004090000_exercise_muscle_references.sql` (the newest definition;
  nothing later redefines it) and differs by the two lines for `schema_version` and `next_targets`
  (a Deno test asserts exactly that). An exercise without logged sets in the last 180 days has no
  entry, and the plan's prescription stands. Two existing pgTAP tests asserted `'1.6'`
  (`train_redesign_data_test.sql`, `coach_intake_test.sql`) and now assert `'1.7'`.
- **Rules** (history is the athlete's completed sessions only; the working sets of a session are its
  completed sets at the top load, so warm-ups, back-off sets and unticked sets never count). For the
  latest session, first match wins:
  1. pain flagged on that session, or on any later performance of the exercise even with no
     completed set logged that day: hold;
  2. 28 days or more away: lower one step (hold when the exercise has no load step); 14 days or more:
     hold;
  3. skipped after the last logged session: hold;
  4. fewest reps below the plan's range: hold at the bottom of the range; twice in a row at the same
     load: lower one step;
  5. fewer sets than planned: hold (a cut-short session is never read as a stall);
  6. three sessions at one load with no more reps per set than the oldest of them (and not at the
     top of the range): lower one step (hold without a step);
  7. fewest reps in reserve below the plan's (10 minus the target RPE, 2 when unset): hold;
  8. every set at the top of the range: add exactly one load step and restart at the bottom of the
     range (hold at the top without a step: needs a harder variation);
  9. otherwise add one rep (the standard's `repsAddedPerSession`) to the weakest set, up to the top.
  The load step is `exercise_catalog.load_step_kg` (B1). Bands, benches, bars and exercises without
  a catalog link have no step, so they progress by reps only. **Assisted exercises** (`assisted-*`
  slug, else a name starting "assisted") log machine help as the load, ranked as
  `get_my_exercise_history` ranks it: the working load is the least help, 0 is a real value
  (unassisted), so progressing reduces the help by one step (never below 0; at 0 it holds) and
  lowering adds one step of help. A target is never more than one step from the last logged load
  and its reps are always inside the plan's range (pgTAP sweeps both). Reps in reserve come from `rir`, else from `rpe` (10 minus RPE); when a
  working set has neither, `confidence` is `low` and the target is not blocked by it.
- **D9.** Heart rate is not an input anywhere; a Deno test fails if the migration's code mentions
  heart rate.
- **Coach context (Contract 7).** The targets reach Coach through the `training_plan` contributor
  (A10, `_shared/coach_context/contributors/training_plan.ts`), which reads
  `public.get_progression_summary_v1(p_user_id)` (`{schema_version: '1.0', targets}`, service role
  only, checked with `has_function_privilege`) inside `get_coach_plan_state_v1` and renders each
  target beside its planned exercise. The standalone `progression` contributor was removed.
- **Train.** Each exercise with a target reads "3 × 6 to 8 · next 75 kg × 6" in the list; its sheet
  shows a **Next target** tile in place of **Today** and one sentence of why ("Every set reached the
  top of the range last time. Add weight and start the reps again."); the workout screen starts each
  set from the target, before last time's set ("Your next target"). VoiceOver reads the target. An
  assisted exercise reads as help, as the workout screen words it: "next 15 kg help × 6" or
  "Unassisted × 8", "15 kilograms of help" in VoiceOver, and the reasons say "less help" and "a step
  more help" (`isAssistedPlanned` in `train_parts.dart`; `test/train_next_target_test.dart`).
  Reason codes this build does not know show the target without a sentence. Older builds ignore
  `next_targets`.
- **Tests.** `progression/targets_test.ts` (Deno) and `contributors/training_plan_test.ts` (A10),
  pgTAP `progression_targets_test.sql` (decision table, invariants, real logged sets through the hub,
  exact key lists, grants), `training_hub_contract_test.dart` (v1.7 fixture `training_hub_v1_7.json`:
  full key lists, parsing, older payloads, Train lines, set suggestions).
- **Open.** (a) The in-house numbers: 14/28 days away, three sessions for a stall, one rep a
  session, the equipment steps (B1), lowering by one step. All are a coach's or the owner's to
  review; they sit in `private.progression_rules()` and the decision function. (b) Sets are never
  changed by progression (the target repeats the plan's set count); volume belongs to the plan and
  B5's deload rules. (c) The decision looks at the heaviest working load only; a session logged at
  two loads is judged on the heavier. (d) Train shows the target, but Today's session card and the
  plan editor do not yet.
**B7 (goal phase review, 2026-10-17; review).** Fixes a failure the owner hit in Coach chat: weight
fell from 90 kg (3 June) to 74.8 kg (13 Oct), 15.2 kg or 16.9%, with the goal `fat_loss` and no
target. Coach saw about six weeks of weight, said "7 kg" and extrapolated "about 66.5 kg in 12
weeks", which the athlete read as advice. Migration 27 (additive), Edge Functions and one Progress
card; no frozen SQL function changed.

- **Deterministic review** (`_shared/training/goal_phase/**`, rules in `docs/ALGORITHMS.md` §5):
  phase summary (start from goal activation, never the goal's saved weight; smoothed start and
  current; change in kg and %; weeks; weekly rate; BMI; target present), the implausible-reading
  rule (60 kg between 87 and 83 is excluded and reported), and the five outcomes `continue`,
  `ask_target`, `consider_maintenance_or_diet_break`, `target_reached`, `slow_down`. Every reason
  carries source ids; `sources.ts` holds six sources whose DOIs were checked against Crossref
  (Garthe 2011, Helms 2014, Byrne 2018, Trexler 2014, the 2013 AHA/ACC/TOS guideline, WHO 2004).
- **Contributor** `coach_context/contributors/goal_phase.ts`: volatile slot, 2,200 characters,
  registered in `registry.ts`. It reads `get_goal_phase_inputs_v1` with a service-role client built
  on first use. `coach-chat/index.ts` now renders the contributors on both the gateway and the
  legacy path (the legacy path passes them into `buildCoachChatUserMessage`, between the athlete
  file and the question).
- **Owner-shaped test** (`goal_phase_test.ts`, synthetic data): start 90 kg, now 74.8 kg, change
  -15.2 kg (-16.9%) over 18.9 weeks, BMI 23.1, the 60 kg reading excluded, outcome
  `consider_maintenance_or_diet_break` (`long_continuous_deficit`, `large_total_loss`), `needs_target`.
- **Athlete-set target.** `set_goal_target_v1`, `get_goal_target_v1` (both `schema_version "1.0"`)
  and `get_goal_phase_inputs_v1` (service role). The target sits in `user_goals.details` beside
  the `target_weight_kg` that onboarding already wrote, so the frozen athlete file carries it. RLS
  by `auth.uid()`, audit event `goal_target_set` (kinds only), pgTAP `goal_targets_test.sql`
  (grants through `has_function_privilege`, key-list test, refusals, cross-athlete). Contract
  fixtures `goal_target_v1_0.json` and `goal_target_none_v1_0.json` with a key-list test in
  `test/contract/goal_target_contract_test.dart`. App: `lib/features/goals/**`; the **Set your
  target** card sits under the weight hero on Progress.
- **Audit items.** (5) goal details render only from a whitelist of free-text note keys (weights
  dropped) labelled "entered when the goal was written"; the goal-phase block states the date the
  goal began; the target is read from the new `target_*` keys. The old reads of
  `target_value`/`deadline` (never selected by the frozen SQL) are gone. (6) The contributor label
  now says a figure Tracend calculated from the athlete's records outranks a saved goal detail or
  an older note, and never overrides Tracend's rules. (7) `weightReadings` excludes implausible
  readings from chat trends. (8) horizon rows need a target weight still ahead and never go below
  the BMI 18.5 floor; the persona allows estimates only toward a set or stated target.
  (9) No tools: Coach never says it changed, saved or set anything. (10) The persona no longer
  claims a journey or training history; change claims state their window, except the goal phase.
  (11) Replies about 120 words, three bullets, one question. (12) The reply check
  (`guard.ts`): rejects a future weight below the floor, or beyond today's weight in the trend's
  direction with no target, with a rule-specific repair line. (13) Evals in
  `_evals/coach_chat_eval_goal_phase_test.ts` (6-week window, stale goal detail, 60 kg outlier,
  healthy BMI with no target, length rule) assert on the rendered prompt and calculators; no model
  call.
- **Review fixes (Opus review of #136).** The calculators emit no kilogram rows at all without a
  target weight still ahead (only the pace), and rows stop at the target; the reply check limits
  `projection_without_target` to sentences with a time or pace cue, passes questions and target
  suggestions ("aim for 70 kg") and applies a limit word only to the weight it governs, while
  `weight_below_healthy_floor` still covers every looking-ahead or target sentence; the Groq and
  Gemini branches receive the contributor blocks and the goal-phase rules; `get_goal_phase_inputs_v1`
  adds HealthKit daily weights on dates without a body measurement and skips rows without a weight;
  a refused target with no active goal says so.
- **Parity digests.** `coach_chat_parity_test.ts` records the new legacy request digests: the
  persona, the goal-phase rules and the goal-details wording changed on purpose.
- **B7.1 (recorded history, 2026-10-17; review).** Production reply: "over the goal phase since
  2026-07-04 you've gone from about 86.2 kg to 74.4 kg, a loss of 11.8 kg (13.7%)". True for the
  goal window, but the weight record starts 3 June at 90.0 kg (-15.2 kg, -16.9% to 74.8 kg), and
  the athlete says "since I started". TypeScript only (`get_goal_phase_inputs_v1` already returns
  the newest 400 readings of every source; no migration). `summarizeGoalPhase` adds `history`
  (first reading, smoothed like the phase start, change, weeks; only when it starts 7 or more days
  before the phase) and `continuousLoss` (the run of falling weight ending now, from its high
  point; a rise above 3% ends it, so a gain phase before a cut is excluded; kept only when it
  differs from the goal phase). The long-deficit and large-loss rules judge the continuous loss
  when present (an athlete 13.7 weeks into the goal but 18.9 weeks into a cut is judged at 18.9;
  outcome precedence unchanged). The contributor text shows "Recorded history" and "Goal phase
  (type, since date)" with explicit dates (about 1,350 characters of the 2,200 on the owner's
  shape); the precedence label is untouched, so no parity digest changed. Tests: owner's shape
  with the goal activated 3 July, gain then cut, a small versus a large rebound, a flat stretch
  before the goal, history equal to the phase, one or no reading before activation, the reply
  check on history sentences, and an eval on the rendered prompt. Open: (a) a plateau inside a
  run does not end it (only a rise above 3% does), so a hold at maintenance followed by a restart
  counts as one run until the weight rises; (b) the run tolerance (3%) and the history lead
  (7 days) are in-house values for owner review; (c) the persona line about change windows still
  names "the goal-phase reference data" as the source for whole-journey change, which now
  includes the recorded history, so its wording is unchanged.
- **In-house thresholds for owner or coach review** (`goal_phase/thresholds.ts`, `inHouse: true`):
  BMI 19.5 as "near the floor" while still falling; 3 weeks before a fast pace counts as sustained;
  16 weeks and 5% loss as a long continuous deficit (the trial arm length and the guideline's
  meaningful loss, combined by us); 10% over 12 weeks as a large loss (top of the guideline's first
  goal, our checkpoint); 0.1 kg a week as "still losing"; 0.5 kg tolerance for a reached target;
  3% plus 1.5% a week of gap as the implausible-reading allowance; 14 days as a stale reading.
  Evidence-backed: BMI 18.5 (WHO) and 1% of body weight a week (Helms, Garthe).
- **Open.** (a) The reply check is a pattern match on sentences with a future cue and a weight; a
  reply that hides a projection in a table of numbers without a cue would pass (the persona and the
  repair line still forbid it). (b) The target UI offers one kind of target at a time; the function
  accepts several. (c) Reply length is a prompt rule, not validated. (d) A body-fat target is
  stored and shown to Coach but no rule reaches it yet (no body-fat reading exists to compare).

### Week ahead and muscle overlap (2026-10-18, `claude/coach-week-ahead`)

`_shared/training/schedule/muscles.ts` is the one exercise-to-primary-muscle mapping (a muscle counts
at 2 direct sets); `week_ahead.ts` builds the next 7 days and the back-to-back muscle overlaps from
it, and `standard/volume.ts` holds the rule value (`minimumDaysBetweenSessionsPerMuscle`, 1 day).
B5 (deloads, joint rules) and the planned Watch-outs block should import these instead of mapping
muscles again. Full account in [`ai-gateway.md`](./ai-gateway.md) and ALGORITHMS.md.

### Advanced level and staple lifts (2026-10-23, `claude/advanced-level-catalog`)

Why: the Coach simulator found that the top level was "intermediate" and the catalog had no
weighted pull-up, close-grip bench press, conventional deadlift or Bulgarian split squat. The owner
(5-6 years of training) approved adding both. Full rules and numbers: ALGORITHMS "Advanced level".
Migration `20261023100050_advanced_level_catalog.sql` (additive); no hub or RPC shape changed, so no
`schema_version` bump and no contract fixture.

- **Level, end to end.** The database already had `experience_level` = beginner | intermediate |
  advanced, so only the catalog's `level` check widened. `ExperienceLevel` and `experienceLevels`
  (`onboarding/catalog.ts`) replace the two-level literals; `allowedExercises` offers an athlete
  every exercise at or below their level. `OnboardingAnswers.experience` carries `advanced`, chosen by
  the athlete (`experience: "advanced"` in the draft, from 3-5 or over 5 years; anything else reads
  intermediate). Coach's `StateProfile.experience` passes the stored level through (it used to
  collapse advanced into intermediate). Standard, templates and the rules plan are keyed by the
  level. The Flutter Training step shows the choice; the review shows "Advanced". Existing athletes
  keep their level; nothing rewrites it.
- **Staples** (all level `advanced`, so intermediate and beginner plans, prompts and the 10,080-case
  digests are byte-identical): `weighted-pull-up` (bar + dumbbells), `close-grip-bench-press`,
  `incline-barbell-bench-press`, `bulgarian-split-squat` (dumbbells + bench). Each has secondary
  muscles, an in-house joint-stress rating, links (a pull-up progresses to the weighted pull-up, the
  Bulgarian split squat follows the dumbbell reverse lunge; the two bench variations substitute the
  bench press), role `variation` and a 2.5 kg load step. `conventional deadlift` was not added:
  `barbell-deadlift` is it. None uses the rear-delt split of #156 (`schedule/muscles.ts`); the
  incline press lists `shoulders`, which that file counts as front and side delts.
- **Standard** (`standard/`): `moesgaard_2022` and `refalo_2023` added as sources (DOI and PMID checked
  against PubMed); advanced rows in `repRanges`, `targetRepsInReserve`, `weeklySetsPerMuscle`
  (`advancedGrowth` 12, `maximum.advanced` 20), `trainingDaysPerWeek`; `undulation` and
  `undulatedRepRange` (heavy and light compound ranges). No source separates advanced from other
  trained lifters except ACSM 2009's frequency and loading summary, so only the build-up level (12) and
  stretch (16) differ from intermediate; reps, reps in reserve, rest, maximum and progression repeat
  the intermediate values with their own bases.
- **Templates** (`templates/advanced.ts`): heavy and light days per split, one more direct accessory
  where a non-strength session has room, and `Slot.prefers` (Bulgarian split squat in the first
  lower session, incline press on the five-day push day). Intermediate templates are untouched
  (goldens and digests).
- **Rules plan:** heavy and light compound rep ranges, a note when an advanced lifter trains fewer
  than 4 days, a progression line naming the heavy and light days. Screening is unchanged and tested
  with advanced (moderate effort, see_professional).
- **Tests.** Deno: `rules_plan_advanced_test.ts` (level plumbing, validity sweep of 1,800 plans, screening,
  heavy and light ranges, targets, staples, goldens), `coach_proposals/advanced_level_test.ts`,
  `catalog_test.ts` and `catalog_v2_test.ts` (migration mirrors across both migrations, staples'
  ratings and links), `templates_test.ts`, `standard_test.ts`. pgTAP `advanced_level_catalog_test.sql`
  (level check, the four rows, links, progression from 0 kg added) and two updated assertions
  (`onboarding_plan_v2_test.sql` 76 rows; `exercise_muscle_references_test.sql` allows a reviewed name
  that is also a catalog name only with the same muscles). Flutter: `phase_2_flow_test.dart` (picker,
  guard, review), `profile_goals_test.dart`.
- **Deploy order and the short window.** The migration runs before the functions deploy. For that
  window the old `onboarding-plan` treats every non-beginner as intermediate and offers the four
  advanced rows to intermediates; they are valid catalog exercises, so nothing breaks. A plan built
  in the window is stored under the old snapshot hash (`catalog_version` `catalog-v1` is part of
  it); the new function uses `catalog-v2`, so it never reuses that plan for the same answers and
  builds a fresh one (the version keys only the generation reuse and the proposal's evidence; no SQL
  reads it). Rollback risk: rolling the function back to before this PR leaves the four advanced
  rows in the catalog, the old function offers them to intermediates again, and plans built under
  v2 are not reused by v1 either; neither can be un-offered without a migration. A Flutter build is
  only needed for the picker; the older picker never sends `advanced`.
- **Review round (Opus, #162).** Heavy and light days of one lift now keep separate progression
  histories (`next_session_targets` redefined in the same migration); the weighted pull-up is
  flagged `added_load` and starts from bodyweight (the first 2.5 kg); `buildAdvancedPlan` never lets
  a staple or the higher advanced targets leave a muscle under the intermediate twin's weekly sets
  (capped at the growth level); `get_coach_plan_state_v1` 1.2 carries `experience`, so home
  alternatives use the athlete's level; a one-session week has no heavy/light day; the catalog
  version moved to v2; two tests that could not fail now can. Left over: the twin comparison
  costs two to several builds per advanced plan (a few ms); the plan state's `experience` is the
  profile's stored level, which is null for an athlete who never recorded it (read as intermediate).
- **Final review (#162).** A next-session adjustment ("make Thursday heavier or lighter") matched
  its progression target on the lift's slug, so a light day of a lift that is also on a heavy day
  used the heavy day's load. `get_coach_proposal_inputs_v1` is now 1.1 (same migration, additive) and
  carries `planned_exercise_id` on every plan exercise; `training.ts` matches the target on it, as
  the Coach context does, and a planned exercise with no target (or an older payload without the id)
  has no target: it never borrows another day's. Known behaviour, kept: an athlete who moves from
  an intermediate to an advanced plan has no target for a split lift's day until that day is logged
  once under its own range (range-matched history only; missing data lowers confidence and is never
  invented). `plan_rules.ts` carries start loads across a plan rebuild: a lift the old plan has in
  one rep range carries by slug as before; a lift it has in several ranges (heavy and light days)
  carries only to a new exercise with the same slug and range, else nothing (it used to take the
  last day's load, so a light day could start at the heavy day's).
- **Candidates not added** (for the owner): weighted dip and dip station (no dip equipment in the
  picker), trap-bar deadlift (no trap bar), hack squat and pendulum squat, seated leg curl, hammer
  curl and EZ-bar curl, skull crusher, Pendlay and T-bar rows, pause bench (a technique of the bench
  press, not a new exercise), walking lunge, back extension. Front squat, Romanian deadlift, barbell
  hip thrust and the conventional deadlift already exist. Each needs equipment or a rating review
  before it joins.
- **Open.** (a) The three-year cut for choosing advanced, the 12/16 build-up and stretch, the
  heavy/light split point, the extra accessory lists and the joint ratings are in-house values for
  owner or coach review. (b) No cited deload cadence or advanced progression rate exists in the
  standard's sources: B5 owns deloads. (c) Session length and the 8-exercise cap bind before the new
  targets (weekly sets +1.6% at 60 minutes, +2.5% at 90); chest stays low in 60-minute sessions for
  both levels. (d) Changing level later has no screen of its own: the athlete repeats the Training
  step in a plan rebuild.

### Stale workouts (2026-10-23, `claude/stale-workout-resume`, migration `20261023150021`)

**Bug.** The owner opened today's Legs B and the app resumed a session left `in_progress` since
2026-07-17: the header timer read 2348 hours, today's sets were saved into the July session
(`local_date` 2026-07-17, so history, progression targets and day adjustments keyed by local date
went wrong), and Finish would have saved it as 3 hours (`complete_workout_v2` caps at 10800 s).
Production held four such sessions (2026-07-01, 2026-07-17, 2026-07-23, 2026-10-20).

**Cause.** `get_my_workout_session` (latest definition `20261015140031_set_timing.sql`) and
`start_workout` (`20260711190000_workout_truth_repair.sql`, the `state='in_progress'` lookup) find an
open session by planned workout alone, and a plan repeats weekly, so any session ever left open is
found again by the same workout months later. The only abandonment was the athlete's own
`abandon_workout` (and the repair flow's blank duplicate); no rule or job closed forgotten sessions.
The app then rebuilt the screen from the server row (start time in July). A local draft of the old
session did the same when the server returned nothing.

**Fix (additive migration).**

- `private.abandon_stale_workouts(p_user default null)`: an `in_progress` session whose `local_date`
  is before `private.local_date_for(user)` and that started more than 10800 s ago becomes
  `abandoned` (state and `updated_at` only), audited `workout.abandoned` with `reason: stale`, the
  completed-set count and the `local_date`. Sets, dates and start stay as they were;
  `actual_ended_at` stays empty.
- `get_my_workout_session` (1.1, same shape) is redefined `security definer`, not `stable`, and
  closes the caller's stale sessions before it looks. The app calls it before every open, so a stale
  session is closed before `start_workout` can find it. An hourly job (`tracend-abandon-stale-workouts`,
  minute 17) closes everyone's.
- App: a saved draft whose workout began on an earlier day than the session date and more than 3
  hours ago is dropped (`workoutLeftOnEarlierDay`), so it cannot open or seed today's workout.
- Choice for a stale session that has logged sets: **abandon, never offer to finish it for that
  day.** Finishing would write a completed workout the athlete did not confirm; moving the sets
  would change their date. The rows stay and the audit event records how many sets they held.
- A workout finished offline is never lost to the close. Server: `sync_workout_draft` and
  `private.complete_workout_session` accept a session whose audit event says `reason: stale`
  (`private.workout_closed_as_stale`), completing it on its own `local_date` with its end at its start
  plus the athlete's duration; a session the athlete discarded herself still answers 55000. App:
  `_restore` sends an earlier day's draft first (sets, then a saved finish; a session never created
  is created only when a finish waits) and drops it only once that succeeded or it held no done set
  and no finish; offline it stays and opens as saved. Set heart-rate summaries
  (`persist_set_heart_rate_v1`) still refuse any abandoned session. A leftover for a workout of
  another weekday is sent when that workout is next opened; the server keeps its session
  completable until then.
- `start_workout` is #165's definition (`20261023140024`, advisory lock first) plus
  `perform private.abandon_stale_workouts(auth.uid())` right before its open-session lookup, so a
  start can never find a stale session even when the read before it failed. A unit test pins the
  redefinition to #165's text plus exactly that line.
- Existing production rows are not touched by the migration; the hourly job closes the four on its
  first run after the deploy (the app does it sooner when the owner opens any workout).

Tests: `supabase/tests/database/stale_workout_close_test.sql` (see the file),
`_shared/training/stale_workouts_test.ts` (hunk pin and rule shape), and in Flutter
`test/phase_3_workout_flow_test.dart` and `test/workout_logic_test.dart`.

**B4-1 (review, #165; same-day readiness adjustment, server side; migration `20261023140024`, code 24).**
Based on the owner-approved B4/B5 design (2026-10-23; O2 to O13 as recommended, O1 amended). ALGORITHMS
section 4 has the rules; AI_SAFETY_SPEC section 6 the safety text; DATA_MODEL `day_adjustments` the
table; Contract 5 in the program plan the payload (1.0 as built).

- **An overlay, not a plan version.** `public.day_adjustments` stores the athlete's answers (kind,
  band, reasons, per-exercise changes, the values the rules read, a hash of them, accepted or
  declined, `origin` proposed or chosen, and the `rules_kind` the rules proposed at the time). RLS
  enabled and forced, owner read, no client write; export and deletion cover it.
  `workout_sessions.day_adjustment_id` links a session to the answer it was started under (composite
  foreign key, so only its own athlete's row).
- **Rules** (`private.readiness_rules`, `readiness_rank`, `readiness_assessment`; TS mirror in
  `_shared/training/readiness/rules.ts`). The check-in leads; sleep under 360 minutes adds a point;
  the recovery score adds a point only next to a point from the check-in, at medium or high
  confidence (D9). Pain of 7 or more gives `safety_route: pain_referral`, kind none, even on a rest
  day. No check-in: band unknown, nothing proposed. Confidence from what was available. Load ratios
  are not inputs.
- **Owner amendment to O1 (built).** The recovery score alone never applies or pre-selects an
  adjustment. The payload carries `signals` (score, confidence, mode, `recovery_low`, sleep minutes)
  and `options`: every kind that would change today's session, each with its own changes and
  sentence. `respond_to_day_adjustment_v1(local_date, accept, chosen_kind default null)` takes a
  third, optional argument so the athlete can pick a kind themselves with one tap; the stored answer
  has `origin = 'chosen'`. Undo is `accept = false`. A low recovery score with no check-in shows
  the trigger `recovery_low` and the sentence that asks for the check-in. Deviation from the brief's
  two-argument signature; additive and absent from old builds.
- **The kinds** (`private.day_adjustment_changes`, reading B3's targets): `hold_load` (last working
  load and fewest reps where B3 says add), `reduce_sets` (a set fewer from 3 sets, effort one point
  lower, not below 6; needs at least one set to go, else it falls back to `hold_load`, a
  clarification of "changes nothing"), `swap_to_easy_cardio` (every exercise to 0 sets; 20 to 30 easy
  minutes; no vigorous cardio).
- **Staleness.** An answer stands while it belongs to today's workout and the rules do not ask for
  something stricter than the greater of what they asked then and what the athlete answered. The
  brief compared only with the answered kind, which would have re-asked a lighter chosen kind; the
  `rules_kind` column fixes that. After the session starts it stands as it is. "Stands" decides what the card shows; `start_workout` does not ask it, and applies the current accepted answer as given.
- **`start_workout`** (same signature) takes the athlete's advisory lock for the day (the one
  `respond_to_day_adjustment_v1` takes), then links and applies the current accepted answer for the
  workout when the start is for the athlete's own today, without asking the rules again; `reduce_sets`
  builds the adjusted set counts, hold-load and easy-cardio answers keep the plan's sets. A backdated
  start gets the plan as written. Pinned to the workout-truth definition plus five hunks
  (`readiness_test.ts`).
- **B3 meets the adjustment.** `progression_decision` and `next_session_targets` (from the
  advanced-level definition) add `adjusted` and `sets_planned` to each session summary, per exercise:
  only an exercise the accepted answer lists is exempt from lowering a load or a stall and compares
  its sets with the adjusted count. The training hub is now 1.8 (the two keys appear inside
  `basis.recent`; the 1.7 body is copied with only the version changed; fixtures
  `training_hub_v1_7.json` and `_v1_8.json` and the Dart contract test cover both), `targets.ts`
  is unchanged.
- **Review round 1 (Codex and Opus).** (1) A start applies the accepted answer unconditionally and
  never computes the day. (2) A safety route wins over every stored answer, a started session
  included. (3) Respond and start share one advisory lock. (4) A start for another date gets the
  plan as written. (5) The sentence of a choice depends on the kind alone; a standing answer keeps
  today's band and reasons. (6) Adjusted is per exercise. (7) Undo is never refused by the 20-answer
  limit; unavailable days have their own sentences, never "Check in"; a body-weight or unassisted
  hold reads as such; the day's scores are made again for new Health data and a failed attempt is
  not repeated within ten minutes; `previous_answer.reason` says `check_in` or `new_data`; hub 1.8.
- **For B4-2 / other streams.** (a) The app must pass the hub's `local_today` as `local_date` (the
  server accepts only the athlete's own today by their account time zone; a device date can differ
  near midnight or when the time zone is unset). (b) Coach is not told about the adjustment yet: the
  `readiness` context contributor, the reply guard so Coach never contradicts an accepted
  adjustment, A8's `next_session` refusing on an adjusted day, the A5 daily snapshot and the A11
  eval cases are contract requests in the program plan. (c) The app words `previous_answer.reason`
  ("Your check-in changed" or "New data came in").
- **Tests that fail without each rule.** pgTAP `readiness_sweep_test.sql` (assessment rows and a
  47,628-case sweep; a 1,800-exercise matrix through the three kinds), `day_adjustments_test.sql`,
  new rows in `progression_targets_test.sql`; Deno `readiness_test.ts`; Flutter
  `day_adjustment_contract_test.dart`.
- **Not in B4-1** (for B4-2 and later): the app (card, toast, Undo, pre-fill, hiding the training
  note), the Coach `readiness` contributor, the A8/A5 changes and B5. The contract requests are in
  the program plan. The app should show `signals` in plain numbers against the athlete's baseline
  from the daily brief's drivers (the payload gives the score, confidence and mode, not the z-scores).
- **Open.** (a) Every threshold is in-house (O2) and waits for a coach's review after four weeks of
  data; log band, kind and answer from `day_adjustments`. (b) `explanation` is the full sentence
  (reasons plus action); the app may use it or compose its own copy from `triggers`. (c) The changes
  sweep runs a synthetic matrix of plans, not the B2 plan sweep.

**B4-2 (review; same-day readiness adjustment, app side).** `lib/features/readiness/` holds the
parser (`day_adjustment.dart`), repository, one shared controller (`DayAdjustmentController`, owned by
the shell and given to Today and Train), the card (`day_adjustment_card.dart`) and all its words
(`readiness_copy.dart`). No server change.
- **Date.** The date sent is always the server's: Train passes the hub's `local_today` after each
  hub load; otherwise the shell asks the hub (`get_my_training_hub(7)`) once and again only when the
  phone's day changes or the server refuses the date. The phone's date is never sent. An adjustment
  whose `local_date` is not the server's today is neither shown nor applied; an answer is sent for the
  day on screen.
- **States** (`dayCardState`): safety, proposed, accepted, begun (started or done, read only),
  declined, check-in, low recovery, cannot-train, coach-adjusted, note (mild pain or an earlier answer
  that no longer stands). A safety route is tested first and stands over any stored answer.
- **Heart-derived signals.** `recovery_low` with no proposal shows "What Tracend sees" and offers
  Check in, Talk to Coach and the three choices; nothing is applied or pre-selected. A choice is one
  tap and sends `chosen_kind`.
- **Reasons.** `previous_answer.reason` is `check_in` ("Your check-in changed") or `new_data` ("New
  sleep or recovery data came in"); any other value reads "Things changed since you answered". An
  accepted earlier answer is said to stay until the athlete chooses again, because `start_workout`
  applies the accepted unsuperseded row; the preview uses today's option of that kind.
- **Applied state.** `DayAdjustment.applyTo(workout)` previews an accepted answer (lower set counts,
  held target) on Train's lines, hero and overview and on Today's strip; the plan is never edited. The
  logger is not built from that preview: it gets the plan's set counts plus the held weights
  (`applyTo(..., sets: false)`), and after `start` it reads the session back (`get_my_workout_session`)
  and `ExerciseDraft.alignTo` makes each exercise have exactly the set rows the server made (untouched
  trailing sets go, missing ones are added; a restored draft or server session follows its rows too).
  `start_workout` is the only authority for the set shape, so a pending answer or an accepted row the
  phone does not know of (a safety day after reduce_sets) cannot desync the logger. Start is disabled
  while an answer is on its way, and the adjustment is read again whenever a workout screen closes.
  Easy cardio leaves the sets. `nextTargetWhy` explains a `day_adjustment` target.
- **One day.** The card shows only when its `local_date` equals the date the surrounding data was
  loaded for: Train reloads its readiness numbers for the hub's day, Today reloads the brief for the
  server's day when the adjustment names another one.
- **Talk to Coach.** `CoachDraftRequests` (shell-owned) puts a question in the Coach composer; it is
  never sent for the athlete.
- **Not done.** The easy-cardio heart-rate line ("under N bpm, the top of your Easy zone") is not
  shown: it needs the C3 profile loaded on Today and Train. The Home Screen widget snapshot still
  counts the plan's sets. `PlanChanges` is not announced: the overlay changes no plan, and Today and
  Train share the controller.
- **Tests.** `day_adjustment_card_test.dart` (every state, accept, keep plan, Undo, safety, stale
  data, wrong date, reasons, copy lint), `day_adjustment_controller_test.dart`,
  `today_day_adjustment_test.dart`, `train_day_adjustment_test.dart`,
  `contract/day_adjustment_rpc_contract_test.dart` (parses every B4-1 fixture, pins the parameters).

## Next agent starts here

B4-2 (the app side) is in review; B5
(deloads, cardio dosing, joint rules, pain check) builds on B3's targets (`private.next_session_targets`,
hub 1.7), the templates and B4-1's `day_adjustments`. B6's server wiring is done (see the B6
section). The briefs are in the program doc.
