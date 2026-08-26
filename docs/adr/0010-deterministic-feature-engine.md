# ADR 0010: Deterministic Feature Engine

**Date:** 2026-07-24 **Status:** Accepted

## Context

Tracend's coaching pipeline (HealthKit sync → policy evaluation → AI provider call → decision) was
complete, but the AI received raw values and boolean presence flags instead of computed scores,
baselines, and trends. ARCHITECTURE.md §5 specified deterministic calculations that didn't yet exist.
AI_SAFETY_SPEC.md §6 defined change-eligibility rules that weren't enforced.

The gap meant the AI model was responsible for interpreting raw health data — something it's not
designed or validated to do deterministically. Scores like recovery, training load, and sleep quality
should be computed once, consistently, and passed as structured input.

## Decision

Implement a deterministic Feature Engine in PostgreSQL, following the architecture rule that
"deterministic code calculates trends, adherence, totals, baselines, and policy eligibility" and
"model output is interpretation and proposal, not authoritative calculation."

### Phase 1: Database Foundation (deployed)

Two new tables (both forced RLS):
- `user_baselines` — Winsorized EWMA per metric with confidence tier
- `metric_baseline_history` — immutable per-observation audit trail

Six SQL functions:
- `compute_winsorized_ewma` — core EWMA with Winsor outlier clamping, anti-anchoring half-life
  (3 days first 8 obs → 14 days)
- `compute_user_baselines` — pulls daily_health_summaries, computes per-metric EWMA
- `compute_daily_metrics` — orchestrator returning full JSONB
- `compute_recovery_score` — z-score composite (HRV 0.55, RHR -0.20, sleep 0.15, resp 0.05, strain
  0.05) → logistic(0-100)
- `compute_sleep_quality` — duration 0.50 + efficiency 0.20 + restorative 0.20 + consistency 0.10
- `evaluate_change_eligibility` — training + nutrition gates per AI_SAFETY_SPEC §6

Enriched `prepare_daily_coaching` features JSONB with `baselines`, `scores`, and `eligibility`.

### Algorithm Choices

1. **Winsorized EWMA over simple MA:** Outlier-resistant but not requiring ARIMA/PACF-tuning. The
   14-night half-life matches the literature convention for HRV baselines (Plews & Buchheit, 2017).

2. **Logistic transform for recovery:** Maps unbounded z-composite to 0-100 band. Constants (k=1.6,
   offset=-0.2) anchor population mean z=0 to ~58% — slightly above mid-range since users are
   training, not rehab. *Superseded 2026-08-25 (recovery honesty): the offset is removed and
   z=0 maps to exactly 50 — the offset fabricated ~58 on days with no usable data. See
   `supabase/migrations/20260825120000_recovery_honesty.sql`.*

3. **HRV via SDNN:** HealthKit provides SDNN, not RMSSD. Correlated but not identical. Documented
   limitation; switch to RMSSD if HealthKit adds support.

4. **Weight via OLS slope:** REGR_SLOPE over 7/28-day windows. Minimum 3 observations. Simpler and
   more interpretable than Holt-Winters for this sample density.

### Remaining Phases

- Phase 2: Migrate algorithm internals to domain-tested implementations, add performance test
  fixtures
- Phase 3: Enrich coach-decide and coach-chat with computed scores as evidence
- Phase 4: Flutter UI — RecoveryRing, SleepArchitectureCard, TrainingLoadGauge, WeightTrend
- Phase 5: Design system alignment — Spline Sans + IBM Plex Mono fonts, new components
- Phase 6: Docs (ALGORITHMS.md) + golden/evaluation tests

## Consequences

- AI decisions are now backed by deterministically computed features, not raw booleans
- Recovery score, sleep quality, and training load are available as evidence codes in coach-decide
- Change eligibility gates are enforced server-side, not by model prompt
- Baseline history is auditable: every observation has a z-score, lambda, and Winsorization flag
- Cold-start confidence tiers prevent unreliable scores during early adoption
- Nostalgia risk: early-life anti-anchoring prevents the baseline from staying anchored to the first
  few observations
