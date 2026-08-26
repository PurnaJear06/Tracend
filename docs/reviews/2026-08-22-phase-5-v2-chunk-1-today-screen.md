# Review: Phase 5 v2 Chunk 1 — Today screen Precision Pro rebuild — 2026-08-22

Scope: branch `feature/feature-engine-phase-5-v2`, commit `1bcc0d8` ("feat(ui): Phase 5 v2
Chunk 1 — Today screen Precision Pro rebuild"), diff `6e96e08..1bcc0d8`. 19 files changed,
+2588 / −761: TrajectoryLens rewrite (87 → 371 lines), today_screen.dart reduced 971 → 417
lines via 8 extracted widgets (`lib/features/today/widgets/`), app_shell tab wiring,
recovery_ring/sleep_architecture_card token restyle, 2 new test files + 3 test updates, plan
tracker update. Reviewed against `.opencode/plans/phase-5-v2-precision-pro.md` §4 (Chunk 1),
`docs/DESIGN_SYSTEM.md`, and AGENTS.md.

Verdict: PASS WITH FINDINGS

No blocking findings. All anti-failure rules (§10) verified: every displayed number traces to
a real repository/RPC field, no fabricated metrics, no dead affordances, missing data lowers
confidence instead of being invented. Gates green (analyze clean, format clean, 200/200 tests).

## Findings

1. [MINOR] docs/PROGRESS_CONTEXT.md:8 · docs/handoff/frontend.md:311 — Dashboard and frontend
   handoff were not updated for Chunk 1. PROGRESS_CONTEXT still says "Chunk 0 complete
   (`c55d281`)" and "175 Flutter tests pass"; handoff/frontend.md still ends "Next: Chunk 1 —
   Today screen". AGENTS.md required flow: "After work, update handoff + this dashboard"
   (Chunk 0 did update both). Suggested fix: update both to Chunk 1 complete / 200 tests.

2. [MINOR] docs/DESIGN_SYSTEM.md:46-55 · pubspec.yaml:74 — The coaching-horizon hero backdrop
   (`_TodayHeroBackdrop` + `assets/visuals/tracend-coaching-horizon-v1.jpg`) was deleted from
   Today in this commit, but DESIGN_SYSTEM.md §2 still defines "the coaching horizon" as the
   signature element (and §3.1:87 references it in the gradient rule), and the now-unreferenced
   20 MB-class asset is still bundled in pubspec.yaml (grep confirms zero `lib/` references).
   The removal matches the plan §4.3 Stitch hero (flat, no backdrop), but the authority doc was
   not amended in the same change (AGENTS.md rule) and the dead asset ships. Suggested fix:
   amend DESIGN_SYSTEM.md §2/§3.1 and drop the asset line, or record the deferral in the plan.

3. [MINOR] lib/features/today/widgets/coach_perspective_card.dart:67 — `Icons.memory_outlined`
   (Material family) while every other Today widget icon uses CupertinoIcons. DESIGN_SYSTEM.md
   §10 lists "mixed icon families" as an anti-pattern. Suggested fix: swap to a Cupertino
   equivalent (e.g. `CupertinoIcons.gauge`, `CupertinoIcons.cpu`).

4. [MINOR] lib/features/today/widgets/metabolic_target_card.dart:242 — `_LogButton`
   constraints `minWidth: 44, minHeight: 32`: height is below the 44×44pt minimum touch target
   (DESIGN_SYSTEM.md §3.3; plan §8.2). Suggested fix: raise minHeight to 44 or pad the hit area.

5. [MINOR] lib/features/today/widgets/readiness_strip.dart:310 — The STRAIN chip forces
   `positive = raw ? true : z >= 0`, so any daily-strain magnitude (including a very hard day,
   e.g. the historical ≈300 outlier) renders in `stateStable` teal. Color then misrepresents a
   raw load value as "good". Suggested fix: use a neutral accent (textSecondary/actionPrimary)
   for raw values, or map strain to a real band.

6. [NIT] lib/features/today/widgets/coach_perspective_card.dart:44-80 — Plan §4.1 binding table
   lists `CoachDecision.finalDecision/reason/confidence` for the coach insight card; the card
   renders finalDecision + summary + confidence but omits `decision.reason`. Nothing fabricated
   (reason is shown in the hero via `brief.reason` when the decision drives the headline), but
   the card deviates from its own binding table. Suggested fix: render reason or amend the
   table. (`modelProvider` is correctly omitted — it does not exist on `CoachDecision`.)

7. [NIT] lib/features/today/recovery_ring.dart:194 — Pre-existing hardcoded
   `const Color(0xFFFFFFFF)` (low-confidence dot) remains; this file was touched by the commit
   (amber → `accentAmber`), so the last raw hex in `lib/features/today/` could have been
   tokenized too (DESIGN_SYSTEM.md §3: "Raw color values must not appear in feature widgets").
   `Colors.white.withValues(alpha: 0.05)` overlays in check_in_prompt_bar.dart:39 /
   metabolic_target_card.dart:245 match the Chunk 0 precedent for framework constants — fine.

8. [NIT] lib/shared/widgets/trajectory_lens.dart:127-128 — Lens labels use fontSize 9 /
   letterSpacing 1.6; plan §4.2 specifies "11px caps (label-caps scale) … 0.08em tracking".
   Likely a deliberate compact-lens adjustment, but it deviates from the written spec without a
   note. Suggested fix: match spec or document the exception in the plan.

9. [NIT] lib/features/today/today_screen.dart:355-361 — The `if (brief.checkIn == null) … else …`
   branches are identical except `completed: true`; collapse to
   `CheckInPromptBar(onCheckIn: onCheckIn, completed: brief.checkIn != null)`.

10. [NIT] lib/shared/widgets/trajectory_lens.dart:308 — `shouldRepaint` compares `units` by list
    identity, but `_unitPoints()` allocates a fresh list on every build, so the painter repaints
    on any parent rebuild even when values are unchanged. Cheap (≤4 points) and correct; a
    value-equality check would avoid redundant repaints after the draw-on completes.

## Verification of the requested focus items

1. **TrajectoryLens — CONFIRMED.** NOW resolves only to real fields:
   today_hero.dart:36-40 `recovery?.toDouble() ?? (points.isEmpty ? null : points.last.value)`;
   when no score exists there is no NOW point at all. Chip-rail fallback when <2 points
   (trajectory_lens.dart:104 `if (widget.points.length < 2) return _ChipRail(...)`; tests cover
   0- and 1-point cases). Bezier CustomPainter with `PathMetric` draw-on
   (trajectory_lens.dart:262-271 `computeMetrics().single` + `extractPath(0, length * progress)`),
   1.5s easeOutCubic via `AnimatedBuilder` — no setState-per-frame (the v1 audit bug). The v1
   `bezierValues`-never-consumed bug is fixed: `points` drives both painter and NOW overlay.
   reduceMotion → no controller created, static full path (`progress: 1`), tested. Semantics
   label enumerates real values (tested). NOW-dot pulse is the single sanctioned idle loop via
   `MicroMotionPulse`, itself Reduce-Motion-gated.

2. **TodayHero — CONFIRMED.** Confidence pill maps `computed.dataConfidence`
   (today_hero.dart:204-211: high/medium/low → labeled pills, `_` → "Building baseline";
   cold_start falls into `_`), rendered in TracendGlass (sanctioned chrome site). 42pt decision
   headline (today_hero.dart:112-117: fontSize 42, height 1.05, letterSpacing −1.26 = −0.03em,
   w600, displaySmall → Spline Sans). Start session disabled, not no-op
   (today_screen.dart:163 `brief.workout != null ? _openWorkout : null` → FilledButton
   `onPressed: null`; tested). View analytics hidden when unwired (today_hero.dart:145; tested).
   Sync label from `decision['created_at']` → `health['local_date']` → hidden (matches §4.1).

3. **ReadinessStrip — CONFIRMED** (finding #5 aside). Mono values with tabular figures
   (readiness_strip.dart:243-249), real z-chips from `recoveryBreakdown.hrvZ/rhrZ/sleepZ`
   (:94-96) and raw `dailyStrain` (:151), honest cold-start fallbacks '--' + "Check in"/
   "Updated", "Rest day"/"Planned", "Up to date"/"Next meal" (tested). Z-sign coloring is
   semantically correct server-side (RHR/resp z are sign-inverted in `compute_daily_metrics`,
   so positive z = good across all drivers). `onOpen` detail sheet preserved.

4. **SessionPlanCard — CONFIRMED.** Counts folded from the real `exercises` array
   (session_plan_card.dart:47-53: length + `set_count` fold) and `estimated_minutes` — the exact
   keys `get_my_training_hub.today_workout` returns (migration 20260726170000:175-184). Null
   workout → "No session planned" honest empty state, no fabricated counts (tested). Chevron
   opens WorkoutDetailScreen (real navigation, not dead).

5. **MetabolicTargetCard — CONFIRMED** (finding #4 aside). Consumed reads
   `brief.nutrition['calories'/'protein_g']` — exact keys of `get_my_daily_nutrition`
   (migration 20260702110000:180-182). Targets from `nutrition.loadTargets()`
   (`nutrition_target_sets` active row; null when none). No targets → consumed-only + "No active
   nutrition target is set.", no fabricated bar (tested). LOG hidden when `onLog` null (tested).
   Fractions clamped 0..1; protein remaining clamped ≥0.

6. **CoachPerspectiveCard — CONFIRMED** (findings #3, #6 aside). T/N toggle switches real
   `decision.trainingSummary` ↔ `nutritionSummary` (coach_perspective_card.dart:34-36; toggle
   tested both ways). Confidence rendered verbatim from `decision.confidence` (:73), never
   hardcoded. No model-version string anywhere (Stitch's fake "v2.4" omitted). No decision →
   caller shows honest fallback card (today_screen.dart:381-387).

7. **CheckInPromptBar — CONFIRMED.** Always present (today_screen.dart:355-361 renders it in
   both check-in states); copy reflects state ("Update morning status?"/CHECK-IN vs "Morning
   status recorded"/EDIT; both tested); opens the real `showCheckInSheet` and reloads the brief.

8. **app_shell wiring — CONFIRMED.** `_selectTab` extracted; `onOpenProgress: () => _selectTab(4)`
   and `onOpenNutrition: () => _selectTab(3)` (app_shell.dart:88-89) match the destinations order
   (Today 0, Train 1, Coach 2, Nutrition 3, Progress 4). Same haptic/guard behavior as before.

9. **Hardcoded hex in today widgets — CONFIRMED clean** except pre-existing
   recovery_ring.dart:194 (finding #7). All new widgets resolve colors via `context.tracendColors`;
   only framework constants (`Colors.transparent`, alpha-white overlays) otherwise.

10. **Tests — CONFIRMED.** State tables per widget in today_widgets_test.dart (trajectoryPoints
    NOW resolution incl. fallback + empty; hero full/cold-start/disabled/unwired; readiness
    full/cold; session full/null; metabolic full/no-targets/unwired; coach default/toggle;
    check-in pending/completed; divider). trajectory_lens_test.dart covers bezier render, 0/1-point
    chip-rail fallback, Reduce Motion static, semantics. 320/375/390/430pt light+dark smoke plus
    2× text scale + Reduce Motion smoke all pass (frontend_smoke_test.dart unchanged, green).
    Light-theme `accentAmber`/`accentNow` ≥3:1 contrast assertion added (theme_test.dart:49-53) —
    closes the Chunk 0 carry-forward note. Full suite: `+200: All tests passed!`.

11. **Screen size — CONFIRMED.** today_screen.dart is 417 lines (< 500 target).

Additional checks: no migrations, no RPC/Edge shape changes (contract fixtures untouched —
correct), no secrets in `lib/`, no TODO/FIXME/dead code in new work, no `onPressed: () {}`
anywhere in the touched files, wrappers used for all gates. The uncommitted working-tree edit
to the plan tracker (filling in commit hash `1bcc0d8`) is expected post-commit bookkeeping.

## Checklist results

- Migrations: n/a (no migration files in diff)
- RPCs consumed by Flutter (`schema_version`): n/a (no RPC changes; consumed fields verified
  against `get_my_daily_brief` v1.1, `get_my_training_hub` v1.4, `get_my_daily_nutrition`)
- Contract fixtures: n/a (no response-shape changes; fixtures untouched)
- RLS: n/a (no new tables)
- Secrets: ok (no service-role/AI keys or prod URLs introduced in lib/)
- Wrappers: ok (gates run via `./scripts/flutter.sh`; no direct tool invocations introduced)
- MVP boundaries: ok (iOS-only UI; no excluded features or infra)
- No placeholders: finding #2 (dead coaching-horizon asset still bundled); otherwise ok
- Docs: findings #1, #2 (dashboard/handoff stale; DESIGN_SYSTEM horizon section + UX_FLOWS §5
  Today diagram now describe the pre-rebuild screen — plan §8.4 defers UX_FLOWS to Chunk 5)
- Tests: ok (25 new tests across 2 files; state tables + fallbacks + a11y smoke; 200/200 green;
  safety fixtures untouched)

## Gate results

- `./scripts/flutter.sh analyze` → No issues found (ran in 6.0s)
- `./scripts/flutter.sh test` → `+200: All tests passed!` (0 failures)
- `./scripts/flutter.sh format --output=none --set-exit-if-changed lib test` → 89 files, 0 changed
- `./scripts/deno.sh lint/test supabase/functions` → NOT RUN (no supabase/functions changes in
  this commit; pure Flutter UI chunk)
