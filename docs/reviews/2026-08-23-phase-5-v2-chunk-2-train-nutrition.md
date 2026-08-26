# Review: Phase 5 v2 Chunk 2 — Train + Nutrition Precision Pro rebuild — 2026-08-23

Scope: branch `feature/feature-engine-phase-5-v2`, commits `d1db7b1` ("feat(ui): Phase 5 v2
Chunk 2 — Train + Nutrition Precision Pro rebuild") + `c2b5422` (one-line tracker hash
update). 18 files changed, +3203 / −1367: 3 new shared widgets (`IntensityBar`,
`DatePillStrip`, `TargetsGrid`), `NutritionInsightCard` + extracted nutrition sheets, 3
extracted train widget files (hero/action cards/prescription cards), train_screen.dart
932 → 499 lines, nutrition_screen.dart 1039 → 589 lines, `TrainingLoadGauge` restyle,
`TrainingSessionSummary.workoutId` added, new `test/chunk2_widgets_test.dart` + 2 updated
test files, plan tracker + PROGRESS_CONTEXT + handoff/frontend updates. Reviewed against
`.opencode/plans/phase-5-v2-precision-pro.md` §5/§10 and AGENTS.md.

Verdict: PASS WITH FINDINGS

No blocking findings. Data-binding honesty is solid: IntensityBar never touches
`session_effort`, TargetsGrid never invents values, NutritionInsightCard hides on null
decision, and every chevron is either wired or absent. Gates green (analyze clean, format
clean, 213/213 tests). One MAJOR: the production shell never injects the real coach
repository into Train/Nutrition, so the chunk's two coach-insight surfaces can never show
real data in the shipped app.

## Findings

1. [MAJOR] lib/features/shell/app_shell.dart:91-100 — `TrainScreen` and `NutritionScreen`
   are constructed without the shell's `_coach` repository, so both fall back to their
   default `const FixtureCoachRepository()` (train_screen.dart:20, nutrition_screen.dart:18),
   whose `loadLatest()` always returns null (coach_repository.dart:391). Consequence in the
   production app: the Train hero "COACH INSIGHT" line (workout_hero.dart:118) and the
   Nutrition `NutritionInsightCard` (nutrition_screen.dart:313-323) are permanently hidden,
   even though real `coach_decisions` data exists and `SupabaseCoachRepository` is already
   built in the shell (app_shell.dart:56-58) and passed to TodayScreen (app_shell.dart:85).
   The chunk's headline Nutrition CoachInsightCard (a master-plan Phase-5 item) is therefore
   orphaned from real data at the composition root — owner ruling §1.4 requires every
   implemented repo feature to "actually work". Behavior stays honest (hidden, never faked),
   but the feature is dead in production. Suggested fix: pass `coach: _coach` to both screens
   in app_shell, plus a smoke test asserting the insight renders when a decision exists.

2. [MINOR] lib/features/nutrition/nutrition_screen.dart:1-589 — Screen is 589 lines after
   extraction, over the plan §2.8/§5 target of < 500 lines/screen (train_screen.dart made it
   at 499). `_ScheduledMealRow` (:454) and `_MealCard` (:522) remain inline. Suggested fix:
   move both into `lib/features/nutrition/widgets/` alongside the sheets.

3. [MINOR] test/chunk2_widgets_test.dart — State tables for the three shared widgets are
   covered (full / cold_start / null), but the chunk's new screen-level logic has no tests:
   (a) `_loadRecordedRpe` (train_screen.dart:237-260) — the recorded-RPE honesty core
   (per-`order` averaging, 1–10 range filter, missing-set tolerance) is untested; (b)
   `RecentSessionsCard` openable vs display-only branching (prescription_cards.dart:364-417:
   chevron + navigation only when `workoutId` resolves) — the chunk's key anti-dead-affordance
   behavior; (c) WorkoutHero `coachInsight` null → hidden vs present → rendered
   (workout_hero.dart:118); (d) NutritionInsightCard hiding is caller-side
   (nutrition_screen.dart:317) and untested — the widget test only covers the full state.
   Plan §10.6: tests written from code. Suggested fix: add these four cases.

4. [MINOR] test/contract/fixtures/training_hub_v1_4.json:62-73 — This chunk starts consuming
   `recent_sessions[].workout_id` (workout_repository.dart:302), served by hub v1.4
   (migration 20260726170000:186), but the v1.4 contract fixture's `recent_sessions` entries
   omit `workout_id` and the contract test never asserts it
   (training_hub_contract_test.dart:80-96). The omission predates this chunk (the field has
   existed server-side since 20260718150000), but the fixture no longer documents the shape
   the app now relies on, and the display-only fallback path is the only thing exercising the
   null case. Suggested fix: add `workout_id` to the v1.4 fixture rows and assert
   `row['workout_id']` is absent-or-String in the contract test.

5. [NIT] lib/shared/widgets/intensity_bar.dart:99-102 — The legend always renders the
   "Recorded" dot even when no entry has a `recordedRpe` (e.g. any non-completed day), so the
   legend advertises an encoding that isn't present on screen. Not fabrication, but mildly
   misleading. Suggested fix: show the Recorded legend item only when at least one marker
   exists.

6. [NIT] lib/shared/widgets/targets_grid.dart:38 — With `summary == null` AND `targets ==
   null` the card prints "0 kcal logged". In nutrition_screen this state occurs during the
   initial load and on load error (an error banner shows alongside), where the pre-chunk UI
   printed "—" (`_number(null)`). Zero is a real logged-count only after a successful empty
   load. Suggested fix: render "—" (or hide the card) while summary is null.

7. [NIT] lib/features/train/widgets/workout_hero.dart:11 — Doc comment says the insight line
   comes "from the daily brief decision", but it binds `CoachDecision.trainingSummary` via
   `coach.loadLatest()` (train_screen.dart:417-424). Suggested fix: correct the comment.

8. [NIT] lib/features/nutrition/nutrition_screen.dart:313-323 ·
   lib/features/train/train_screen.dart:417-424 — `loadLatest()` returns the most recent
   decision regardless of the selected date, so when browsing past days/weeks the insight
   card/line shows today's decision under a past day's log without any date label. Consistent
   with Chunk 1's coach-perspective precedent, but consider scoping by `decision.localDate`
   or labeling the decision date in a later chunk.

## Verification of the requested focus items

1. **Data binding honesty — CONFIRMED.** IntensityBar bars are exclusively
   `planned_exercises.target_rpe` (intensity_bar.dart:141-146, clamped 0..1); the marker is
   exclusively `recordedRpe` (intensity_bar.dart:147-149), which train_screen computes from
   `get_my_workout_session` per-set `rpe` averaged per exercise `order`
   (train_screen.dart:237-260; RPC shape verified at migration 20260711190000:122-132).
   `session_effort` appears nowhere in `lib/` except the pre-existing hardcoded save value
   (workout_repository.dart:548) and the doc comment warning against using it. Marker only
   renders on completed days (train_screen.dart:436-464) and only for movements with logged
   RPE in 1..10. Cold start: empty entries → "Log a session to see intensity", no bars
   (intensity_bar.dart:49-66; tested). TargetsGrid binds only `NutritionTargets` /
   `NutritionSummary` (targets_grid.dart:20-22); no targets → consumed-only + "No active
   nutrition target is set.", no bars (tested); null summary → zero-consumed cold start
   (tested; see finding #6 for the error-state nuance). Fractions clamped, protein remaining
   clamped ≥0 (targets_grid.dart:126-135). NutritionInsightCard renders only
   `nutritionAction`/`nutritionSummary`/`confidence` (nutrition_insight_card.dart:55-79);
   caller returns `SizedBox.shrink()` when decision is null (nutrition_screen.dart:317) —
   hidden, never faked (but see finding #1: in production the fixture default guarantees
   null).

2. **Dead affordances — CONFIRMED none introduced.** DatePillStrip chevrons render only when
   their callback is provided (date_pill_strip.dart:70,107; tested both ways); Train supplies
   offset-bounded chevrons (`_weekOffset` clamped −3..0, train_screen.dart:278-291,346-349)
   and Nutrition hides "next" in the current week (nutrition_screen.dart:292-294) — the
   remaining "previous" chevron always performs real navigation. Recent-session rows: chevron
   + InkWell exist only when `workoutId` resolves against `hub.workouts`
   (prescription_cards.dart:364,406-417); otherwise the row is plain content with no tap
   target and no chevron — truly display-only, documented at prescription_cards.dart:303-305.
   `_ProgressionRow` converted to non-interactive text, choice documented
   (prescription_cards.dart:211-215 + plan tracker "Chunk 2 decisions"). Disabled future-day
   pills in Nutrition set `onTap: null` (date_pill_strip.dart:185; tested). No
   `onPressed: () {}` anywhere in the diff.

3. **BackdropFilter budget — CONFIRMED, zero new sites.** Grep finds exactly two live
   BackdropFilter sites app-wide, both pre-existing: app_shell.dart:172 (floating tab bar)
   and tracend_glass.dart:46 (used once, today_hero.dart:214 confidence pill). All new Chunk
   2 surfaces use `PremiumGradientCard` (solid gradient, zero blur — its test asserts no
   BackdropFilter in subtree). TargetsGrid cells are solid `surfaceRaised` containers, no
   nested glass (targets_grid.dart:174-181, 283-290).

4. **Test coverage — PARTIAL** (finding #3). chunk2_widgets_test.dart covers the shared-widget
   state tables: DatePillStrip (seven pills, normalized-date tap, chevron presence/absence,
   disabled pill, `mondayOf`), IntensityBar (cold start, planned bars, recorded marker text,
   strain show/hide), TargetsGrid (full with remaining protein + percent, no-targets, cold
   start), NutritionInsightCard (full render incl. confidence). Updated tests remain
   meaningful: phase_6_nutrition_test.dart now navigates via date-pill keys with a
   previous-week fallback and asserts the new subtitle copy; production_rebuild_flutter_test
   replaces the deleted ChoiceChip strip with date-pill taps and scrolls to the new
   PRESCRIPTION card. Both exercise real flows (verified green). Gaps: the four screen-level
   behaviors listed in finding #3.

5. **Screen size — PARTIAL.** train_screen.dart 499 lines (< 500 ✓). nutrition_screen.dart
   589 lines (> 500 — finding #2).

6. **AGENTS.md violations — NONE found.** No TODO/FIXME/placeholders in new code (grep
   clean); no secrets or prod URLs introduced; no direct `flutter`/`dart`/`deno`/`supabase`
   invocations in changed scripts/docs (gates run via wrappers); no migrations (plan: "DB
   changes: NONE" — verified; `workout_id` already exists in hub v1.4, migration
   20260726170000:186, so no schema change was needed); no RPC shape changes (contract
   fixtures untouched apart from finding #4's staleness); doc comments are documentation, not
   commented-out alternatives. PROGRESS_CONTEXT.md and handoff/frontend.md updated in-commit;
   UX_FLOWS nav update deferred to Chunk 5 per plan §8.4 (consistent with Chunk 1 precedent).

## Checklist results

- Migrations: n/a (none in diff; forward-only rule respected — no DB changes)
- RPCs consumed by Flutter (`schema_version`): n/a (no RPC changes; newly consumed
  `recent_sessions[].workout_id` verified present in `get_my_training_hub` v1.4, migration
  20260726170000:186; `exercises[].order`/`sets[].rpe` verified in `get_my_workout_session`,
  migration 20260711190000:122-132)
- Contract fixtures: finding #4 (v1.4 fixture lacks the now-consumed `workout_id`)
- RLS: n/a (no new tables)
- Secrets: ok (none introduced; `session_effort = 8` remains a save-time value only, never displayed)
- Wrappers: ok (gates via `./scripts/flutter.sh`; no direct tool invocations introduced)
- MVP boundaries: ok (iOS-only UI; no excluded features or infra)
- No placeholders: ok (no TODO/dead code/commented-out alternatives)
- Docs: ok (dashboard + handoff + plan tracker updated; UX_FLOWS deferred to Chunk 5 per plan)
- Tests: finding #3 (screen-level gaps); otherwise ok — 13 new widget tests, 2 updated
  suites, 213/213 green, safety fixtures untouched

## Gate results

- `./scripts/flutter.sh analyze` → No issues found! (ran in 6.2s)
- `./scripts/flutter.sh test` → `+213: All tests passed!` (0 failures)
- `./scripts/flutter.sh format --output=none --set-exit-if-changed lib test` → 98 files, 0 changed
- `./scripts/deno.sh lint/test supabase/functions` → NOT RUN (no supabase/functions changes
  in these commits; pure Flutter UI chunk)
