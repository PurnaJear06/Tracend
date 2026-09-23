# Feature Engine & UI Alignment — Implementation Plan

**Created:** 2026-07-22
**Trigger:** NOOP reverse-engineering audit + Tracend architecture gap analysis
**Scope:** Deterministic feature engine + HealthKit-to-Supabase algorithms + UI/design alignment

---

## Problem Statement

Tracend's coaching pipeline (HealthKit sync → policy evaluation → AI provider call → decision) is complete, but the **deterministic feature engine** is a thin check-in validator. The AI receives raw values and boolean presence flags instead of computed scores, baselines, and trends. ARCHITECTURE.md §5 specifies calculations that don't yet exist. AI_SAFETY_SPEC.md §6 defines change-eligibility rules that aren't enforced.

## What Changes

```
BEFORE: HealthKit → raw values → AI sees "is data present?" (boolean)
AFTER:  HealthKit → raw values → Feature Engine (baselines, z-scores, composites) → AI sees scores, trends, confidence
```

New computed outputs the AI will receive:
- Recovery score (0-100) with driver breakdown (HRV z, RHR z, sleep z)
- Sleep quality score with efficiency, architecture, debt
- Training load: ACWR, monotony, daily strain
- Weight trend: 7-day / 28-day regression
- Macro adherence against targets
- Data confidence tier

---

## Phase 1: Database Foundation

### New Tables

**`user_baselines`** — per-user, per-metric EWMA baselines (hrv_sdnn, resting_hr, sleep_minutes, weight_kg, daily_strain)

**`daily_computed_metrics`** — one row per user per day: recovery_score, sleep_quality_score, daily_strain, acwr, weight_trend, adherence_pct, data_confidence + driver breakdowns

**`metric_baseline_history`** — immutable per-observation z-scores for audit

### Migration

`20260723000000_feature_engine_foundation.sql` — additive only, no renames/drops

### Enriched Feature Snapshots

`prepare_daily_coaching` now includes in `feature_snapshots.features`:
- Recovery: score, band, confidence, driver z-scores
- Sleep: quality_score, efficiency, debt_minutes
- Training load: strain, ACWR, monotony
- Weight: 7d/28d trend
- Nutrition: calorie/protein adherence
- Data confidence: coverage %, days of data per metric

### Change Eligibility

`evaluate_change_eligibility(target_user_id, change_domain)` — enforces AI_SAFETY_SPEC.md §6 rules:
- Training change: 2 comparable sessions OR 2 weeks adherence evidence
- Nutrition change: 14 days weight + 80% adherence + trend

---

## Phase 2: Algorithm Implementation (PostgreSQL)

### 2.1 Baselines — Winsorized EWMA
- Midpoint `λ = 1 - 0.5^(1/half_life_days)` (default half-life: 14 nights)
- Winsor clamping: ±3×spread, hard outlier >5×spread
- Early-life anti-anchoring: faster half-life (3 days) for first 8 nights
- `compute_baseline(user_id, metric_key, observations[], dates[], half_life, floor_spread, epoch)`

### 2.2 Recovery Score
```
z_composite = Σ(term_z × weight) / Σ(weight)
  HRV (SDNN):    weight 0.55 (higher = better)
  Resting HR:    weight 0.20 (lower = better)
  Sleep quality: weight 0.15 (higher = better)
  Resp rate:     weight 0.05 (lower = better)
  Prev strain:   weight 0.05 (lower = better)

Recovery = 100 / (1 + exp(-1.6 × (z_composite + 0.2)))
Bands: Red 0-34, Yellow 34-67, Green 67-100
Population mean anchor: z=0 → ~58%
Cold start: ≥4 nights HRV + RHR required
```
Caveat: HealthKit provides SDNN, not RMSSD. Correlated but not identical. Document clearly.

### 2.3 Sleep Quality
```
Score = 0.50×duration + 0.20×efficiency + 0.20×restorative + 0.10×consistency
Uses HealthKit-supplied sleep stages directly (does NOT re-derive stages)
Sleep debt = target_minutes - avg_last_7d_sleep
```

### 2.4 Training Load (sRPE + ACWR)
```
Session Strain = session_effort (RPE 1-10) × duration_minutes / 10
Daily Strain = Σ(session_strain)
ACWR = 7d_avg / 28d_avg  (sweet spot 0.8-1.3, danger >1.5)
Monotony = mean(7d_strain) / stddev(7d_strain)
```
Uses existing `workout_sessions.session_effort` — already collected!

### 2.5 Weight Trend
```
OLS regression slope over 7-day and 28-day windows
Requires ≥3 observations in window
```

### 2.6 Macro Adherence
```
calorie_adherence_7d = confirmed_kcal / target_kcal × 100
protein_adherence_7d = confirmed_protein_g / target_protein_g × 100
```

### 2.7 Orchestrator
`compute_daily_metrics(user_id, date, timezone)` → runs all above, upserts into daily_computed_metrics
Called by: prepare_daily_coaching, prepare_coach_chat, health-sync (post-sync trigger), nightly cron

---

## Phase 3: Edge Functions

### coach-decide — Enriched Context
New evidence codes backed by computed values:
- RECOVERY_WITHIN_BASELINE → actual z-score threshold
- RECOVERY_BELOW_BASELINE → HRV z < -1.0
- SLEEP_QUALITY_GOOD / SLEEP_QUALITY_POOR
- TRAINING_LOAD_ELEVATED → ACWR > 1.5
- NUTRITION_ON_TRACK / NUTRITION_BEHIND
- WEIGHT_TRENDING_DOWN / WEIGHT_TRENDING_UP

### coach-chat — Extended Context
Add latest daily_computed_metrics + user_baselines summary to context

### Cron: Nightly Baseline Recompute
`SELECT cron.schedule('nightly-feature-engine', '0 6 * * *', ...)`

---

## Phase 4: Flutter UI — Computed Metrics

### RecoveryRing (Today)
CustomPainter: 240° open arc, SweepGradient green→yellow→red, centered score, driver chips below

### SleepArchitectureCard (Today)
Horizontal stacked bar hypnogram (HealthKit stages), quality score, efficiency, debt

### ReadinessStrip Redesign (Today)
3 cards: Recovery (score + band + driver), Training (strain + ACWR), Nutrition (adherence %)

### TrainingLoadGauge (Train)
Horizontal bar: ACWR position on 0.8-1.5 scale, colored zones

### Weight Trend Line (Progress)
7-day + 28-day regression lines on existing weight chart

### MetricSparkline (Evidence Rows)
44×16pt inline sparklines for HRV, RHR, sleep, weight — 7-day trend

---

## Phase 5: Design System Alignment

### Typography
Add Spline Sans (decision headlines) and IBM Plex Mono (data values) — both SIL Open Font License

### New Components (Priority Order)
P0: RecoveryRing, TrajectoryLens (animated path), SleepArchitectureCard, TrainingLoadGauge
P1: MetricSparkline, IntensityBar, EvidenceAccordion, CoachInsightCard
P2: DatePillStrip, TargetsGrid, WorkoutModeSheet
P3: WeeklyScheduleStrip, SessionMap

### Trajectory Lens
Replace simplified chip-based signal rail with Stitch design animated SVG path:
CustomPainter + AnimationController, Bezier curves between evidence points, 1.5s draw-in animation, terminal glow-dot

### Screen Updates
- **Today:** TrajectoryLens top, RecoveryRing, SleepArchitectureCard, TrainingLoadGauge, design-aligned cards
- **Train:** WeeklyScheduleStrip, TrainingLoadGauge, performance progression cards
- **Nutrition:** DatePillStrip, TargetsGrid, recommendation card, CoachInsightCard
- **Progress:** EvidenceCardsGrid, weight trend overlay, trajectory card
- **Coach:** EvidenceAccordion, styled composer, suggestion pills

### New Screens
- **My AI Usage:** per AI_USAGE_PROMPT.md spec
- **Welcome screens** (post-MVP, needs Apple Sign-in)

---

## Phase 6: Docs & Testing

### New Docs
- `docs/ALGORITHMS.md` — published formulas with references (Plews/Buchheit, Task Force 1996, Edwards/Banister, Gabbett, Foster, Tanaka)
- `docs/adr/0010-deterministic-feature-engine.md`

### Updated Docs
- ARCHITECTURE.md §5, DATA_MODEL.md, AI_SAFETY_SPEC.md §6, DESIGN_SYSTEM.md §5
- UX_FLOWS.md, TESTING_STRATEGY.md, IMPLEMENTATION_ROADMAP.md, PROGRESS_CONTEXT.md

### Tests
- Algorithm regression: known inputs → exact expected scores
- pgTAP: baseline computation, recovery bands, ACWR, change eligibility, cold start, cross-user RLS
- Contract fixtures: updated RPC response shapes
- Golden files: widget rendering at multiple score values

---

## Deployment Order

1. DB migration (additive-only tables + functions)
2. SQL functions (baseline, recovery, sleep, load, weight, adherence, orchestrator)
3. Modified prepare_daily_coaching (now calls compute_daily_metrics)
4. Modified coach-decide Edge Function (enriched context)
5. Modified coach-chat Edge Function (extended context)
6. Flutter UI updates (new widgets, screen changes)
7. Cron job (nightly recompute)

**Between each step:** verify pre-deploy gate passes, existing app still works.

---

## Effort Estimate

| Phase | Days |
|-------|------|
| 1: Database | 3-4 |
| 2: Algorithms | 5-7 |
| 3: Edge Functions | 2-3 |
| 4: UI Computed Metrics | 3-4 |
| 5: UI Design Alignment | 5-7 |
| 6: Docs & Testing | 2-3 |
| **Total** | **20-28 days** |

---

## Architecture Rule Compliance

All 12 AGENTS.md rules verified. Deterministic calculations own scoring. Model output stays interpretation-only. RLS on all new tables. No secrets in Flutter. Forward-compatible migrations only.
