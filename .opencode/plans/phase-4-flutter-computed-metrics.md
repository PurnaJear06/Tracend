# Phase 4 — Flutter UI: Computed Metrics Widgets

**Parent plan:** `feature-engine-and-ui-alignment.md`
**Created:** 2026-07-26
**Branch:** `feature/feature-engine-phase-4` (off `feature/feature-engine`)
**Effort:** 3-4 days
**Skills:** Impeccable (craft, critique, bolder, polish) + Taste-Skill (stitch, redesign)

---

## Objective

Build Flutter widgets that visualize the feature engine's computed scores — recovery, sleep quality,
training load, weight trends, macro adherence — as native iOS components faithful to the Stitch
design language. The computed data already flows from PostgreSQL into the `get_my_daily_brief` RPC
response; the Flutter model layer needs to parse it and new widgets need to render it.

## What Changes

```
BEFORE: DailyBrief model ignores the `computed` field from RPC response.
        Today shows 3 readiness tiles backed by subjective check-in flags.
        No recovery visualizations, sleep architecture, ACWR gauge, or trend lines.
        Charts show raw values without regression overlays.

AFTER:  DailyBrief parses `computed` → ComputedMetrics model.
        RecoveryRing: 240° animated arc gauge with driver breakdown.
        SleepArchitectureCard: stacked sleep-stage bars + quality score.
        ReadinessStrip redesign: 3 cards showing computed scores instead of check-in booleans.
        TrainingLoadGauge: ACWR horizontal bar with colored zones.
        Weight Trend Line: OLS regression overlay on existing weight chart.
        MetricSparkline: 44×16pt inline trend for HRV, RHR, sleep, weight.
```

## Design Language

All widgets follow the Stitch "Kinetic Precision" aesthetic — instrument readouts and training-log
discipline, not gamified dashboards or motivational UIs:

- Dark mode reference: canvas `#090D14`, surface `#121925`, action `#9BA5FF`, stable `#59D6C7`,
  attention `#FF887D`, nutrition-amber `#E2A45C`
- Recovery arc uses a directional sweep gradient encoding recovery band
- Colored zones are always paired with text labels (no color-only signal)
- No activity rings, composite scores alone, or generic fitness ring anti-patterns
- Content width-constrained to 720pt, 20pt gutter
- Cards use `TracendRadii.decision` (28pt) for primary surfaces, `card` (20pt) for secondary
- Motion: 240ms `easeOutCubic` on expand/crossfade, 160ms on micro-interactions

**Raw hex values never appear in feature widgets.** All colors come from `context.tracendColors`,
all spacing from `TracendSpacing`, all radii from `TracendRadii`.

---

## Step 1: Data Plumbing

### 1.1 ComputedMetrics Model

Create `lib/features/today/computed_metrics.dart`:

```dart
class ComputedMetrics {
  final int? recoveryScore;
  final Map<String, double?> recoveryBreakdown; // hrv_z, rhr_z, sleep_z, resp_rate_z, prev_strain_z
  final int? sleepQuality;
  final Map<String, double?> sleepBreakdown; // duration, efficiency, restorative, consistency
  final int? sleepDebtMinutes;
  final double dailyStrain;
  final double? acwr;
  final double? trainingMonotony;
  final double? weightTrend7dKgPerDay;
  final double? weightTrend28dKgPerDay;
  final double? weightTrendR2_28d;
  final int? macroAdherencePct;
  final String dataConfidence; // cold_start, low, medium, high
}
```

Factory `ComputedMetrics.fromJson(Map<String, dynamic> json)`:
- Navigates `scores.recovery`, `scores.recovery_breakdown.*`, etc.
- All fields nullable-safe with sensible defaults
- `dataConfidence` defaults to `'low'` when absent

### 1.2 Update DailyBrief Model

In `daily_brief_repository.dart`:

```dart
class DailyBrief {
  // ... existing fields ...
  final ComputedMetrics? computed; // NEW
}
```

`SupabaseDailyBriefRepository.load()` adds:
```dart
computed: value['computed'] is Map
    ? ComputedMetrics.fromJson(Map<String, dynamic>.from(value['computed'] as Map))
    : null,
```

`FixtureDailyBriefRepository.load()` adds computed fixture data (from the daily_brief_v1_1.json
shape).

### 1.3 Contract Test Fixture

Update `test/contract/fixtures/daily_brief_v1_1.json` if needed (the `computed` key already exists
with real values — verify it matches `ComputedMetrics.fromJson` parsing). Update
`test/contract/daily_brief_contract_test.dart` to assert the computed field parses correctly.

### 1.4 ComputedMetrics Widget Tests

Create `test/features/computed_metrics_test.dart`:
- `fromJson` parses full fixture → all fields populated
- `fromJson` parses empty scores → null-safe defaults
- `fromJson` parses missing computed key → `null`
- `fromJson` parses partial scores (recovery only, no sleep) → graceful nulls

### Verification

```sh
./scripts/flutter.sh test test/features/computed_metrics_test.dart
./scripts/flutter.sh test test/contract/daily_brief_contract_test.dart
```

---

## Step 2: RecoveryRing Widget

### 2.1 Visual Spec (from Stitch design language)

```
      ┌─────────────────────┐
      │    ╭──── 240° ────╮ │
      │   ╱               ╲ │
      │  │       72       │ │  ← centered score, displaySmall (32px, 700)
      │  │    Recovery    │ │  ← labelMedium (13px, 600)
      │   ╲               ╱ │
      │    ╰──────────────╯ │  ← open at bottom (60° gap)
      │                     │
      │  HRV  +0.5σ    ↑   │  ← driver chips (TracendPill style)
      │  RHR  +0.5σ    →   │     z-score as label, ↑/→/↓ icon
      │  Sleep +0.8σ   ↑   │
      └─────────────────────┘
```

- CustomPainter: 240° open arc, 12pt stroke width, round caps
- SweepGradient: green (#59D6C7 at 0.0) → yellow (#E2A45C at 0.5) → red (#FF887D at 1.0)
  mapped to recovery bands: Green 67-100, Yellow 34-66, Red 0-33
- Arc background: `borderSubtle` at 20% opacity, same stroke
- Animated arc: `AnimationController` 1.5s, `easeOutCubic`, `stroke-dashoffset` draw-on
- Centered score text: `displaySmall` with tabular figures
- Sub-label: "Recovery" in `labelMedium`, `textSecondary`
- Driver chips below: `TracendPill` variants showing `metric_name + z_value + trend_icon`
  - HRV: weight 0.55 — ↑ when z>0, ↓ when z<0, → when ≈0
  - RHR: weight 0.20 — ↓ when z<0 (lower RHR is good)
  - Sleep: weight 0.15 — ↑ when z>0
  - Others: shown compactly on second row if space permits

### 2.2 API

```dart
class RecoveryRing extends StatelessWidget {
  final int recoveryScore;           // 0-100
  final Map<String, double?> drivers; // hrv_z, rhr_z, sleep_z, resp_rate_z, prev_strain_z
  final String? confidence;          // high, medium, low, cold_start
}
```

### 2.3 States

| State | Behavior |
|-------|----------|
| Score 67-100 (Green) | Ring filled to value, green band, "Within baseline" label |
| Score 34-66 (Yellow) | Ring filled to value, yellow band, "Moderate" label |
| Score 0-33 (Red) | Ring filled to value, red band, "Below baseline" label |
| Cold start / null | Dotted arc, "Not enough data" centered, drivers hidden |
| Low confidence | Pale arc with confidence badge |

### 2.4 Placement

In `today_screen.dart`, inside the decision `TracendCard`, after `_TodayHeroBackdrop` (line ~135)
and before `_ReadinessStrip` (line ~137). Standalone centered widget.

### Verification

```sh
./scripts/flutter.sh test test/widgets/recovery_ring_test.dart
```

Golden tests: green band (score=85), yellow band (score=50), red band (score=20), cold start (null).

---

## Step 3: SleepArchitectureCard Widget

### 3.1 Visual Spec

```
┌─────────────────────────────────────┐
│  SLEEP ARCHITECTURE                 │  ← label-caps, stateStable
│                                     │
│  7h 42m            Quality: 85      │  ← headlineMedium + quality score
│                                     │
│  ┌─── Hypnogram ──────────────────┐ │
│  │ ████░░████░░██░░████░░████░░█  │ │  ← horizontal stacked bar
│  │ ███░░░████░██░░████░░████░██ ░ │ │     4 stage colors (deep=indigo,
│  │ ██████░░████░██░░████░████░██  │ │     rem=purple, light=blue,
│  └─────────────────────────────────┘ │     awake=gray)
│                                     │
│  92%          43%          -65 min  │  ← MetricStrip: efficiency,
│  Efficiency   Restorative  Debt     │     restorative %, debt min
└─────────────────────────────────────┘
```

- `TracendCard` with `raised: false`, radius `card` (20pt)
- Header: "SLEEP ARCHITECTURE" in `labelMedium` caps, `stateStable` color, with `bedtime` icon
- Duration: total sleep time in headline style (32px, 700), "h"/"m" in secondary color
- Quality score: right-aligned, `titleMedium`
- Hypnogram: `CustomPainter` rendering horizontal bars per sleep stage
  - Each bar = one sleep period segment (time-ordered across the night)
  - Deep sleep: `actionPrimary` (indigo) at 80% opacity
  - REM: `actionPrimary` at 50% opacity
  - Light: `actionPrimary` at 25% opacity
  - Awake: `borderSubtle`
  - Rounded corners (2pt) on bar segments, 2pt gap between segments
  - 48pt total height, ~20-30 segments per night
- Bottom metrics: `MetricStrip` with 3 items
  - Efficiency % (from `sleep_breakdown.efficiency_score`)
  - Restorative % (from `sleep_breakdown.restorative_score`)
  - Debt minutes (positive = debt, negative = surplus, color-coded: attention when positive)

### 3.2 API

```dart
class SleepArchitectureCard extends StatelessWidget {
  final int? totalMinutes;
  final int? qualityScore;
  final Map<String, double?> breakdown; // duration, efficiency, restorative, consistency
  final int? debtMinutes;
  final List<SleepStageSegment> stages; // from HealthKit sleep stage data
}

class SleepStageSegment {
  final double startFraction; // 0.0 to 1.0 across the night
  final double durationFraction;
  final SleepStageType stage;
}

enum SleepStageType { deep, rem, light, awake }
```

### 3.3 Data Source

Sleep stages come from `HealthDay` model (already parsed from Apple Health): `sleepDeepMinutes`,
`sleepRemMinutes`, `sleepAwakeMinutes`, `sleepLightMinutes`. These are aggregated totals. To build
a hypnogram, we need segment-level data. **Apple Health provides sleep stage samples** — the
`health-sync` Edge Function stores them in `daily_health_summaries`. For MVP Phase 4, use the new
`get_my_daily_sleep_stages(target_date)` RPC (lightweight, returns ordered stage segments) OR fall
back to a simplified bar representing aggregated stage proportions if segment data isn't yet
surfaced.

**Decision: Simplified bar for now.** Use aggregated stage totals to render 3-4 proportional
blocks instead of full hypnogram segments. Full hypnogram segments require an additional RPC and
migration, which is scope creep for Phase 4.

### 3.4 States

| State | Behavior |
|-------|----------|
| Full data | All fields rendered |
| No sleep data | Card hidden or shows "No sleep data" empty state |
| Quality only (no stages) | Quality score shown, hypnogram hidden, simplified breakdown |
| Cold start | "Gathering baseline — need 3+ nights" message |

### 3.5 Placement

In `today_screen.dart`, inside the "Apple Health" section, replacing the sleep `_SignalMetric` at
line ~653. The card expands the current single-number display into the architecture visualization.

### Verification

```sh
./scripts/flutter.sh test test/widgets/sleep_architecture_card_test.dart
```

---

## Step 4: ReadinessStrip Redesign

### 4.1 Current vs. Target

| Current | Target |
|---------|--------|
| 3 tiles: Check-in, Training, Nutrition | 3 cards: Recovery, Training, Nutrition |
| Backed by subjective check-in booleans | Backed by computed scores |
| Opens bottom sheet with text | Shows real scored data inline |
| `_ReadinessTile` in a `Row` | `TracendCard`-style strips in a `Column` or horizontal scroll |

### 4.2 Recovery Card

- RecoveryRing at smaller scale (ring 120pt diameter, score in `titleLarge`)
- Band label: "Green: Within baseline" / "Yellow: Moderate" / "Red: Below baseline"
- Driver strip: compact 3-chip row (HRV, RHR, Sleep z-scores)
- Tap opens full RecoveryRing detail sheet

### 4.3 Training Card

- TrainingLoadGauge at compact scale (120pt wide bar)
- ACWR value + zone label
- Strain value
- Monotony badge (only when > 2.0, indicating repetitive training)
- Tap navigates to Train tab

### 4.4 Nutrition Card

- Macro adherence as filled progress bar (amber fill, 65% shown as "1,547 of 2,380 kcal")
- Calorie adherence %
- Protein sub-marker on the progress bar
- Tap navigates to Nutrition tab

### 4.5 Implementation

Replace `_ReadinessStrip` and `_ReadinessTile` with `_ComputedReadinessStrip` containing 3
`_ReadinessMetricCard` widgets. Each card is a `TracendCard` (compact, non-raised) with the
corresponding metric visualization.

### Verification

Existing Today screen widget tests must be updated (readiness tile assertions change). Widget
test for the new strip renders at 375pt, 390pt, and 2× accessibility text scaling.

---

## Step 5: TrainingLoadGauge Widget

### 5.1 Visual Spec

```
┌──────────────────────────────────────────┐
│  TRAINING LOAD         ACWR: 1.15        │  ← header
│                                          │
│  ┌────────────────●─────────────────────┐│
│  │ ████████████████░░░░░░░░░░░░░░░░░░░ ││  ← horizontal bar
│  │ 0.5    0.8    1.0    1.3    1.5     ││     colored zone backgrounds
│  └──────────────────────────────────────┘│
│  Low risk    Optimal   Elevated   Danger  │  ← zone labels
│                                          │
│  Daily Strain: 42.0                      │
│  Monotony: 1.8 (varied)                  │
└──────────────────────────────────────────┘
```

- Horizontal `Stack` or `CustomPaint`
- Width: 100% of container, height: 16pt bar + 12pt zone labels below
- Colored zones as background `Container`s:
  - 0.0–0.8: `borderSubtle` (undertraining, gray)
  - 0.8–1.3: `stateStable` at 15% opacity (optimal, green)
  - 1.3–1.5: `stateAttention` at 15% opacity (elevated, amber)
  - 1.5+: `stateDanger` at 15% opacity (danger, red)
- Needle/indicator: `actionPrimary` rounded vertical bar (4pt wide, 20pt tall) at the ACWR position
- ACWR label: `titleMedium` with tabular figures, right-aligned in header
- Zone labels below: `labelMedium`, `textSecondary`
- Daily strain: `MetricRow` with value + unit
- Monotony: shown only when > 2.0 (training is repetitively unvaried), with attention color

### 5.2 API

```dart
class TrainingLoadGauge extends StatelessWidget {
  final double? acwr;             // null = no data
  final double dailyStrain;
  final double? trainingMonotony;
}
```

### 5.3 States

| State | Behavior |
|-------|----------|
| ACWR in optimal (0.8–1.3) | Green zone highlighted, "Optimal load" label |
| ACWR elevated (1.3–1.5) | Amber zone, "Elevated — monitor recovery" |
| ACWR dangerous (>1.5) | Red zone, "High risk — consider deload" |
| ACWR low (<0.8) | Gray zone, "Undertraining — increase load" |
| ACWR null (no data) | Full gauge grayed out, "Need 2+ sessions for ACWR" |
| Monotony > 2.0 | Warning text: "Training pattern is repetitive" |

### 5.4 Placement

In `train_screen.dart`, after `_WeekdayStrip` (line ~251) and before the repair/reconciliation
cards. Also used in the redesigned Today ReadinessStrip (compact variant).

### Verification

```sh
./scripts/flutter.sh test test/widgets/training_load_gauge_test.dart
```

Test ACWR values: 0.6, 1.15, 1.4, 1.6, null. Test monotony warning at 2.5.

---

## Step 6: Weight Trend Line

### 6.1 Visual Spec

```
  Weight (kg)
  80 │
     │   ••           ← raw measurements (dots, textSecondary)
  79 │  •   •••  
     │ •    •   ••    ← 7d trend (dashed, stateAttention, light)
  78 │•              
     │─────────────── ← 28d trend (solid, actionPrimary, 2pt)
  77 │
     └──┬──┬──┬──┬──┬──
        M  T  W  T  F  S
```

Overlay on the existing `EvidenceTrendChart`:

- Raw weight measurements: existing rendering (dots with connecting lines)
- 7-day trend line: dashed line at `stateAttention` color, 42% alpha, 1pt stroke
- 28-day trend line: solid line at `actionPrimary` color, 2pt stroke
- Both trend lines extend edge-to-edge across the date range
- A key/legend row below the chart: 2 colored dots with "7-day trend" and "28-day trend" labels

### 6.2 Implementation

Extend `_EvidenceTrendPainter` with a new paint pass for trend line overlays OR add a second
`CustomPaint` widget stacked on top.

**Approach: Add trend line parameters to `EvidenceTrendChart`.**

```dart
class EvidenceTrendChart extends StatelessWidget {
  // ... existing parameters ...
  final List<DatedTrendValue>? trend7d;   // NEW
  final List<DatedTrendValue>? trend28d;  // NEW
}
```

Trend lines are computed from the same measurements list in `_TrendCard`:
- 7-day: OLS regression over last 7 measurements before each date
- 28-day: OLS regression over last 28 measurements before each date
- Computation in pure Dart (deterministic, per architecture rules)
- Only rendered when ≥ 3 measurements exist in the window

### 6.3 Placement

In `progress_screen.dart`, inside `_TrendCard` (line ~549-604), the existing `EvidenceTrendChart`
at line ~587 receives the calculated trend line data.

### Verification

```sh
./scripts/flutter.sh test test/widgets/weight_trend_line_test.dart
```

Golden test: chart with raw dots + both trend lines vs chart with dots only (no trend data).

---

## Step 7: MetricSparkline Widget

### 7.1 Visual Spec

```
HRV   58ms  ───╮╭───────╯╰──  ← 44×16pt inline, 7-day trend
```

- 44pt wide × 16pt tall inline sparkline
- Shows 7-day trend of a single metric
- No axes, no grid, no labels — pure trend shape
- `CustomPainter` with `Canvas.drawPath` using quadratic bezier smoothing
- Line color: `actionPrimary`, 1pt stroke
- Fill below line: `actionPrimary` at 8% opacity
- Current value: `actionPrimary`, last data point with 3pt dot
- Metric label: 13px `labelMedium`, tabular figures
- Unit: 11px `labelMedium`, `textSecondary`
- Used inline in lists/rows — never standalone

### 7.2 Data Source

**No time-series RPC exists yet.** To render sparklines, we need one of:

| Option | Effort | Risk |
|--------|--------|------|
| A. New RPC `get_my_metric_series` returning `[{date, value}]` from `daily_computed_metrics.scores_jsonb` | Medium | New migration + RPC |
| B. Direct Flutter query against `daily_computed_metrics` (RLS permits owner SELECT) | Low | No migration, but adds Flutter→DB coupling |
| C. Wire into existing `HealthHistory.days` data (already fetched for Today health section) | Low | Only covers HealthKit metrics (HRV, RHR, sleep), not computed scores |

**Decision: Option C for MVP Phase 4.** Use `HealthDay` data already flowing into Today screen:
- HRV SDNN: `healthDay.hrvSdnnMs` over the last 7 `HealthHistory.days`
- Resting HR: `healthDay.restingHeartRateBpm` over the last 7 days
- Sleep minutes: `healthDay.sleepMinutes` over the last 7 days
- Weight: `bodyMeasurements.weightKg` over the last 8 entries (already displayed)

This avoids new RPCs/migrations for Phase 4. A time-series RPC for computed scores can be Phase
4.1 or Phase 5.

### 7.3 API

```dart
class MetricSparkline extends StatelessWidget {
  final String label;        // "HRV"
  final String? currentValue; // "58"
  final String? unit;        // "ms"
  final List<double> values; // last 7 values, oldest first
  final double? average;     // optional average line
}
```

### 7.4 Placement

Inline with existing `_SignalMetric` rows in Today's "What matters today" section (lines ~630-670).
Each metric row gets a trailing sparkline showing 7-day trend.

### Verification

```sh
./scripts/flutter.sh test test/widgets/metric_sparkline_test.dart
```

Test: rising trend, falling trend, flat trend, single value (dot only), empty list (hidden).

---

## Step 8: Screen Integration

### 8.1 Today Screen Changes

File: `lib/features/today/today_screen.dart`

1. **Pass computed metrics through:** `DailyBrief.computed` available as `brief.computed`
2. **RecoveryRing:** Insert after `_TodayHeroBackdrop` (line ~135), before `_ReadinessStrip`
   ```dart
   if (brief.computed != null)
     RecoveryRing(
       recoveryScore: brief.computed!.recoveryScore ?? 0,
       drivers: brief.computed!.recoveryBreakdown,
       confidence: brief.computed!.dataConfidence,
     ),
   ```
3. **Redesigned ReadinessStrip:** Replace `_ReadinessStrip` with `_ComputedReadinessStrip` that
   renders Recovery/Training/Nutrition cards using computed scores
4. **SleepArchitectureCard:** In the Apple Health section, replace the sleep `_SignalMetric`
   (line ~653) with the card, using `latestHealthDay` data + computed quality scores
5. **MetricSparklines:** Add to the 3-4 `_SignalMetric` items in "What matters today"
6. **Null/non-computed fallback:** When `brief.computed` is null (pre-feature-engine data), keep
   existing readiness tiles and current signal display

### 8.2 Train Screen Changes

File: `lib/features/train/train_screen.dart`

1. **TrainingLoadGauge:** Insert after `_WeekdayStrip` (line ~251), shown for any selected day
2. Uses `hub` data (needs ACWR field — or fetch from daily_brief if on same day)
3. For non-today days: ACWR may not be computed per-day; show "Today only" label or fetch from
   a daily-computed-metrics query

**Decision: Scope Limit.** ACWR is computed as a point-in-time metric. For the Train screen, show
the gauge only when viewing today (the current date), fed from a separate brief load or a
lightweight `get_my_daily_scores(target_date)` RPC. For past days, show a placeholder with "Data
available for today only." This avoids per-day ACWR recomputation which is Phase 2 algorithm
territory already done, but per-day retrieval from `daily_computed_metrics` table added.

**Implementation:** `WorkoutRepository` or `TrainingHubRepository` gains a
`Future<DailyComputedScores?> getScores(DateTime date)` method that queries
`daily_computed_metrics` via RPC or direct table access.

### 8.3 Progress Screen Changes

File: `lib/features/progress/progress_screen.dart`

1. **Weight Trend Line:** In `_TrendCard` (line ~549), compute 7d/28d trend from measurements and
   pass to `EvidenceTrendChart` via new optional parameters
2. Trend computation function in a new utility: `lib/features/progress/weight_trend.dart` — pure
   Dart OLS regression, no AI, no backend call

---

## Step 9: Fixtures, Tests, Golden Files

### Contract Test Updates

- `test/contract/fixtures/daily_brief_v1_1.json`: already has `computed` block — verify it's valid
- `test/contract/daily_brief_contract_test.dart`: add assertion for `computed` field parsing
- New fixture: `test/contract/fixtures/daily_brief_v1_1_no_computed.json` (pre-engine fixture for
  backward-compat testing)

### Widget Tests

| Test file | Widget | Scenarios |
|-----------|--------|-----------|
| `test/features/computed_metrics_test.dart` | ComputedMetrics model | Full, empty, partial, null |
| `test/widgets/recovery_ring_test.dart` | RecoveryRing | Green/yellow/red bands, cold start, animation |
| `test/widgets/sleep_architecture_card_test.dart` | SleepArchitectureCard | Full data, no stages, no sleep |
| `test/widgets/training_load_gauge_test.dart` | TrainingLoadGauge | All ACWR zones, null, monotony warning |
| `test/widgets/weight_trend_line_test.dart` | EvidenceTrendChart + trend | With/without trend lines, golden |
| `test/widgets/metric_sparkline_test.dart` | MetricSparkline | Rising, falling, flat, single, empty |
| `test/widgets/computed_readiness_strip_test.dart` | ReadinessStrip redesign | 3 cards render, null computed fallback |

### Golden Files

- RecoveryRing: score 85 (green), score 50 (yellow), score 20 (red), null (cold start)
- SleepArchitectureCard: full 4-stage bar, no stages, no data
- TrainingLoadGauge: ACWR=1.15, ACWR=1.6, ACWR=null
- Weight Trend Line: chart with trend lines vs without
- MetricSparkline: rising, falling, flat trends

All golden files at `test/goldens/phase4/` for 390×844pt in both light and dark modes.

### Accessibility

- All CustomPainters expose `Semantics` nodes with meaningful labels
- Tabular figures throughout (score values, dates, strain, ACWR)
- Minimum 44×44pt touch targets on interactive elements
- Text scaling up to 2× tested in widget tests

---

## Step 10: Verification Gate

### Per-Widget Iteration

For each widget, run:

```sh
./scripts/flutter.sh test test/widgets/<widget>_test.dart  # new widget tests
./scripts/flutter.sh test                                   # full suite — must stay green
./scripts/flutter.sh analyze                                # clean analysis
./scripts/flutter.sh format --set-exit-if-changed lib test  # formatted
```

### Full Gate

```sh
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/flutter.sh build ios --release --no-codesign
```

### Design Review

Use `/impeccable critique TodayScreen` and `/impeccable critique TrainScreen` to UX-review the
integrated results before final commit.

---

## Deployment Order

1. `ComputedMetrics` model + `DailyBrief` update (data plumbing)
2. `RecoveryRing` widget + widget tests + golden files
3. `SleepArchitectureCard` widget + widget tests + golden files
4. `TrainingLoadGauge` widget + widget tests + golden files
5. `MetricSparkline` widget + widget tests
6. `ReadinessStrip` redesign
7. Weight trend line augmentation on `EvidenceTrendChart`
8. Screen integration (Today → Train → Progress)
9. Contract test updates
10. Final gate + iPhone build

All steps are pure Flutter — no database migration, no Edge Function change, no RPC change
(except possibly a lightweight `get_my_daily_scores` if needed for Train ACWR).

---

## Skills Usage

| Step | Impeccable | Taste-Skill |
|------|-----------|-------------|
| Widget design | `/impeccable craft RecoveryRing` etc. | `stitch-design-taste` for Stitch alignment |
| Screen integration | `/impeccable shape TodayScreen` | `redesign-existing-projects` for layout audit |
| UI review | `/impeccable critique TodayScreen` | — |
| Boring fix | `/impeccable bolder TodayScreen` | `design-taste-frontend` for anti-slop guard |
| Anti-pattern scan | `npx impeccable detect lib/` | — |
| Final polish | `/impeccable polish` | — |
| Code hardening | `/impeccable harden` | — |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Stitch designs show outdated placeholder data | Follow Stitch visual language, not literal data values. Our DESIGN.md + tokens are authoritative. |
| No sleep stage segments for hypnogram | Use aggregated stage proportions for Phase 4; full hypnogram deferred. |
| No time-series RPC for sparklines | Use existing `HealthDay` data for MVP; time-series RPC in follow-up. |
| ACWR only computable for today in Train | Fetch from `daily_computed_metrics` for today; placeholder for past days. |
| Golden file drift on CI | Specify exact font/theme in test environment; use `tester.binding.setSurfaceSize(390, 844)`. |
| Performance with many CustomPainters | Profile with Flutter DevTools; each painter is lightweight (single-path draw). |

---

## What Wait for Phase 5

- Spline Sans + IBM Plex Mono font imports (OTF files + pubspec)
- TrajectoryLens redesign (animated Bezier path replacing chip list)
- Full screen layout redesigns (Today, Train, Nutrition, Progress, Coach)
- New components: EvidenceAccordion, CoachInsightCard, DatePillStrip, TargetsGrid, WorkoutModeSheet
- Screen-level visual overhaul to match Stitch layouts exactly
- My AI Usage detail screen
