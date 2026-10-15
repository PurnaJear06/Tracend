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
  evidence, most pressing first, and returns the first one the decision contract accepts under the
  request's policy outcome; the contract stays the only copy of the policy rules. Where a change is
  not allowed, the plan is kept and the evidence still reported (elevated load keeps its
  `elevated_load` flag; recovery within baseline without a check-in asks for the check-in).
  Escalation cites its evidence only when permitted.
- **Rules plan ranks exercises.** `buildRulesPlan` took the first catalog exercise per slot, and
  catalog.ts lists bodyweight first (production reads the catalog in slug order, which put band rows
  and assisted pull-ups first instead), so a full-gym lifter got bodyweight squats and push-ups.
  `rankExercises` (`_shared/onboarding/rules_plan.ts`) orders the athlete's exercises: loaded
  before bodyweight (a bench alone counts as bodyweight), compound before isolation, equipment by
  experience (intermediate: barbell, dumbbells, pull-up bar, machines, cables, kettlebells, bands;
  beginner: dumbbells, machines, cables, barbell, kettlebells, bands, pull-up bar), standard form
  before variation before regression, then slug. A slot takes a loaded exercise from any of its
  patterns before a bodyweight one; weekly variety never drops to bodyweight or to a regression.
  Movements to avoid, level filtering and every volume, time and set limit are unchanged.
- **Catalog ranking field.** `CatalogExercise.role` (`variation` or `regression`, absent for the
  standard form) is set on seven entries in `catalog.ts`. The database catalog has no such column,
  so the rules plan reads it from catalog.ts by slug; no migration.
- **Tests.** `mock_coach_model_provider_test.ts`: every policy outcome x all 128 subsets of seven
  evidence codes x missing data x decision kind (2,560 cases) passes `parseCoachDecision`, plus the
  per-policy expected actions. `rules_plan_test.ts`: golden plans for an experienced lifter in a
  full gym, a beginner in a full gym, dumbbells only (both experience levels) and bodyweight only;
  the database catalog (slug order, no roles) builds identical plans; with a loaded form free for
  the session no plan uses a bodyweight form. `plan_contract_test.ts` now expects the dumbbells-only
  plan to open with a goblet squat (it asserted the old bodyweight squat). Deno suite: 403 passed,
  0 failed, 8 ignored.

## Next agent starts here

Take the first `todo` chunk of this stream from the program board whose dependencies are merged.
