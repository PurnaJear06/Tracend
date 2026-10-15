# Training Engine Handoff

**As of:** 2026-10-15

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

Deterministic, coach-grade training rules: templates, progression from the sets actually logged, deloads, joint-friendly modifications, a screening gate and a same-day readiness adjustment.

## Chunks

B0 (Phase 1); B1 (Phase 2); B2, B3, B6 (Phase 3); B4, B5 (Phase 4)

## State

No chunk of this stream has merged yet.

**B0 (in review, branch `claude/b0-decision-plan-fixes`; Edge Functions only, no SQL or app change).**

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

## Next agent starts here

Take the first `todo` chunk of this stream from the program board whose dependencies are merged.
