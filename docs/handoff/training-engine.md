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
- Choice for a stale session that has logged sets: **abandon, never finish it for them.** Finishing
  would write a completed workout the athlete did not confirm; moving the sets would change their
  date. The rows stay and the audit event records how many sets they held. (Amended 2026-10-24: it
  is offered back for the athlete to save or discard, see "Unfinished workouts" below.)
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

### Unfinished workouts (2026-10-24, `claude/unfinished-workout`, migration `20261024050011`)

**Incident.** The owner logged 23 sets of Legs B on Fri 23 Oct from 16:45 and left without tapping
Finish. The hourly job closed it as `abandoned` at 00:47 and at 05:00 Coach said Legs B "was not
done". Logged training had silently become "not done". Completing it for them would write durable
history without approval (architecture rule 3), so the athlete is asked.

**Server (additive).**

- `private.unfinished_workouts(user, today)`: the rule. `abandoned`, closed by the stale rule,
  `local_date` within the 28 days before today (Coach's look-back), at least one completed set, and
  no completed session of the same planned workout on the same day (re-done). Each row has `save_by`
  (its day + 7): the athlete is offered it until then (the read and the resolve filter on it); Coach
  gets all rows with `offerable`. A session the athlete discarded in the app has no `stale` reason
  and is never listed.
- `get_my_unfinished_workout_v1` (1.0): the newest offered session, or `workout: null`; it closes the
  caller's stale sessions first. **A small RPC, not a hub field:** Today does not read the training
  hub (Train does, and the hub is already 1.8); the repair and match cards are separate RPCs too.
- `resolve_unfinished_workout_v1(session, 'save' | 'discard', effort)` (1.0): Save goes through the
  same `private.complete_workout_session` that `complete_workout_v2` uses for a stale-closed
  session, with the athlete's own effort; duration is the start to the last logged set (cap 10800 s)
  or unknown with no set times. A past-`save_by` or unknown session answers P0002, a discarded one
  55000. Discard keeps it abandoned for good; `private.workout_closed_as_stale`
  is redefined so a discard ends the late-send allowance. Both audited `workout.unfinished_resolved`.
  `abandon_workout` (20261003100000 definition plus one hunk): a replay on a session the rule already
  closed records the athlete's discard (`workout.unfinished_resolved`), so a discard queued offline
  does not come back as "didn't finish". Pinned: `private.complete_workout_session` is the 20261023150021 definition plus the unknown
  duration hunk; `workout_closed_as_stale` plus the discard clause; `get_coach_plan_state_v1` is
  the 20261023100050 (1.2) definition plus `unfinished` and 1.3. pgTAP: `unfinished_workouts_test.sql`.
- `get_coach_plan_state_v1` 1.3 adds `unfinished`. `coach_data_lookups_test.sql` and
  `advanced_level_catalog_test.sql` assert 1.3.

**App.** Today shows `UnfinishedWorkoutCard` under the hero: "You didn't finish Legs B on Fri 23 Oct ·
23 sets logged", "Save it by Fri 30 Oct", **Save workout** (the finish sheet, effort 1 to 10 required, then it appears in
history on its own date) and **Discard** (confirmed). Save first sends the phone's draft of that session
(`sync_workout_draft`, which a stale-closed session still takes; set times the server refuses are sent
again without them), so sets that never reached the server are not lost; when that send fails nothing is
answered, the draft stays and the card stays with the error toast. The draft is removed only after the
server accepted the answer, so opening the workout again cannot send its sets into a closed session; a
draft of a newer session of the same workout stays. A session that already refuses the draft (55000: an
earlier try saved it and the answer was lost) is not an error: Save still asks, and the server replays
"saved" (or says it was discarded, 55000, and the draft goes). A past-`save_by` or discarded workout
answers `UnfinishedWorkoutGone` ("This workout can no longer be saved."), and Today reloads the offer.
`_sendLeftOver` (opening a workout with an earlier day's draft) also treats 55000 as settled and
drops that draft instead of resuming its old session. The offer is read after the phone's queued
discards are sent, and a discard still waiting hides its workout. Today ignores an offer read that finishes after a
newer read or an answer, so a slow read never brings an answered card back. `UnfinishedWorkoutRepository` is implemented by
`SupabaseWorkoutRepository`; fixture mode offers nothing. Contract fixtures:
`test/contract/fixtures/unfinished_workout_v1_0*.json` and `resolve_unfinished_workout_v1_0_*.json`.

**Coach.** `training_plan.ts` parses `unfinished` (28 days, each `offerable` or not), adds one fixed
line per group ("Logged but not finished ..." for those the athlete can still save, "Logged but never
finished, and no longer offered ..." for the older ones; never that it was not done, skipped or
missed; names, dates and set counts through `record()`),
marks the session in the day-by-day list, and stops treating such a session as undone or as a
make-up candidate (it is the athlete's to save or discard; discarding returns it to undone). Only a
workout from the current ISO week stands for that week's session. `watch_outs` reads the same
`undone` list, so "Behind plan ... not done" no longer names it, and its streak line ("Planned but not
logged on each of its last days") treats a planned day with an unanswered unfinished workout as trained,
which ends a streak; the list covers the same 28 days the streak looks back over.

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

**B5-1 (review; pain check, red flags and joint rules, server side; migration `20261024060025`, code 25).**
Based on the owner-approved B4/B5 design (2026-10-23). ALGORITHMS section 4 ("Pain check, red flags
and joint rules") has the rules; AI_SAFETY_SPEC section 6 the safety text; DATA_MODEL `pain_reports` the
table; Contract 5 1.1 in the program plan the payload.

- **The pain check.** `public.pain_reports` (area, severity, pattern, red-flag answers, the clearance
  the athlete states, the outcome; append-only; RLS forced; export and deletion cover it).
  `private.pain_outcome(severity, red_flags)` is the one rule and a check constraint keeps a stored
  outcome equal to it. Ten red-flag codes (closed list); any code is accepted for any area (a stored
  flag is never wrong to act on). `save_daily_check_in` (phase 3 definition plus the pain check) takes
  `pain_area`, `pain_pattern`, `pain_red_flags`, `pain_cleared_by_clinician`, `pain_followups`; any of
  them marks a build that asks the questions, and then nothing is dropped silently (22023). A build
  that sends none behaves as before. `record_pain_check_v1` is the workout chip's writer
  (idempotent by key, own performance only, never a future day, 40 reports a day).
- **Joint states** (`private.joint_states`): held until a clearance (self-attested, severity 3 or
  less, no flag), limited and watch for 7 days after the newest report, watch for 7 days after a
  clearance, persistent at 14 days. Reports are ordered by day and then by when they were stored.
- **Safety routes.** Today's reports with a held outcome give `urgent`, `clinician_today` or
  `clinician`; the strictest of those and a check-in pain of 7 or more wins; band red, kind none, no
  options, trigger codes `red_flag:<code>`; applies with no check-in, on a rest day and after the
  session started, and stands over a stored answer. `private.day_adjustment_compute` is B4-1's plus the
  hunks (a Deno test pins them).
- **Joint rules** (`private.joint_changes`, `joint_swap`, `range_note_code`, `joint_options`,
  `merge_day_changes`): see ALGORITHMS. Joint changes ride on every kind and alone as the new kind
  `joint_adjust` (the one-tap answer and Undo are B4's). `start_workout` leaves out an exercise the
  accepted answer drops, under every kind. B3's `next_session_targets` treats an exercise an accepted
  answer lists, or limits for a joint, as adjusted.
- **Payload 1.1** is additive: `joint_states`, `exercise_joint_options`, the `joint_adjust` kind, the
  joint keys of a change (only on an exercise a joint touches), the three new safety routes and
  `red_flag:<code>` triggers. `_shared/training/readiness/payload.ts` parses 1.0 and 1.1.
  `get_readiness_context_v1` (service role) is the reader for Coach context.
- **For B5-2 (app) and the lead.** (a) The installed B4-2 parser reads `kind` and `safety_route`
  strictly (`DayAdjustmentKind.fromWire` returns null for `joint_adjust`): it must accept the new kind,
  the new routes and the new keys, or an athlete with a held joint sees no card; B5-2 must land with
  or before the first app build that sends the pain keys. (b) The app shows referral copy for each
  route (`safety_copy.dart`), the persistent line, the swap and range cues (`rules.ts` has the
  cues), and extends the `beforeSend` scrubber test for the `pain_*` keys. (c) Pain keys are only sent
  with an area and the red-flag answer; a refused check-in (22023) leaves the queue's envelope.
  (d) Contract request 1 (context) is built: Coach reads `get_readiness_context_v1` through the `readiness`
  contributor (see "Coach knows today's readiness card" in [`ai-gateway.md`](./ai-gateway.md)). Requests 2 and 3
  (red-flag screen, reply guard) are still open: a held joint is enforced by the prompt text alone.
- **Review round 1 (Opus).** (1) A hold on `urgent` or `clinician_today` keeps the safety route every
  day until the athlete's clearance (the copy says "until you've been seen"); a `clinician` hold gives
  a daily reminder line even with no exercise change; held states carry `hold_outcome`. (2) A stored
  answer stands only while its joint changes (exercise, joint, action, swap target) equal the ones the
  rules ask for now. (3) The in-workout options meet the same ceilings as the day's swaps
  (`private.joint_caps`). (4) A Coach-adjusted day offers `joint_adjust` alone. (5) `start_workout`
  creates a swapped exercise as a `substituted` performance named for the swap (reason `pain`).
  **For B5-2's logger:** take the exercise name from the performance row (`performed_name`), never from
  the planned exercise; the catalog slug of the swap is in the answer's change (`swap_to_slug`) because
  the performance trigger keeps no slug on a substitution; the load starts empty. (6) A pain check's date
  is the server's today or yesterday (a phone a day ahead is stored under today), and today's route also
  counts reports stored today. (7) The 40-a-day cap counts only reports that do not route out. Low: an
  exercise left out but trained earns no `add_load`; every cue of a limited exercise is kept
  (`range_note_codes`); two calls with one key take turns (an advisory lock) and replay.
- **Review round 2 (Opus).** Capability and gates: the two day-adjustment RPCs gained an optional
  `supports_joint_changes boolean default false` (the old signatures are dropped and recreated with the
  default, so every old call works and gets the old behaviour); `private.day_adjustment_compute` gained
  `p_joint`. **Contract for B5-2: pass `supports_joint_changes: true` on every read
  (`get_my_day_adjustment_v1`) and every answer (`respond_to_day_adjustment_v1`); a client that passes
  it on one and not the other would preview one session and store another.** Old clients keep seeing and
  getting plain readiness kinds and may accept `joint_adjust` (shown as a note). `start_workout` keeps
  its signature: it applies what was stored, and an answer that carries joint changes only while they
  equal today's. Reports are ordered by when stored (a backdated red flag after a clearance holds the
  area). The chip's options also avoid the exercises the day's own swaps go to. A clearance recorded
  later the same day ends that area's route for the day (a new check-in never does).
- **Choices where the brief was open (the safer one taken).** `pain_outcome` takes two arguments, not
  three (the clearance does not change an outcome; it lifts a hold in `joint_states`). A held area
  needs a clearance even when a later report says 0. A report older than 7 days lapses at 8 days (a hold never lapses).
  Persistent counts reports of 4 or more in the episode from the first to the day asked about, so two
  reports a week apart flag at 14 days. A swap must not trade one sore joint for another and is never
  harsher on any joint. A limited exercise with no RPE target gets effort 7. An unrated exercise
  counts as moderate everywhere. A joint change with no readiness kind needs the new kind
  `joint_adjust`. Today's red-flag reports from every check-in revision count (a superseded revision's report does
  not lapse) until the athlete's own clearance for that area, which also ends the route the same day;
  a red flag typed by mistake holds its joint until that clearance.
- **Tests that fail without each rule.** pgTAP `pain_checks_test.sql`, `joint_states_test.sql`,
  `joint_rules_test.sql`, `joint_swap_sweep_test.sql` (and the changed keys in
  `day_adjustments_test.sql`); Deno `joints_test.ts`; Flutter `pain_check_contract_test.dart`.
- **Not in B5-1.** The app (B5-2), deloads (B5-3), cardio dosing (B5-4), the Coach context
  contributor, the A9 screen and reply guard changes (contract requests), and the eval cases.

**B5-2 (review; pain check, red flags and joint changes, app side; no server change).** Based on B5-1's
contract (above) and B4-2's card. Words: `lib/features/readiness/safety_copy.dart` (one file, scanned
by the diagnosis-word test with `readiness_copy.dart`).
- **Contract.** `SupabaseDayAdjustmentRepository` adds `supports_joint_changes: true` to **every**
  `get_my_day_adjustment_v1` and every `respond_to_day_adjustment_v1` call (one constant,
  `_jointChanges`; a contract test pins both). No other code calls those RPCs.
- **Parser** (`day_adjustment.dart`). `DayAdjustmentKind.jointAdjust`; `JointState` (area, state,
  severity, `since`, `persistent`, `hold_outcome`), `ExerciseJointOptions` (`joint_options` per
  exercise), per-change `joint_action` (swap, limit, drop), `swap_to_slug`/`swap_to_name` (a swap
  missing either is read as no joint action), `range_note_codes` (else the single code). Unknown
  future kinds stay `unsupportedKind`, unknown joint states and actions are skipped, and any safety
  route (known or not) is shown, an unknown one with the `urgent` words.
  `applyTo(workout)` previews a standing accepted answer (swap name with no load, range cues, left-out
  exercise); with `sets: false` (the logger) set counts stay the plan's, but a left-out exercise is
  left out either way.
- **Card** (`day_adjustment_card.dart`, `readiness_copy.dart`). `joint_adjust` has its own title,
  button, toast and Undo; joint states, hold reminders (`clinician` holds, every day) and the two-week
  line are said once each; red-flag routes show `safetyWords(route)` and no training button.
  `routeNeedsAcknowledgement`: `urgent`, `clinician_today` and unknown routes cannot be dismissed
  without **Got it**.
- **Referral sheet once** (Today). `SafetyAcknowledgements` (per athlete, local) remembers the day and
  route acknowledged; `_showSafetyOnce` opens the sheet after a delivered or queued check-in (queued:
  from the answers by the phone's copy of the rules, `painOutcome`), after a pain report arrives, and on
  a later day a hold stands. In a workout the referral read in the result sheet is acknowledged for the
  day.
- **Check-in** (`check_in_sheet.dart`). Area, optional pattern and the area's red-flag questions
  (`redFlagCodesFor`); Save stays closed until the area and an answer (a tick or **None of these**) are
  given; follow-ups for each state in `joint_states` (**Gone** / **Still there**; held: **Yes** with a
  strength / **Not yet**). Pain keys travel only with an area and the red-flag answer. A clinician
  clearance for an area chosen again as today's pain goes as `pain_cleared_by_clinician` on that one
  report. A queued envelope is replayed on launch and whenever the app comes forward; `CheckInQueue`
  marks a pain check the server refuses (`pain_refused`, `pain_refused_too_old`, `painState`) and
  `acknowledgeRefusedPain` then sends the rest of the check-in without the pain keys. See "Review
  fixes" below for what the sheet does when a referral is due or the server refuses.
- **Workout pain chip** (`pain_check_sheet.dart`, `pain_reporting.dart`, `pain_report_queue.dart`,
  `pain_check.dart`). `record_pain_check_v1` with an idempotency key and the server's day
  (`serverDay`); the outcome is computed on the phone by the same table as `private.pain_outcome` (a test
  pins the table), so a referral shows even when nothing can be sent. A report that cannot be sent
  waits in `PainReportQueue` (per athlete), is sent again when the app comes forward and after each
  workout sync, and a 22023 marks it **refused**: it is never dropped, Today says so
  (`PainNoticeCard`) until **I understand**. Account deletion clears the queue and the
  acknowledgements.
- **Logger** (`active_workout_screen.dart`, `workout_draft.dart`). `_alignSets` takes each server row
  by its order: a row with **no sets** is `ExerciseDraft.leftOut` (page says "Left out today", no
  set card, nothing logged; the draft carries it with empty `sets`, status `unknown`, never
  skipped); a `substituted` row takes `performed_name` and `exercise_slug` (`takeIdentity`) and the
  draft sends `performance_kind`/`performed_name`/`substitution_reason` (`swapFields`); a swap made in
  the workout (**Use ‹swap›**, only before any set has an entry) is logged the same way and kept in the
  local draft as `swap_pending` (with its slug) until a server row says it. A name that differs under
  sets with entries is never relabelled (`takeIdentity` returns a conflict and changes nothing); the
  sync needs attention instead. Range cues show on a limited exercise.
- **`syncDraft`** now takes `readRows` and returns what it sent. Both callers pass it (the earlier
  day's left-over draft, read for the day it was made on; the unfinished-workout save,
  `get_my_workout_session` for the offered session). `alignPayloadToRows` drops only blank trailing
  sets beyond the rows (all of them when the rows cannot be read) and never a set with an entry;
  `completeWithEffort` gets the fitted payload.
- **Sentry.** `lib/app/sentry_scrubber.dart` (`beforeSend` and `beforeBreadcrumb`) removes the pain
  check from events and breadcrumbs, by key and by words in strings, and the "Failing row contains"
  text of a refused row. `main.dart` uses it; the old in-file scrubber is gone.
- **Safer choices where the brief was open.** A 4 to 6 result sheet can be closed (the athlete stays in
  charge); 7 or more, any Yes, a held area and a day with a safety route cannot. A refused report is told
  as "too old" only when the server's message is the date window (`isPainDateRefusal`); any other 22023
  gets "could not record it as it stands". Follow-up answers carry no red-flag question (the server's
  `pain_followups` take area, strength and clearance only).
- **Not done.** The pain keys are not on the Home Screen widget or Live Activity (by design). Today's
  meals and the Coach decision freshness still use the phone's date (B4-2 follow-up, unchanged).
- **Tests.** `joint_adjustment_card_test.dart` (joint_adjust accept and Undo, each route, hold reminder,
  swap, limit, left out, unknown kinds), `pain_check_test.dart` (outcome table, wire, queue),
  `pain_chip_test.dart`, `today_check_in_sheet_test.dart` and `check_in_queue_test.dart` (red-flag flow
  online and queued, follow-ups, refusals), `today_pain_notice_test.dart` (notice, referral once per
  day), `workout_server_rows_test.dart` (left-out and swapped rows, `syncDraft` alignment),
  `workout_repository_test.dart` (unfinished save fits the rows), `sentry_scrubber_test.dart`,
  `contract/day_adjustment_rpc_contract_test.dart` and `contract/pain_check_contract_test.dart` on the
  1.1 fixtures.

**B5-2 review fixes (Codex and a second hostile review of #176).**
- **Pain queue.** `PainReportQueue` changes storage only through one lock per athlete and by
  idempotency key: `drain` reads, sends one report, then removes or marks that one report, so a report
  added during a drain survives, a dismissed refusal stays dismissed, and `PainReportQueue.clearFor`
  (account deletion) wins over a drain that is waiting on the network. Drains in flight are joined, and
  each send first checks that the signed-in athlete (`PainReporting.signedInUser`) is still the queue's.
  `readiness.load()` runs after a drain only when it sent something (`PainQueueState.sent`).
- **The answer never waits on the network.** `PainReporting.submit` returns at once with the phone's
  outcome and a `delivery` future; the chip's form closes with it. A send that has not answered after
  8 seconds is kept in the queue and forgotten again if it lands. The result sheet shows the referral
  at once; a server that is silent changes nothing but the small "Saved on this phone" line. The
  check-in sheet closes at once for a referral (the envelope is queued and sent in the background,
  `CheckInSaved.pending`; Today then reads today again or says it waits); a check-in with no referral
  waits at most 8 seconds.
- **Refused check-in.** A 22023 never discards the check-in: the envelope is kept marked
  (`markPainRefused`), the local referral is still shown, and Today's notice sends the rest without
  the pain answers when the athlete has read it. Closing the sheet no longer depends on the answer.
- **Second offline check-in.** An envelope with a pain check is moved to
  `daily_check_in_pending.earlier.<uid>` (a list) instead of being overwritten, and every earlier
  envelope is sent first, in order (the last one sent is the day's check-in; a failure holds the later
  ones back, a refusal does not).
- **Held area and safety-route day.** The chip's result sheet is the stop sheet (referral or hold line,
  **Skip this exercise** / **End workout**) when the report routes out, the area is held (today's
  `joint_states`, or the server's `area_state` when it answers within 1.5 s) or the day has a safety
  route. `DayAdjustment.jointOptionsFor` is null on a day with a safety route.
- **Swap and restart.** `swap_pending` and the swap's slug live in the local draft. `takeIdentity` never
  renames an exercise with entries (round 2 below: the identity is sent with them instead of blocking).
  A set with entries and no server row is still a conflict: `_rowsConflict`, draft kept, nothing sent,
  **Needs attention**.
- **Sentry.** Pain keys go with their values in any text (`pain_area=back`, JSON, query strings), a
  refused row goes to the end of the line, and `pain_reports` and `record_pain_check*` are redacted.
- **Smaller.** The chip sends `red_flags: null` ("not asked": it asks 2 of 10; `record_pain_check_v1`
  takes null and judges by the strength) and the queue keeps that. A successful call whose answer this
  build cannot read counts as recorded, with the phone's outcome. A report just made always shows its
  referral (the once-a-day rule is only for what Today opens by itself). "a tear" is now "a ripping
  feeling" in the Dart and TypeScript question copy.

**B5-2 round 2 fixes.**
- **One ordered path for check-ins.** The check-in sheet no longer sends its envelope directly: it
  enqueues it and calls `CheckInQueue.replay`, so every older envelope goes first and this one last
  (the server counts the last one sent as the day's check-in). `CheckInQueue` takes a lock per
  athlete, changes one envelope by its key (`clearDelivered`, `markPainRefused`; never a list read
  before an await), and runs replays one after the other, so a check-in saved while a replay waits
  survives whether that replay lands or is refused. A refused check-in that a newer one for the same
  day has replaced is marked `superseded` and is let go, unsent, when the athlete reads the notice
  (sent late it would become the day's check-in again).
- **Refusals.** The day's limit on pain reports (`P0001`, "too many pain reports today") on a stored
  envelope with a pain check is a refusal like 22023 (marked, told, later envelopes go on); another
  `P0001` is retried. A duplicate idempotency key (`23505`) counts as delivered.
- **A conflicting row never blocks the workout.** `sync_workout_draft` records `performance_kind`,
  `performed_name` and the reason as sent (`coalesce` over the stored value; `prescribed` and
  `substituted` both pass the shape check). A server row of `prescribed` against a swap logged on the
  phone keeps the swap (`swapPending`); a row of `substituted` against sets logged under the plan's
  name keeps the plan's identity, which is sent as `performance_kind: prescribed` with the plan's name
  (`ExerciseDraft.keepsOwnIdentity`, kept in the local draft as `keep_identity`). Only a set with
  entries that has no server row still needs attention.
- **Smaller.** `area_state` that is not text reads as `none`; a send that fails with an error keeps
  the report and the answer; the result sheet opens whatever happens to the delivery; the check-in
  sheet falls back to "waiting" for any failure and never stays on "Saving".

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
- **Applied state.** `DayAdjustment.applyTo(workout)` previews a standing accepted answer (lower set
  counts, held target) on Train's lines, hero and overview and on Today's strip; the plan is never
  edited. An earlier accepted answer that no longer stands is shown in words only ("Your earlier
  choice (fewer sets) still applies until you choose again"): `previous_answer` carries no stored
  changes, so nothing is derived from today's options. The logger is not built from the preview: it
  gets the plan's set counts plus the held weights (`applyTo(..., sets: false)`).
- **Later 1.x payloads.** The parser ignores unknown keys, skips an option of an unknown kind, and keeps
  an unknown top-level kind as `unsupportedKind`: the card says the explanation and offers nothing to
  apply, and a safety route (known or not) is always shown, an unknown one with the strictest (urgent)
  copy. Fixtures `day_adjustment_v1_1_{joint,red_flag}.json` come from B5-1 (#172).
- **Logger rows.** `start_workout` is the only authority for the set shape. After `start` the logger
  reads the session back (`get_my_workout_session`) and `ExerciseDraft.alignTo` makes each exercise
  have exactly the rows the server made. Until a started session's rows were read once
  (`_rowsAligned`, kept in the local draft as `rows_aligned`; a draft without it counts as aligned)
  nothing is synced and the draft stays on the phone, and a finish waits; every save retries the
  read. A 22023 from a sync reads the rows again, aligns, and sends once more when they moved; a set
  with entries that has no row is never dropped and the sync shows Needs attention.
- **One day.** The card shows only when its `local_date` equals the date the surrounding data was
  loaded for. The controller exposes `serverDay` (the hub's or the server's today, known even when
  the read failed). Today records it as soon as it arrives, whether or not the brief has, and loads
  the brief for it (reloading when the newest request was for another day, in either order); the
  check-in sheet saves, and queues, under it (`showCheckInSheet(localDate:)`), so the rules find
  today's check-in and a pain-7 referral is not missed; the gate's day marks use it. Until the day
  is known the phone's date is used. Train reloads its readiness numbers for the hub's day.
- **Follow-up (not changed).** Today's meals (`loadMeals(DateTime.now())`) and the Coach decision
  freshness (`_dateKey(DateTime.now())`) still use the phone's date; they should follow
  `_serverDay` too.
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

**B5-3 and B5-4 (review; deloads and cardio dosing, server side; migrations `20261024060125_deloads.sql` and `20261024060225_cardio_dosing.sql`, code 25).**
Based on the owner-approved B4/B5 design (2026-10-23; O6, O7, O11, O13 as recommended, O1 amended).
ALGORITHMS section 4 ("Deloads", "Cardio Dosing") has the rules; AI_SAFETY_SPEC section 6 ("Deloads
and cardio dosing") the boundaries. No app change, no new table, no Edge Function.
- **Deloads.** `private.deload_rules()` (rules `deload-v1`), `private.deload_signals(user, date)` (status,
  reasons, last end, weeks since, proposal, suppression), `private.readiness_band_on` (the band a past day
  had, from that day's check-in, sleep and stored recovery score; never rescored here),
  `private.is_deload_proposal`, `private.training_guidance` (built 1.0 here, 1.1 in B5-4) and the two
  readers `get_my_training_guidance_v1(local_date)` (own today only; 22023 otherwise) and
  `get_training_guidance_for_v1(p_user_id, p_local_date)` (service role). Read-only. The A8 builder
  (`coach_proposals/training.ts`) now builds a deload as exactly one week (a longer length asked for is
  cut to one, not refused), half the sets rounded up, loads held, effort 7 or lower (no target becomes
  7), from `standard/deload.ts`; the old in-house `deloadRules` is deleted. The stored block carries
  `training.intensity_level` (`deload` or `moderate`), which is how SQL tells a deload from another effort
  block; a block approved before the key existed is found by its title "Deload until <date>".
- **Cardio.** `private.cardio_rules()` (`cardio-v1`) and `private.cardio_week(user, date, band)`;
  `private.training_guidance` is replaced by 1.1, B5-3's text plus three hunks (pinned by
  `deload_cardio_test.ts`); the readers are unchanged. Observed minutes are the union of the
  athlete's cardio workouts (overlaps count once, 180 minutes a workout), so a watch and a phone
  recording one walk never double count.
- **Strictest wins, and the safety route.** Nothing here computes a safety route: the guidance reads it
  from `private.day_adjustment_compute` (so it is exactly the day adjustment's route, including a held area's
  urgent or same-day outcome), turns a suggested deload into `not_due` (`suppressed_by` `safety_route`) and
  withholds the cardio dose (`cardio_withheld` `safety_route`). A running deload is an ordinary plan
  version, so a held or limited joint still swaps or drops its exercise and a poor night still takes a
  set off it (pgTAP `deloads_test.sql`, the interplay groups). The original migrations redefine no
  existing function except B5-3's own; review round 1 (below) replaces `next_session_targets` and
  `respond_to_coach_proposal_v1` in a new migration.
- **Choices where the brief was ambiguous (the safer one taken).**
  (a) Deload start load: the lower of the last working load and the B3 target's load (for an assisted
  exercise the higher help), not the last load alone: a target that steps down is followed, a step up never.
  (b) A deload length other than 1 is cut to 1 rather than refused, so Coach's request still produces
  a card. (c) `vigorous_allowed` needs a green band today: no check-in (unknown), amber and red are
  easy-only days, and a joint that is held or limited closes it too; `vigorous_sessions_max` follows the
  health check only. (d) Under `see_professional` no cardio dose is given (the brief was silent).
  (e) An undone deload is not counted as the last one; a block ended early counts as ended today.
  (f) A past day's band uses that day's assessment only (a pain of 7 or more reads red) and not that
  day's joint or pain-report routes. (g) "Opt-in" for the block-end offer (O13) is read as "only ever a
  suggestion"; no preference is stored. (h) The cardio dose counts only plugin workout names that are
  cardio; undercounting can only understate the week. (i) HHS 2018 is not in `sources.ts` (it has no DOI or
  PubMed id; WHO 2020 and ACSM 2011 state the same dose). (j) `rpe_cap` 7, the half and the one week are in
  `deload_rules()` although SQL does not read them: the builder does, and one drift test pins both sides.
- **B3 after a deload.** The first session after a deload week reads as incomplete against the
  restored plan's full set count, so B3 holds the load for it (reason `incomplete`) and moves on after one
  full session. Review round 1 corrected the earlier claim that deload sessions need no marking: a held
  load at half the sets looked like a stall (same load, reps not rising) and gave `lower` during the week
  and on the first full session after it. Sessions logged under a deload week's plan version are now
  marked `adjusted` in `next_session_targets`, so they are never stall or lowering evidence.
- **Review round 1 (migration `20261024060325_deload_cardio_review_fixes.sql`, PR #174).** Seven functions
  replaced with `create or replace`, each pinned as its latest earlier definition plus the intended hunks by
  `deload_cardio_review_test.ts`: `deload_rules` (+`declined_cooldown_days` 14), `deload_signals`,
  `cardio_rules`, `cardio_week`, `training_guidance`, `next_session_targets`, `respond_to_coach_proposal_v1`.
  (H1) While a deload week is the active plan, a B3 target never steps up: `add_load` becomes `hold`, reason
  `deload`, at the last working load (the app prefills from the target before the plan's `start_load_kg`).
  (H2) Deload sessions are `adjusted` evidence (see above). (M1) A pending deload is withheld on a
  safety-route day (no `proposal_id`, `not_due`, `suppressed_by` `safety_route`) and approving one on such
  a day is refused with 55000. (M2) A declined deload proposal, or one that ran out unanswered, suppresses
  new suggestions for 14 days (`suppressed_by` `declined_recently`; a proposal replaced by a newer one does
  not count, nor does one that expired for another reason such as the plan moving on: the audit reason
  decides, and a timeout found by an approval attempt, reason `expired`, still counts; a proposal asked for
  through Coach and declined counts the same). `last_ended_on` is now the day the block-ended audit event was
  written (never later than the block's own last day), so a deload ended early keeps one end date and the
  28 days count from it (before, it moved forward every day). (L1) `vigorous_allowed` is
  false when today's check-in says not available to train. (L2) It also needs a screening row: no row is not
  cleared for hard cardio (`current_screening_outcome` itself is unchanged, no row still reads cleared
  elsewhere). (L3) Five more cardio names (wheelchair walk and run paces, cross-country skiing, paddle
  sports, social dance); a denied Apple Health workout permission reads as 0 minutes, not as missing.
  (L4) A pending proposal built on a plan version that is no longer current is stale, not pending. (L6) The
  Coach tool text now says a deload is always one week; the rationale says loads stay at the current working
  weights, or, when a B3 target had stepped down, that loads don't go up and the small step down is kept. (M3, not done) `training_guidance` still computes
  `next_session_targets` twice (through the day adjustment and the deload signals) and the screening
  outcome three times; passing them in would change several signatures. Run EXPLAIN ANALYZE on
  `get_training_guidance_for_v1` before the Coach reads it every turn.
- **Not built.** The `readiness` contributor (ai-gateway); eval cases. The contract requests 8 in the
  program doc says what it needs. (The `training-proposals` function, the Train card and the Cardio row
  are built: see "B5-3/B5-4 app and function" below.)
- **In-house numbers needing a coach's review before an external beta:** the half, the cap of 7, the
  thresholds (two lifts, four of seven days, 75%, 28 days, three of four weeks), the stretch-goal mapping,
  the two hard sessions, the 180-minute cap and the five-of-seven-days rule.
- **Tests that fail without each rule.** pgTAP `deloads_test.sql`, `cardio_dosing_test.sql`; Deno
  `deload_cardio_test.ts` and the deload tests in `coach_proposals/build_test.ts`.

**B5-3/B5-4 app and function (review; branch `claude/train-deload-cardio-ui`).**
- **`training-proposals` (O7).** `supabase/functions/training-proposals/` (JWT; in `config.toml`,
  `deploy.yml`, `hotfix.yml`). Body `{schema_version "1.0", kind "deload", local_date}` and nothing else (a
  `user_id` key makes it 422). The user is `auth.uid()`; the guidance is read through the athlete's own
  `get_my_training_guidance_v1` with the server day the app sends (22023 -> 422 `wrong_date`) and parsed with the
  strict `_shared/training/guidance/payload.ts`. `pending` returns that proposal (`created: false`, nothing
  stored: idempotent); `suggested` stores a pending proposal through `proposeSuggestedDeload`
  (`_shared/coach_proposals/service.ts`) = `buildSuggestedDeload` (`training.ts`, the same `deloadWeek()` builder
  as Coach, with the rules' reason sentences and a `DELOAD_SIGNALS` evidence line instead of an athlete's
  words) + `persist_coach_proposal_v1`; any other status is 409 `not_suggested`; a builder refusal is 409 with its
  code and plain `reason`; an unreadable guidance or a failed store is 503 without detail. No model call, nothing
  applied. Two quick taps could store two proposals; the second replaces the first (an expired-by-replacement
  proposal does not count as a decline) and the app disables the button while one is on its way.
- **App.** `lib/features/train/guidance/`: `training_guidance.dart` (tolerant parser: a later 1.x reads; an
  unknown deload status makes `deload` null, unknown reasons are dropped, a suggestion left with no sayable
  reason, a proposal status with no id, and a suggestion or open proposal on any `safety_route` day all hide the
  card; `cardio_week` needs `done_min` present, null stays null and is never shown as 0), the repository
  (`get_my_training_guidance_v1` + `training-proposals`), `TrainingGuidanceController` (the B4-2 server-day
  pattern: Train passes the hub's `local_today` after each hub load, the shell's `_serverToday` is the fallback
  and the retry on 22023), `guidance_copy.dart` (all the words), `deload_card.dart`, `cardio_week_sheet.dart`.
  The card is placed under the readiness card. **See what changes** prepares the proposal when the status is
  `suggested` (opening it applies nothing), then opens the existing `CoachProposalLoader` in a sheet with
  `origin: tracend` ("Suggested by Tracend", no AI line) and `allowChange: false` (Change it sends a Coach chat
  message, so it is not offered here). Approve/Not now/Undo are the existing `respond_to_coach_proposal_v1` /
  `undo_coach_proposal_v1`; approve and undo announce `PlanChanges`, which reloads the hub and the guidance. The
  sheet closing reloads the guidance.
- **Review of PR #178 (guidance 1.2, migration `20261024060425_deload_origin_and_undo_cooldown.sql`).**
  (H1) The card no longer calls a Coach-made week "Suggested by Tracend": guidance 1.2 adds `deload.proposal_origin`
  (`tracend` when the proposal's evidence has `DELOAD_SIGNALS`, which only `buildSuggestedDeload` adds; else
  `coach`; null with no proposal) and `deload.ends_on` (a running week's last day). A pending or running Coach week
  shows "Proposed by Coach", no rule reasons and no "No AI" line; a missing or unknown origin reads as Coach's. The
  proposal sheet takes its origin from the proposal's own evidence (`CoachProposal.suggestedByRules`), so the two
  always agree. The running card says "until <day>". (M1) The rules' deload is stored through `public.persist_suggested_deload_v1` (service role only,
  same arguments as `persist_coach_proposal_v1`). Under the store lock it refuses with SQLSTATE `TP001` when a
  pending, unexpired 3.0 proposal with a `training` payload that is not a deload is built on the active plan
  version, because storing a training proposal expires every open one; one built on an older plan, one that ran
  out, and an unanswered deload do not block. `training-proposals` maps `TP001` to 409 `other_proposal_pending`
  and keeps no read of its own, so a Coach proposal stored between a check and the store cannot be expired
  unseen. The card says "You have a change waiting in Coach. Answer it first." (M2) An undone deload holds new suggestions back 14 days from the day it was undone
  (`declined_recently`); it is still not the last deload. (L1) The handler answers an unexpected throw with 503 and
  reports only the fixed name `training_proposals_unexpected` to Sentry. (L2) `persist_coach_proposal_v1` takes
  `pg_advisory_xact_lock(hashtextextended('tracend.coach_proposal_store:' || p_user_id::text, 0))` (the repo's
  lock naming) before it replaces an open proposal; the redefinition is the latest earlier definition plus that
  hunk, found by scanning earlier migrations and pinned by `deload_origin_test.ts`. (L3) The function returns refusal codes only and the
  app words them (`deloadRefusalLine`); `proposal_notices.dart` words stale and refused answers for a card the rules
  made (no "Coach", no first person, "Pull down on Train"), and a deload approved on a route day says a lighter week
  can't start on a day with a referral. (L4) "stalled or slipped"; "Today's readiness reads green, which needs
  today's check-in." (L5) `prepareDeload` asks `_today()` so a day that rolled over is refreshed first. (L6)
  `hadUnreadReasons` is gone. (L7) The cardio row is hidden while a past week is on screen. The TS parser
  (`guidance/payload.ts`) reads 1.2 and refuses an origin on a status with no proposal or an end date off a running
  week. pgTAP: `deload_origin_test.sql`; `deloads_test.sql` and `cardio_dosing_test.sql` carry the new keys and the
  undone-deload cool-down.
- **Decisions.** (a) A `running` status shows a quiet card "A lighter week is on" with **Details and undo**: the
  brief listed only suggested and pending, but a rules-originated week has no chat message to carry its Undo.
  (b) The Cardio row sits in "This week" after Training load. It shows "85 of 150 min" or "Not enough Apple Health
  data", and is absent on a safety-route or `see_professional` day (withheld) and for a cardio week the app cannot
  read. (c) Easy-only reasons: the payload gives only `vigorous_allowed`, so the sheet lists the four conditions
  that open hard cardio instead of guessing which one failed. (d) The sheet always carries the note that a denied
  Apple Health workout permission can read as 0 minutes. (e) The easy heart-rate line in beats per minute is still
  not shown (needs the C3 profile on Train); the sheet gives the talk test and "about 60% of heart rate reserve" as a
  guide. (f) The card shows without a selected-day check: a lighter week belongs to the week.
- **Tests.** Deno `training-proposals/handler_test.ts` and the `proposeSuggestedDeload` test in
  `coach_proposals/service_test.ts`; Flutter `contract/training_guidance_contract_test.dart` (the three
  fixtures, later-1.x tolerance, the parameters), `training_guidance_controller_test.dart`,
  `train_guidance_test.dart` (suggested, pending, running, declined_recently and the other suppressions, safety
  route, unknown status and reason, failures, cardio met/partial/zero/null/easy-only/hard/unreadable, copy lint).

## Next agent starts here

B4-2 (the app side of the readiness adjustment) and B5-2 (the pain check in the app; builds on B5-1's RPCs
and B4-1's) are live; B5-3 and B5-4 (deloads, cardio dosing) are in review with their app card, cardio row and the
`training-proposals` function; the Coach contributor is what is left of them. B6's server wiring is done (see the B6
section). The briefs are in the program doc.
