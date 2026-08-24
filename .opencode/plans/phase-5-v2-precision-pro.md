# Phase 5 v2 — "Precision Pro" Production UI — Master Plan

**Created:** 2026-08-22 (rewritten same day after master-plan cross-check)
**Status:** Chunk 4 complete — reviewed, follow-ups fixed (AI Usage + Shell + Account)
**Branch:** `feature/feature-engine-phase-5-v2` (from `93fa49e`) → merge into `feature/feature-engine`
**Backup:** tag `backup/pre-phase-5-v2` (local; push blocked by deploy-guard — user pushes or approves)
**Supersedes:** the 2026-08-18 Phase 5 attempt (reverted) and the earlier draft of this file
**Parent plan:** `.opencode/plans/feature-engine-and-ui-alignment.md` (2026-07-22) — this plan
executes its Phase 4/5 UI scope. Every component in that plan's P0–P2 list is now covered.
**DB changes:** NONE. Pure UI phase. All data already exists in RPCs/models (verified below).

## Progress Tracker

| Chunk | Scope | Status | Commit | Gate | Review |
| ----- | ----- | ------ | ------ | ---- | ------ |
| 0 | Docs + tokens + fonts + glass/motion widgets | ✅ Done 2026-08-22 | `c55d281` | analyze ✓ · format ✓ · 175 tests ✓ | PASS w/ findings — `docs/reviews/2026-08-22-phase-5-v2-chunk-0-precision-pro-foundation.md` |
| 1 | Today screen (hero + readouts + TrajectoryLens) | ✅ Done 2026-08-22 | `1bcc0d8` + `578f065` | analyze ✓ · format ✓ · 200 tests ✓ | PASS w/ findings — `docs/reviews/2026-08-22-phase-5-v2-chunk-1-today-screen.md` (all fixed in `578f065`) |
| 2 | Train + Nutrition (IntensityBar, DatePillStrip, TargetsGrid) | ✅ Done 2026-08-23 | `d1db7b1` + `0e82689` | analyze ✓ · format ✓ · 213 tests ✓ | PASS w/ findings — `docs/reviews/2026-08-23-phase-5-v2-chunk-2-train-nutrition.md` (all fixed in `0e82689`) |
| 3 | Progress + Coach (regression overlay, EvidenceAccordion) | ✅ Done 2026-08-24 | `672f28f` + `288d14a` | analyze ✓ · format ✓ · 262 tests ✓ · ios build ✓ | PASS w/ findings — `docs/reviews/2026-08-24-phase-5-v2-chunk-3-progress-coach.md` (all fixed in `288d14a`) |
| 4 | AI Usage + Shell + Account cleanup | ✅ Done 2026-08-24 | `82bf748` + `2afe1c8` | analyze ✓ · format ✓ · 274 tests ✓ · ios build ✓ | PASS w/ findings — `docs/reviews/2026-08-24-phase-5-v2-chunk-4-ai-usage-shell-account.md` (all fixed in `2afe1c8`) |
| 5 | Motion + A11y + copy audit + final gate + merge | ⬜ Pending | — | — | — |

Carry-forward notes from reviews:
- Chunk 0 review: assert light-theme `accentAmber`/`accentNow` contrast when those tokens are
  first wired (Chunks 1–3).
- Flutter 3.41.7 has no `MediaQuery.accessibilityFeaturesOf` — Reduce Motion gating uses
  `MediaQuery.disableAnimationsOf` everywhere (plan §2.7/§3.4 wording superseded by this).
- Chunk 2 decisions (2026-08-23):
  - `IntensityBar` recorded-RPE marker binds to per-set `rpe` from `get_my_workout_session`
    (averaged per exercise order), NOT the hardcoded `session_effort = 8` written on save.
    Marker only renders for completed days with logged set RPE.
  - `TrainingSessionSummary` gained nullable `workoutId` (hub `recent_sessions[].workout_id`,
    schema v1.4). Recent-session rows with a resolvable workout open `WorkoutDetailScreen`;
    rows without one are display-only (no dead chevron).
  - `_ProgressionRow` converted to display-only facts (no chevron/tap) — progression values
    are not navigation. Documented in `prescription_cards.dart`.
  - `DatePillStrip` replaces the old `_WeekdayStrip` (Train) and the chevron date nav
    (Nutrition). Chevrons render only when their callback is provided.
  - Nutrition `CoachInsightCard` = `NutritionInsightCard` binding
    `CoachDecision.nutritionAction`/`nutritionSummary`/`confidence`; hidden when no decision.
  - Train hero coach-insight line binds `CoachDecision.trainingSummary`; hidden when null.
- Chunk 2 review follow-ups (2026-08-24): coach repo injected into Train/Nutrition at the
  shell (finding 1); `_ScheduledMealRow`/`_MealCard` extracted to
  `lib/features/nutrition/widgets/meal_cards.dart` (nutrition_screen 589 → 453 lines,
  finding 2); four screen-level tests added (finding 3); v1.4 contract fixture gained
  `workout_id`/`effort`/`energy` + assertion (finding 4); IntensityBar "Recorded" legend
  only when a marker exists (finding 5); TargetsGrid null-summary shows "No confirmed meals
  yet" (finding 6); WorkoutHero doc comment corrected (finding 7). Finding 8 (date-scoped
  `loadLatest`) deferred to a later chunk per review.
- Chunk 3 decisions (2026-08-24):
  - Regression overlays derive deterministically from confirmed weigh-ins: each line passes
    through its window centroid (OLS property) and is clipped to its 7d/28d window and the
    chart range — no invented intercept, no extrapolation. Slopes come from
    `ComputedMetrics.weightTrend7d/28d`; R2 exists only for the 28d window (`weightTrendR2`),
    threshold 0.3 per ALGORITHMS.md §7; missing R2 → low confidence; the 7d line is never
    R2-gated.
  - `EvidenceAccordion` (`lib/shared/widgets/evidence_accordion.dart`) animates height BEFORE
    unmounting collapsed content, chevron rotates on the same controller, Reduce
    Motion → instant jump; header is a 44pt semantics button announcing expanded state.
    Replaces both raw `ExpansionTile` sites in Coach.
  - `ExpandableText` truncates at 6 lines with a real Show more/Show less control that renders
    only when the text actually overflows (no dead control on short reasons).
  - Progress measurement history rows are tappable → `MeasurementDetailSheet` (date, source,
    weight, optional tape values; read-only), making the "Tap a history row" copy a real
    affordance. Strength-progression rows stay display-only with an honest caption.
  - `MetricSparkline` wired into `WeightTrendIndicator` from real confirmed weigh-in
    values (its production home).
  - Coach screen rebuilt from extracted widgets (`coach_decision_card`, `coach_context_card`,
    `coach_message_bubble`, `coach_composer`); progress screen rebuilt from
    `widgets/{measurement_widgets,weight_trend_card,training_evidence_widgets,photo_widgets,weekly_review_widgets}.dart`.
    Both screens stay under the 500-line review budget.
  - Widget tests that drive a chat send must mock `SystemChannels.platform` —
    `HapticFeedback.lightImpact()` never completes on the unmocked test channel and stalls
    `_send` before the reply mounts.
- Chunk 3 review follow-ups (2026-08-24): all 10 findings fixed —
  (1+2) `deriveTrendOverlay`/`WeightTrendCard` binding contracts now disclose that overlay
  windows end at the latest confirmed weigh-in (may trail the brief target date) and that the
  centroid anchor uses displayed body-measurement dots only (server fit may merge HealthKit
  summary weights); (3) DESIGN_SYSTEM.md Evidence-visualization amended to permit labeled,
  R²-gated regression overlays (raw dots never smoothed; reconciles PRD §4.7);
  (4) `EvidenceAccordion` semantics label now includes the subtitle; (5) `ExpandableText`
  caches and disposes its overflow-probe `TextPainter`; (6) progress reachability test now
  taps Record measurement → entry sheet and Open weekly review → review sheet; (7) coach
  loading state asserted via a never-completing repository; (8) design-handoff markdown
  indent fixed; (9) frontend-handoff build line refreshed to 25.2 MB; (10) chat-bubble 18pt
  radius documented as a shape-lock exception in DESIGN_SYSTEM.md §3.3. 262 tests pass.
- Chunk 4 implementation notes (2026-08-24, `82bf748`):
  - `AiUsageScreen` (`lib/features/account/widgets/ai_usage_screen.dart`) binds only the
    merged `loadUsage()` fields; thresholds/limits render from RPC values; hero cost card
    is a `PremiumGradientCard` with glow; service pill = blocked (danger) / warning
    (attention) / available (stable) / hidden when budget fields absent; Refresh usage
    refetches; error state carries a working retry. No token counts, breakdown rows, or
    period toggle (not in any RPC).
  - `ConsentLedgerScreen` (`lib/features/account/widgets/consent_ledger_screen.dart`) is a
    StatefulWidget whose loader runs in `initState` (FutureBuilder subscribes before the
    future settles — a future created in the route builder leaks its error to the test
    zone). All five canonical purposes render; missing ones say "No record yet".
  - Account restyle: `PremiumGradientCard` profile hero, `AccountRow` icon-container rows
    (chevron only when tappable), tabular-figure detail values; account_screen.dart
    1075 → 388 lines via `widgets/{account_widgets,profile_goals_screen,ai_usage_screen,
    consent_ledger_screen,account_sheets,notification_sheet,coach_threads_sheet}.dart`.
  - Unconfigured environment: AI row = "AI service not configured" +
    "Approved plans and manual logging remain available" (UX_FLOWS §13); profile row
    detail is honest static copy (the old hardcoded "Lean muscle · private beta" was
    fabricated).
  - Shell capsule: inline `BackdropFilter` → `TracendGlass` inside a shadow-only
    `DecoratedBox`; `app_shell_test.dart` asserts exactly 2 `TracendGlass`/
    `BackdropFilter` widgets app-wide (confidence pill + capsule).
  - Deleted `ComingSoonButton`, `MiniTrendChart`, `_MiniTrendPainter` (zero usages).
  - 273 tests pass (11 new: 6 AI usage, 4 consent, 1 shell glass).
- Chunk 4 review follow-ups (2026-08-24): PASS WITH FINDINGS
  (`docs/reviews/2026-08-24-phase-5-v2-chunk-4-ai-usage-shell-account.md`), all findings
  resolved — (1, minor) Account AI row now distinguishes RPC failure from loading: usage
  future moved to `initState` (also fixes rebuild re-fire) and the error branch shows
  "AI usage unavailable · Open details to retry" (test added); (2) consent ledger picks
  latest per purpose by `created_at` regardless of input order (test reordered to prove
  it); (3) consent rows render the record `source`; (4) threshold copy uses
  fractional-safe `usdText`; (5) thread delete gained an error path; (6) doc line counts
  corrected. Deferred: `get_my_ai_usage`/`get_my_ai_budget_state` lack `schema_version`
  (AGENTS.md RPC rule) — needs an additive migration, out of this UI-only phase.
  Accepted: fixture-mode AI usage detail shows "$0.0000 · Estimates only" without
  repeating the not-configured framing (honest, test-asserted). 274 tests pass.
- Chunk 5 pre-check (2026-08-24, working tree clean at `53a26ef`): most §8.1/§8.2
  already shipped in Chunks 0–4 — TrajectoryLens 1.5s path draw + NOW-dot
  `MicroMotionPulse` (only idle loop), shell tab morph, `MicroMotion.stagger`/
  `exitDuration` helpers, semantics on rings/sparklines/trend charts/intensity bar/
  targets grid, contrast asserts in `theme_test.dart`, textScale-2 smoke tests.
  Remaining scope: (1) count-up on score changes (RecoveryRing score is static text);
  (2) stagger entrances on Today cards (`MicroMotionEntrance` only used in
  `today_hero`); (3) a11y audit — touch targets, Dynamic Type 1.3/largest coverage,
  bubble semantics verify; (4) copy self-audit; (5) final gate + review. Merge/push
  stays owner action (risk register row 6).
- Chunk 5 implementation notes (2026-08-24):
  - Motion: `MicroMotionCountUp` added to `micro_motion.dart` (animates only on
    value change, 600ms ease-out, reduceMotion-static) and wired into the
    RecoveryRing score. All nine Today brief sections wrapped in
    `MicroMotionEntrance` with fixed stagger slots 0–8; the redundant inner
    entrance around TrajectoryLens removed (hero-level stagger subsumes it).
  - A11y: `_DriverBar` gained a semantics label ("HRV driver, z-score 0.5",
    excludeSemantics); contrast asserts extended in `theme_test.dart`
    (stateAttention/stateDanger/actionOnPrimary/textPrimary-on-canvas/light
    graphics); all 5 chips use padded tap targets (48pt); tab labels clamp to
    1.3× scale (iOS tab-bar convention, protects the 70pt capsule); `_CardTag`
    label wraps instead of overflowing. Bubble semantics ("Coach said"/"You
    said") verified present. Notification sheet times verified against the
    native scheduler (hour 19 daily; hour 18 weekday 1 = Sunday).
  - Dynamic Type: new `test/dynamic_type_test.dart` — all five tabs at 320pt,
    scales 1.3 and 2.0 (largest iOS), no-overflow asserted. Fixed two real
    overflows found (session_plan_card `_CardTag`, app_shell tab label).
  - Copy audit: no filler, no AI-cliché, no fabricated numbers found; all
    interpolated strings trace to repository fields.
  - 284 tests pass (was 274).

---

## 0. Design Read (per design-taste-frontend skill §0)

> Reading this as: premium-consumer health-coaching app (iOS, single owner, iPhone 12) for a
> data-literate user, with a dark-tech "Precision Pro" language, leaning toward the Stitch
> design tokens already generated for this product — Spline Sans + IBM Plex Mono, off-black
> canvas, one indigo accent, spring-physics motion, glass on chrome only.

**Dials:** `DESIGN_VARIANCE: 7` · `MOTION_INTENSITY: 6` · `VISUAL_DENSITY: 6`

Consequences of these dials (skill §1.C):
- Variance 7 → asymmetric compositions inside cards; no centered-hero defaults; but this is a
  phone app, so asymmetry shows in card internals (value left / delta right, offset labels),
  not page-level masonry.
- Motion 6 → motion must actually exist and be motivated (hierarchy, feedback, state change).
  Spring `stiffness 100, damping 20`. No idle loops except the single NOW-dot pulse.
- Density 6 → IBM Plex Mono + tabular figures for ALL changing numbers (skill §7: density > 5
  mandates mono numerals). Cards still used (elevation communicates hierarchy at density 6),
  but data inside them breathes — hairline dividers, not boxes-in-boxes.

**Palette lock (skill §4.2):** the Stitch hex set below is the ONE palette. No warm/cool gray
drift between screens. One accent family (trajectory-indigo) + two semantic state hues
(stable-teal, attention) + one domain accent (nutrition-amber). Locked app-wide, audited in
Chunk 5.

**Shape lock (skill §4.4):** one radius scale, documented: cards 24pt (Stitch `3xl`),
decision surfaces 28pt, controls/buttons 12pt, pills/chips full. No mixing outside this rule.

---

## 1. Owner Rulings (2026-08-22, all confirmed)

1. Stitch "Precision Pro" visual direction. Owner loved the Stitch designs; the previous
   agent's execution was rejected.
2. `docs/DESIGN_SYSTEM.md` is outdated where it conflicts → amend it in the same change as
   the code (AGENTS.md rule), never silently override.
3. Scope: all 5 tabs, chunked, each chunk gated + `/review` before the next.
4. Every already-implemented repo feature must be surfaced beautifully and actually work —
   no no-op controls, no orphaned widgets, no dead affordances.
5. AI Usage: real RPC fields only. Stitch mock's token counts and per-feature breakdown rows
   do NOT exist in `get_my_ai_usage` → omitted, never fabricated.
6. Fonts: Spline Sans (display/headlines) + IBM Plex Mono (data values). Body/labels stay
   iOS system SF (Stitch's Inter maps to system SF on iOS).
7. Colors: Stitch hexes, contrast-guarded (ratios computed in §3, asserted in tests).
8. Process: tests configured first, nothing breaks at any step, research agents used for
   grounding, frontend skills loaded at execution.
9. **Master-plan gaps closed (this rewrite):** IntensityBar → Chunk 2; dedicated
   EvidenceAccordion → Chunk 3; weight 7d/28d regression overlay → Chunk 3; ReadinessStrip
   kept and restyled → Chunk 1; Nutrition CoachInsightCard → Chunk 2.
10. "Stunning modern UI" mandate: skills (`stitch-design-taste`, `design-taste-frontend`,
    `impeccable`) govern taste decisions; plan may be rewritten if it drifts.

---

## 2. Verified Facts (checked against repo 2026-08-22 — cite, don't guess)

### 2.1 Theme today
- `lib/app/theme/tracend_tokens.dart` — `TracendColors extends ThemeExtension` (13 fields),
  `TracendSpacing` (xxs 4 → xxl 48), `TracendRadii` (control 12 / card 20 / decision 28 /
  navigation 28), `TracendMotion` (quick 160 / standard 240 / emphasized 360, easeOutCubic).
  Dark: canvas `#090D14`, surface `#121925`, surfaceRaised `#182130`, textSecondary
  `#AAB5C5`, actionPrimary `#9BA5FF`, stateStable `#59D6C7`, borderSubtle `#293446`.
- `lib/app/theme/tracend_theme.dart:12` — hardcoded `fontFamily: '.SF Pro Text'` base
  override (must be removed for custom fonts to apply).
- `test/theme_test.dart` — has `_contrast()` helper; asserts textPrimary/textSecondary vs
  surface. Extend, don't replace.

### 2.2 Stitch source of truth (`design/stitch/screens/today/today.html` tailwind config)
Colors: canvas `#080B10` · base-surface `#111827` · elevated-surface `#1A222F` ·
primary-text `#F4F7FB` · secondary-text `#8894A8` · trajectory-indigo `#8A94F5` ·
stable-teal `#45C4B5` · nutrition-amber `#E2A45C` · chartreuse `#BCE85D` ·
border-hairline `#2D3748` · border-subtle `#1F2937`.
Type scale: screen-title 24/32 w600 · section-title 18/24 w600 · decision-headline 42,
lh 1.05, ls −0.03em, w600 · body-base 17/25 w300 · body-compact 14/20 w300 ·
data-utility 13/18 w400 · label-caps 11/16, ls 0.08em, w500.
Font roles: Spline Sans → screen-title/section-title/decision-headline · Inter → body/labels
(maps to iOS SF) · IBM Plex Mono → data-utility.
Spacing: base 4 / sm 8 / md 12 / lg 16 / gutter 20 / xl 24 / xxl 32 / xxxl 48 (matches
existing `TracendSpacing` — no change needed). Radii: 3xl = 24px for cards.
Google Fonts link confirms families+weights: Spline Sans 300–700, IBM Plex Mono 300–600,
Inter 300–600.
Other Stitch screens (train/nutrition/progress/coach) reuse the same dark palette plus
light-mode variants (`#F3F6F8`, `#f9f9ff`, `#9BA5FF`, `#FF887D`…) — our light theme keeps
the Phase-4 baseline; Stitch is dark-first.

### 2.3 Data models (what UI may bind to — nothing else)
- `DailyBrief` (`daily_brief_repository.dart:5`): `localDate`, `workout?`, `nextMeal?`,
  `checkIn?`, `health?`, `nutrition?`, `computed?`, `decision?` (all Maps except computed).
- `ComputedMetrics` (`computed_metrics.dart`): `scores` = recovery?, recoveryBreakdown?
  (hrvZ/rhrZ/sleepZ/respRateZ/prevStrainZ), sleepQuality?, sleepBreakdown?
  (duration/efficiency/restorative/consistency scores), sleepDebtMinutes?, dailyStrain?,
  acwr?, trainingMonotony?, **weightTrend7d?, weightTrend28d?, weightTrendR2?**,
  macroAdherencePct?; `baselines` = hrv/restingHr/sleepMinutes/weightKg/respRate each
  {ewma, spread, nObs, confidence}; `dataConfidence` (default `'cold_start'`).
- `CoachDecision` (`coach_repository.dart:4`): id, localDate, trainingAction,
  trainingSummary, nutritionAction, nutritionSummary, finalDecision, reason, confidence,
  evidence[], missingData[], riskFlags[], createdAt.
- `CoachMessage`: role, content, evidence[], missingData[], safetyState,
  suggestedFollowUps[], modelProvider?, model?, reasoningChain[].
- `NutritionSummary` (calories/protein/carbohydrate/fat/confirmedMeals) +
  `NutritionTargets` (same 4 fields) + `ScheduledMeal`/`MealCandidate` models.
- Workout models: `durationSeconds?`, per-exercise `target_rpe`, `session_effort`
  (currently hardcoded 8 on save at `workout_repository.dart:542` — IntensityBar must show
  recorded RPE from check-in draft, not pretend effort varies), `recorded_duration_seconds`,
  `healthkit_duration_seconds`, `duration_difference_seconds`.
- **AI usage reality:** `get_my_ai_usage()` (migration 20260702090000:218) returns ONLY
  `period='current_month', successful_runs, failed_runs, estimated_cost_usd`.
  `get_my_ai_budget_state()` (migration 20260704150000:360) returns `period,
  estimated_cost_usd, warning_threshold_usd=3, hard_stop_usd=5, warning, blocked,
  today_requests, daily_limit=30`. Flutter calls both (`coach_repository.dart:354`).
  → NO token counts, NO per-feature breakdown anywhere in UI.

### 2.4 Existing wired widgets (restyle, never rebuild)
- `RecoveryRing` → today_screen.dart:141 · `SleepArchitectureCard` → today_screen.dart:268
- `TrainingLoadGauge` → train_screen.dart:268 · `WeightTrendIndicator` → progress_screen.dart:125
- `EvidenceTrendChart` (`shared/widgets/evidence_trend_chart.dart`, CustomPainter) →
  today_screen.dart:950, progress_screen.dart:608
- `_ReadinessStrip` → today_screen.dart:465 (3 tiles: Recovery/Training/Nutrition, tap →
  detail sheet via `onOpen`)
- `HealthStatusCard` → today_screen.dart:275 + account_screen.dart:80
- `ReasoningChainCard` → coach_screen.dart:580 · `PreferencePromptChip` → coach widgets
- Shell: `_FloatingTabBar` (app_shell.dart:117) — 5 tabs, BackdropFilter σ18, uses
  `MediaQuery.disableAnimationsOf` — already the correct Reduce Motion API for the pinned
  Flutter 3.41.7 SDK (no change needed; earlier plan drafts wrongly called for a switch)

### 2.5 Orphans & dead affordances (wire or delete — audit)
- WIRE: `TrajectoryLens` (shared/widgets/trajectory_lens.dart, 87 lines, chip-rail stub —
  rewrite to bezier per §5.1) · `MetricSparkline` (shared/widgets/metric_sparkline.dart,
  test-only)
- DELETE: `ComingSoonButton` (tracend_scaffold.dart:239) · `MiniTrendChart`
  (tracend_scaffold.dart:389) — zero usages
- KEEP gallery-only: `MetricRow`
- Display-only rows to wire or justify: account_screen.dart:263 (justify — trailing delete
  is the action) · coach_screen.dart:601 (evidence item) · coach_screen.dart:668 (context
  source) · train_screen.dart:400 (recent session → WorkoutDetailScreen) ·
  train_screen.dart:836 (_ProgressionRow) · progress_screen.dart:190 (progression row) ·
  today_screen.dart:694 (_BriefEvidence row)
- Progress weight section says "Tap a history row below to verify" (progress_screen.dart:617)
  → make rows tappable or delete the instruction (anti-dead-affordance rule)

### 2.6 Fonts (research agent findings, 2026-08-22)
- Old Phase-5 attempt shipped FAKE files: `SplineSans-SemiBold.ttf` byte-identical to Bold
  (51,468 B each). Discard pattern; verify every intake.
- **Spline Sans:** github.com/SorkinType/SplineSans, SIL OFL 1.1, no Reserved Font Names.
  Expected static sizes: Light 75,504 / Regular 74,548 / Medium 76,672 / SemiBold 78,232 /
  Bold 77,396 B. Google Fonts ships variable-only → use SorkinType statics.
- **IBM Plex Mono:** github.com/IBM/plex v2.5.0, OFL 1.1 WITH Reserved Font Name "Plex" →
  never subset/modify. Expected: Regular 173,052 / Medium 174,008 / SemiBold 174,608 B.
- `pubspec.yaml` fonts section currently commented out; `assets/fonts/` does not exist.
- OFL-FAQ 1.20: include copyright statement + license text in-app via `LicenseRegistry`.

### 2.7 Glass performance budget (research agent, iPhone 12 / A14 / Impeller)
- Max 1–2 visible BackdropFilter sites for 60fps. Blur cost = area × sigma, re-runs every
  frame content beneath changes.
- Never nest independent BackdropFilters → `BackdropGroup` if grouping. Never animate sigma.
  Wrap static glass in `RepaintBoundary`.
- Reduce Motion: gate on `MediaQuery.disableAnimationsOf(context)` — the pinned Flutter
  3.41.7 SDK has no `MediaQuery.accessibilityFeaturesOf`; iOS Reduce Motion surfaces through
  `disableAnimations`.
- Reduce Transparency: NO Flutter API (issue #190318 open) → app-level flag + opaque fallback.
- Sanctioned glass sites (max 2 visible at once): floating tab bar (exists), top app bar,
  confidence pill. Content cards and charts NEVER blur — they use `PremiumGradientCard`.

### 2.8 Screen sizes (rewrite budget awareness)
today 971 · train 932 · nutrition 1039 · progress 1066 · coach 758 · account 1075 ·
app_shell 288 · tracend_scaffold 508 lines. Extract sub-widgets into
`lib/features/<feature>/widgets/` as screens are rebuilt — target < 500 lines/screen.

### 2.9 Tests & gates
- Existing: theme_test, recovery_ring_test, sleep_architecture_card_test,
  training_load_gauge_test, weight_trend_and_sparkline_test, evidence_ui_components_test,
  frontend_smoke_test, app_shell_test, phase_3/4/5/6/7/8 suites, contract/.
- Gate commands (wrappers mandatory):
  `./scripts/flutter.sh analyze` · `./scripts/flutter.sh format --set-exit-if-changed lib test`
  · `./scripts/flutter.sh test` · Chunk 5 adds deno fmt/lint/test + iOS release build.
- Deploy auto-triggers on push to `feature/feature-engine` (NOT the v2 branch) — merge is
  the deploy trigger. `git push` is deny-listed for agents: user pushes.

---

## 3. Chunk 0 — Foundation (docs + tokens + fonts + glass + motion)

### 3.1 Authority docs FIRST (same commit as tokens)
- `docs/DESIGN_SYSTEM.md §3.2 Typography`: permit Spline Sans (display/headlines only) +
  IBM Plex Mono (data values only); body/labels remain system SF. Document OFL inclusion
  via LicenseRegistry. Cite Stitch type-scale mapping (screen-title 24/600, section-title
  18/600, decision-headline 42/600/−0.03em, data-utility 13 mono).
- `docs/DESIGN_SYSTEM.md §3.4 Elevation and material`: permit (a) premium-gradient SOLID
  fills on evidence/content cards (tonal separation, zero blur); (b) restrained glass on
  top app bar, confidence pill, floating tab capsule. Max 2 visible BackdropFilter sites
  app-wide. Content cards and charts never use BackdropFilter. Opaque fallback when
  reduce-transparency flag active.
- `docs/DESIGN_SYSTEM.md §10 Anti-Patterns`: add "glass/blur on content cards",
  "fabricated metrics or fake-precise numbers", "dead affordances (no-op chevrons/buttons)",
  "hardcoded confidence strings". Remove any contradicting entry.
- `docs/DESIGN_SYSTEM.md §3.3`: card radius 20 → 24 (Stitch 3xl), document shape lock
  (cards 24 / decision 28 / controls 12 / pills full).
- `docs/handoff/design.md` + `docs/PROGRESS_CONTEXT.md`: active change = Phase 5 v2,
  chunked, this plan file as reference.

### 3.2 Tokens (`tracend_tokens.dart`) — Stitch hexes, contrast-guarded

Dark theme changes (light theme UNCHANGED — Stitch is dark-first):

| Token | Current | New | Contrast note |
|---|---|---|---|
| canvas | `#090D14` | `#080B10` | Stitch canvas |
| surface | `#121925` | `#111827` | Stitch base-surface |
| surfaceRaised | `#182130` | `#1A222F` | Stitch elevated-surface |
| textSecondary | `#AAB5C5` | `#8894A8` | ≈6.3:1 on canvas, ≈4.8:1 on surface — AA body ✓ (assert in test) |
| actionPrimary | `#9BA5FF` | `#8A94F5` | Stitch trajectory-indigo; assert ≥4.5:1 with `actionOnPrimary` text usage, else keep text on canvas |
| stateStable | `#59D6C7` | `#45C4B5` | Stitch stable-teal; assert ≥3:1 vs canvas (graphics threshold) |
| borderSubtle | `#293446` | **KEEP** | Stitch `#1F2937` measures ≈1.2:1 vs canvas = invisible → rejected |
| NEW `borderHairline` | — | `#2D3748` | decorative 0.5–1px borders only, never the sole affordance signal |
| NEW `accentAmber` | — | `#E2A45C` | nutrition domain accent (replaces 13× hardcoded duplicates) |
| NEW `accentNow` | — | `#BCE85D` | NOW indicator dot only |
| scrim | `#B3090D14` | `#B3080B10` | track canvas change |

Also: `TracendRadii.card` 20 → 24 (shape lock). Add `TracendFonts` constants class:
`displayFamily = 'Spline Sans'`, `monoFamily = 'IBM Plex Mono'`.

### 3.3 Fonts
1. Create `assets/fonts/`. Download genuine statics:
   - SorkinType/SplineSans `fonts/ttf/SplineSans-{Regular,Medium,SemiBold,Bold}.ttf`
   - IBM/plex v2.5.0 release → `IBMPlexMono-{Regular,Medium,SemiBold}.ttf`
2. Verify BEFORE committing: byte sizes match §2.6 table; `shasum -a 256` all distinct;
   no two files byte-identical; internal `usWeightClass` = 600 vs 700 for SemiBold/Bold
   (python/fontTools or `otfinfo` if available — else size+SHA distinctness suffices).
3. `pubspec.yaml`: uncomment/replace fonts block —
   family `Spline Sans` (Regular + Medium 500 + SemiBold 600 + Bold 700), family
   `IBM Plex Mono` (Regular + Medium 500 + SemiBold 600). Explicit `weight:` on every
   non-Regular asset. No filename inference, no fake-bold synthesis.
4. OFL texts → `assets/fonts/OFL-SplineSans.txt` + `assets/fonts/OFL-IBMPlex.txt`;
   register both via `LicenseRegistry.addLicense` in `main.dart`.
5. Theme wiring (`tracend_theme.dart`):
   - REMOVE `fontFamily: '.SF Pro Text'` (line 12)
   - displaySmall/headlineMedium/titleLarge/titleMedium → `fontFamily: TracendFonts.displayFamily`
   - body/label styles: NO fontFamily (system SF)
   - labelMedium keeps `tabularFigures()`; add a `dataUtility` helper style (13/18 mono,
     tabular) for data call sites
   - decision-headline usage (42pt) applied at call site in Chunk 1, not in base theme

### 3.4 Shared widgets (new files under `lib/shared/widgets/`)
- `tracend_glass.dart` — `TracendGlass`: ClipRRect → BackdropFilter(σ24) → 72% surface
  fill + 1px 10%-white inner border + 8% top-highlight gradient. Wrapped in
  `RepaintBoundary`. `enabled` flag + app-level reduce-transparency flag → opaque
  `surfaceRaised` fallback (no blur). Used ONLY at: top app bar, confidence pill,
  tab capsule.
- `premium_gradient_card.dart` — `PremiumGradientCard`: solid 145° LinearGradient
  (surface@80% → canvas@90%), hairline border (`borderHairline`), 24pt radius, optional
  decorative corner glow (paint-only radial gradient, ZERO blur). The Stitch evidence-card
  surface. Assert no BackdropFilter in its subtree (test).
- `micro_motion.dart` — `MicroMotion`: spring entrance (stiffness 100, damping 20),
  scroll-stagger helper (per-index delay ≤60ms), single pulse-loop helper. ALL gated on
  `MediaQuery.disableAnimationsOf(context)` (pinned SDK API). Exits 15–30% faster than
  entries. Nothing animates idle.

### 3.5 Tests FIRST (write from code as it lands, per anti-failure rule 6)
- `test/theme_test.dart` update: new dark pairings pass AA (textSecondary vs canvas AND
  surface; actionPrimary graphics ≥3:1; stateStable ≥3:1); light theme unchanged assertions.
- `test/fonts_test.dart` (new): both families present in TextTheme/constants; weights
  distinct; display styles carry Spline Sans, body styles carry no fontFamily.
- `test/widgets/tracend_glass_test.dart` (new): renders; `enabled: false` → no
  BackdropFilter in tree; fallback opaque.
- `test/widgets/premium_gradient_card_test.dart` (new): renders; `find.byType(BackdropFilter)`
  finds nothing inside.
- `test/widgets/micro_motion_test.dart` (new): reduceMotion → no running AnimationControllers.

### 3.6 Gate → commit → `/review`

---

## 4. Chunk 1 — Today Screen (hero + readouts)

### 4.1 Data-binding contract (every number traces to a field — this table is THE contract)

| Stitch element | Real data source | cold_start / null state |
|---|---|---|
| Confidence pill | `brief.computed.dataConfidence` | "Building baseline" |
| Decision headline | `brief.decision['final_decision']` / `nextAction` | "Keep the approved plan." |
| Reason text | `brief.decision['reason']` | deterministic fallback text |
| Sync timestamp | `brief.health['local_date']` / decision `createdAt` | hidden |
| TrajectoryLens bezier | `computed.scores` (sleep/recovery/strain normalized) | decorative static path, labeled as such |
| ReadinessStrip tiles | `computed.scores.recovery` + band + `recoveryBreakdown` z-chips; `dailyStrain` + `acwr`; `macroAdherencePct` | '--' + "Check in"/"Updated" (existing logic kept) |
| Sleep Architecture | existing `SleepArchitectureCard` restyled into PremiumGradientCard; `sleepBreakdown.*`, baselines HRV/RHR | "Not enough data" |
| Session Plan card | `brief.workout` name/objective; set/movement counts from workout exercises fold (pattern train_screen.dart:629) | "No session planned" |
| Metabolic Target card | `brief.nutrition` + NutritionSummary/Targets (kcal, protein, remaining computed) | targets only, no consumed |
| T-Coach / N-Coach toggle | REAL: switches `CoachDecision.trainingSummary` ↔ `nutritionSummary` | hidden if no decision |
| Coach insight card | `CoachDecision.finalDecision/reason/confidence` + `modelProvider` | hidden; NEVER fake "v2.4" |
| Check-in bar | → `showCheckInSheet` (exists) | — |
| Start session | → active workout flow (exists) | disabled if no workout |
| View analytics | → Progress tab (real navigation) | — |
| RecoveryRing | kept (Phase 4, real) | existing cold-start state |

### 4.2 TrajectoryLens rewrite spec (`lib/shared/widgets/trajectory_lens.dart`)
- `CustomPainter` bezier path + `PathMetric` draw-on (1.5s, easeOutCubic) via
  `AnimatedBuilder` — NO setState-per-frame
- Precompute bezier constants; ≤200 samples; values passed explicitly (`bezierValues`
  param actually consumed — the v1 bug)
- Data dots: Sleep → Train → Fuel → Now from `computed.scores`; NOW dot = `accentNow`
  + glow pulse (the single sanctioned idle loop)
- reduceMotion → static full path, no draw animation
- Labels: 11px caps (label-caps scale), system font, 0.08em tracking; Semantics label
  describes the underlying values
- Keep the old chip-rail as fallback when fewer than 2 scores exist

### 4.3 Layout (Stitch today.html, top to bottom)
1. Top bar: "Tracend" + date + account avatar (TracendGlass)
2. Hero: confidence pill (TracendGlass) + sync timestamp · headline (Spline Sans,
   decision-headline scale 42pt, −0.03em) · reason · TrajectoryLens (≈280pt) ·
   [Start session] [View analytics]
3. **ReadinessStrip — KEPT, restyled**: 3 compact tiles (Recovery score+band+driver
   z-chips / Training strain+ACWR / Nutrition adherence %), mono values, existing
   `onOpen` detail sheet kept. Asymmetric internal layout (big value left, delta/chips
   right) per variance dial.
4. "PRECISION READOUTS" stylized divider (label-caps)
5. Sleep Architecture (PremiumGradientCard)
6. Session Plan (PremiumGradientCard)
7. Metabolic Target (PremiumGradientCard)
8. Coach perspective: T-Coach/N-Coach segmented + insight card
9. Check-in prompt bar
10. Existing health evidence section kept below (real data, restyled; `_BriefEvidence`
    row at :694 wired or justified)

### 4.4 Rules
- State table per widget BEFORE code (full / cold_start / null / low-confidence)
- No `onPressed: () {}` anywhere; every chevron navigates or is deleted
- Flexible/FittedBox chip rows — no Row overflow at 320pt
- Extract hero/readout sub-widgets to `lib/features/today/widgets/` (screen < 500 lines)

### 4.5 Tests
Per-widget state tables + frontend_smoke_test at 320/375pt + a11y scaling 1.3/largest.

### 4.6 Gate → commit → `/review`

---

## 5. Chunk 2 — Train + Nutrition

### 5.1 Train
- **IntensityBar (NEW — master plan P1, `lib/shared/widgets/intensity_bar.dart`)**:
  per-exercise `target_rpe` bars (0–10 scale) + session RPE marker from recorded check-in
  draft + `dailyStrain` context line. Real data only: `planned_exercises.target_rpe`,
  `recorded_duration_seconds`. Cold start: "Log a session to see intensity" — never
  invent bars. NOTE: `session_effort` is hardcoded 8 on save (workout_repository.dart:542)
  → display recorded RPE from the draft, do not imply per-session effort variance that
  isn't captured.
- **DatePillStrip (NEW, `lib/shared/widgets/date_pill_strip.dart`)**: week navigation
  with REAL chevron offset state, normalized-date Set lookup for days-with-data, const
  constructors, Dynamic-Type-safe widths. Reused by Nutrition.
- TrainingLoadGauge (exists, real ACWR) restyled into PremiumGradientCard context
- Session bars from real workout data (no `clamp(3,6)` fabrication)
- Recent session row (train_screen.dart:400) → wire to WorkoutDetailScreen
- `_ProgressionRow` (train_screen.dart:836) → wire to real destination or convert to
  non-interactive text (decide during implementation; document choice)

### 5.2 Nutrition
- **TargetsGrid (NEW, `lib/shared/widgets/targets_grid.dart`)**: real NutritionTargets
  (kcal/protein/carb/fat) with consumed from NutritionSummary; solid cells (NO nested
  glass); mono values; `X / Yg` readable text + a11y role
- Meal cards restyled (PremiumGradientCard), metabolic bar gradient (amber accent)
- DatePillStrip reuse
- **CoachInsightCard (master plan Phase-5 item, was missing)**: nutrition insight from
  `CoachDecision.nutritionSummary` + confidence; hidden when no decision — never faked

### 5.3 Gate → commit → `/review`

---

## 6. Chunk 3 — Progress + Coach

### 6.1 Progress
- **Weight regression overlay (NEW — data already exists)**: extend `EvidenceTrendChart`
  with optional 7d/28d trend lines from `ComputedMetrics.weightTrend7d/28d/R2`. Labeled
  ("7-day trend", "28-day trend"), R2-gated confidence (low R2 → dashed + "low
  confidence" note), legend distinguishes raw dots (measured) vs model lines (computed).
  Keep "each dot is an actual confirmed weigh-in" honesty copy.
- WeightTrendIndicator (exists, real) restyled
- Body measurements section (real `save_body_measurement` RPC)
- Evidence rows with EvidenceTrendChart (exists, real); **MetricSparkline wired** into
  evidence rows here (its production home per master plan)
- Progression row (progress_screen.dart:190) → wire or justify as display-only
- "Tap a history row" instruction (progress_screen.dart:617) → make rows tappable
  (detail sheet: date, source, value) or remove the instruction

### 6.2 Coach
- **EvidenceAccordion (NEW dedicated component — master plan P1,
  `lib/shared/widgets/evidence_accordion.dart`)**: correct collapse semantics (animate
  height BEFORE removing content), chevron rotation, reduceMotion → instant. Replaces
  raw `ExpansionTile` usages in coach_screen.dart (595, 658).
- CoachInsightCard: stroke inset by width/2 (no clipped border), no per-frame rebuild,
  expansion for >6 lines
- Evidence item row (coach_screen.dart:601) + context source row (:668) → wire or justify
- Styled composer + suggestion pills (PreferencePromptChip exists;
  `suggestedFollowUps[]` is the real source)
- Confidence ALWAYS from `CoachDecision.confidence` — never hardcoded "medium"
- ReasoningChainCard kept (wired at :580), restyled

### 6.3 Gate → commit → `/review`

---

## 7. Chunk 4 — AI Usage + Shell + Account

**Chunk 4 decisions (2026-08-24, owner-confirmed):**
- "Privacy and AI processing" row → NEW read-only **consent ledger** screen: latest
  state per purpose from `consent_records` (terms, privacy, progress_photo_storage,
  progress_photo_ai, notifications), following the `_loadProfileGoals` direct-select
  pattern (RLS `consent_records_select_own` already grants owner reads).
- Account scope = **full Precision Pro restyle** (not cleanup-only): rows/cards restyled
  with `PremiumGradientCard`, mono values, section labels — matching Chunks 1–3.
- `session-ses_fcef.md` (untracked session artifact) → leave as-is; not deleted, not
  gitignored.
- Threads row in delete sheet → documented as display-only; the trailing delete button
  is the action (no dead chevron).
- Extraction targets (`lib/features/account/widgets/`): AI usage screen, consent ledger
  screen, profile-goals screen, deletion/export/notification sheets — account_screen.dart
  1075 → <500 lines.

### 7.1 My AI Usage screen (rebuilt from `_AiUsageScreen`, account_screen.dart:418)
- REAL fields only: `successful_runs`, `failed_runs`, `estimated_cost_usd` (from
  `get_my_ai_usage`) + `today_requests`, `daily_limit` (30), `warning_threshold_usd` (3),
  `hard_stop_usd` (5), `warning`, `blocked` (from `get_my_ai_budget_state`)
- Cost labeled "operational estimate" (per AI_USAGE_PROMPT.md)
- OMITTED (do not exist in any RPC): token counts, per-feature breakdown rows
- Period: RPC is current_month only → single period display, NO dead toggle
- Budget text binds the RPC values at render time. Note: the plan originally assumed
  $3/$5/30-per-day production thresholds, but the latest deployed migration
  (`20260711100000_owner_groq_qwen_test_routing.sql`) overrides `get_my_ai_budget_state`
  to $1 warning / $2 hard stop / 10 daily. The UI hardcodes neither — thresholds,
  limits, and warning copy all render from the RPC response (owner decision 2026-08-24).
- States: loading / empty / stale / unavailable; "Refresh usage" → real refetch
  (re-assign future)
- Never display API keys, prompts, raw errors, cross-user totals

### 7.2 Shell
- KEEP 5 TABS (DESIGN_SYSTEM.md §4 mandates 5; Stitch's 4-tab mock rejected)
- Restyle capsule with `TracendGlass` (replaces inline BackdropFilter at
  app_shell.dart:166); tab motion via TracendMotion tokens
- Reduce Motion API: shell already uses `MediaQuery.disableAnimationsOf` (app_shell.dart:156)
  — correct for the pinned SDK; keep as-is when restyling the capsule

### 7.3 Account
- "Privacy and AI processing" row → wire to real destination or delete
- Conversation row in delete sheet (:263) → justify as display (trailing delete is the action)
- DELETE: `ComingSoonButton` (tracend_scaffold.dart:239), `MiniTrendChart` (:389)

### 7.4 Gate → commit → `/review`

---

## 8. Chunk 5 — Motion + A11y + Final

### 8.1 Animation pass (all reduceMotion-gated, all motivated)
- Stagger entrances (cards, ≤60ms per-index), TrajectoryLens path draw (1.5s), NOW-dot
  pulse (only idle loop), count-up on score changes, tab morph
- Exits 15–30% faster than entries; press feedback <100ms; nothing else animates idle

### 8.2 A11y pass (impeccable skill)
- Dynamic Type 1.0 / 1.3 / largest — wraps before truncating, no overflow at 320pt
- VoiceOver labels on ALL data viz (rings, gauges, sparklines, bezier, regression lines)
- 44×44pt touch targets, ≥8pt between adjacent
- Contrast audit: every new token pairing ≥4.5:1 body / ≥3:1 large+graphics (asserted)
- Bubble semantics restored ('Coach said' labels; color never the only signal)

### 8.3 Copy self-audit (design-taste-frontend §4.9)
Re-read every visible string: no AI-cliché copy, no fake-precise numbers, no filler
("Scroll to explore"), no unclear referents. One copy register per screen.

### 8.4 Final gate
```sh
./scripts/flutter.sh analyze
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh test
./scripts/deno.sh fmt --check supabase/functions
./scripts/deno.sh lint supabase/functions
./scripts/deno.sh test --allow-env --allow-net supabase/functions
./scripts/flutter.sh build ios --release --no-codesign
```
- iPhone manual pass: dark+light, reduce motion, reduce transparency fallback, Dynamic
  Type, 60fps scroll (no blur jank)
- Docs final: PROGRESS_CONTEXT.md, handoff/frontend.md, UX_FLOWS.md (if nav changed)
- `/review` → `/test` → merge to `feature/feature-engine` → auto-deploy

---

## 9. Explicitly OUT of v2
- Welcome/onboarding screens (post-MVP — needs Apple Sign-in; 16 Stitch refs preserved)
- WorkoutModeSheet (would fabricate data — no real session-tracking backend yet)
- WeeklyScheduleStrip, SessionMap (master plan P3 — deferred, no current requirement)
- Any DB migration, any Edge Function change
- MetricRow production wiring (gallery specimen only)
- Light-theme Stitch restyle (light stays Phase-4 baseline; Stitch is dark-first)

## 10. Anti-failure rules (from 2026-08-18 audit — the ones that bit Phase 5 v1)
1. Authority docs amended FIRST in Chunk 0, never after, never silently overridden
2. Every number on screen traces to a repository/model field — binding tables are contract
3. State table per widget BEFORE code (full / cold_start / null / low-confidence)
4. No orphans, no no-ops, no dead affordances — wire it or delete it
5. Max 2 visible BackdropFilter sites app-wide; BackdropGroup if grouped; never animate sigma
6. Tests written from code, never from plan
7. Per-chunk gate + `/review` before next chunk starts
8. Missing/conflicting data lowers confidence; never silently invented
9. Fonts verified on intake (size + SHA + weight class) — never trust a download blindly
10. Skills govern taste; if plan and skill conflict, surface the conflict, don't choose silently

## 11. Risk Register
| Risk | Mitigation |
|---|---|
| Font download unavailable/corrupted | §2.6 verification table; abort chunk on mismatch |
| BackdropFilter jank on iPhone 12 | 2-site budget; RepaintBoundary; manual 60fps pass |
| Screen files too large to review | extract to `widgets/` subdirs, <500 lines/screen |
| Token change breaks light theme | light theme untouched; theme_test asserts both |
| Merge conflicts with `feature/feature-engine` | branch is from its HEAD (93fa49e); merge soon after Chunk 5 |
| `git push` denied for agents | user pushes branch/tag; local tags + commits are the backup |
| Stitch mock features without backend (tokens, breakdown) | §7.1 OMITTED list; binding tables enforce |
