# Phase 1 — Feature Engine: Database Foundation

**Parent plan:** `feature-engine-and-ui-alignment.md`
**Created:** 2026-07-24
**Effort:** 3-4 days

---

## Objective

Add the deterministic feature engine's database layer: two new tables for baseline tracking, six scoring functions in PostgreSQL, enriched `prepare_daily_coaching` snapshots, change eligibility gates, and a nightly cron sweep.

## What Changes

```
BEFORE: prepare_daily_coaching → features = { check_in (boolean presence), health_present_types }
AFTER:  prepare_daily_coaching → features = { baselines, scores, eligibility, + existing data }
```

The AI receives computed scores and trends instead of raw booleans. Eligibility rules from AI_SAFETY_SPEC.md §6 are enforced deterministically.

## 3 New Migrations

| # | File | Purpose |
|---|------|---------|
| 1 | `20260724000000_feature_engine_tables.sql` | Creates `user_baselines` + `metric_baseline_history` tables with RLS |
| 2 | `20260724000001_feature_engine_baselines.sql` | 6 SQL functions: EWMA, baselines, scores, eligibility |
| 3 | `20260724000002_feature_engine_enrich_coaching.sql` | Alters `prepare_daily_coaching`, bumps constraints + RPC versions, adds cron |

## New Tables

### `user_baselines`
Per-user, per-metric Winsorized EWMA baselines. One row per metric per user, upserted.

- `metric_name`: `hrv_sdnn_ms`, `resting_hr_bpm`, `sleep_minutes`, `weight_kg`
- `baseline_value` (numeric): current EWMA
- `spread` (numeric): MAD spread for z-score denominator
- `confidence`: `cold_start`, `low`, `medium`, `high`
- Enforced: `UNIQUE (user_id, metric_name)`, `UNIQUE (id, user_id)`

### `metric_baseline_history`
Immutable per-observation audit trail. Append-only via RPC.

- `observation_date`, `raw_value`, `was_winsorized`, `was_outlier_rejected`
- `lambda_used`: captures anti-anchoring transition
- `prior_baseline_id`: linked list for traceability

## 6 New SQL Functions

| Function | Signature | Purpose |
|---|---|---|
| `compute_winsorized_ewma` | `(values numeric[], n_obs int) → numeric` | Core EWMA with Winsor outlier clamping, anti-anchoring. IMMUTABLE. |
| `compute_user_baselines` | `(user_id uuid, date date) → void` | Pulls daily_health_summaries, computes EWMA per metric, upserts user_baselines + inserts history |
| `compute_daily_metrics` | `(user_id uuid, date date, tz text) → jsonb` | Runs all scorers, returns full metrics JSONB |
| `compute_recovery_score` | internal | z-score composite (HRV 0.55, RHR -0.20, sleep 0.15, resp 0.05, strain 0.05) → logistic(0-100) |
| `compute_sleep_quality` | internal | Duration 0.50 + efficiency 0.20 + restorative 0.20 + consistency 0.10 |
| `evaluate_change_eligibility` | `(user_id uuid, snapshot_id uuid, version text) → jsonb` | Training + nutrition change gates per AI_SAFETY_SPEC §6 |

## Algorithms

### Recovery Score
```
z_composite = 0.55×hrv_z + (-0.20)×rhr_z + 0.15×sleep_z + 0.05×resp_z + 0.05×prev_strain_z
score = 100 / (1 + exp(-1.6 × (z_composite + 0.2)))
```
- Red 0-34, Yellow 34-67, Green 67-100
- Cold start: ≥4 nights HRV + RHR required
- Caveat: HealthKit provides SDNN, not RMSSD. Correlated, not identical. Documented.

### Winsorized EWMA Baseline
```
λ = 1 − 0.5^(1/half_life)      // half_life = 3 days for first 8 obs, then 14
spread = 1.4826 × MAD           // MAD via percentile_cont(0.5)
hard_reject: |x| > 5×spread    → skip completely
winsorize:   |x| > 3×spread    → clamp to boundary
z_i = λ × winsorized + (1−λ) × z_{i−1}
```

### ACWR & Monotony
```
acwr = AVG(strain, 7d) / AVG(strain, 28d)
monotony = AVG(strain, 7d) / STDDEV_SAMP(strain, 7d)
strain = session_effort × duration_minutes / 10
```

### Weight Trend
```
OLS slope via REGR_SLOPE(weight_kg, epoch_days) over 7d and 28d windows
Requires ≥3 observations per window
```

## Constraint Alterations

| Constraint | Old | New |
|---|---|---|
| `feature_snapshots.schema_version` | `= '1.0'` | `IN ('1.0', '2.0')` |
| `policy_evaluations.policy_version` | `= 'daily-v1'` | `IN ('daily-v1', 'eligibility-v1')` |

## RPC Schema Version Bumps

| RPC | Current | New |
|---|---|---|
| `get_my_training_hub` | `1.3` | `1.4` |
| `get_my_daily_brief` | `1.0` | `1.1` |

## Enriched `prepare_daily_coaching` Features JSONB

```json
{
  "baselines": {
    "hrv_sdnn_ms": {"ewma": 45.2, "spread": 12.1, "n_obs": 14, "confidence": "medium"},
    "resting_hr_bpm": {"ewma": 58.3, "spread": 4.2, "n_obs": 21, "confidence": "high"},
    "sleep_minutes": {"ewma": 420, "spread": 45, "n_obs": 14, "confidence": "medium"},
    "weight_kg": {"ewma": 78.5, "spread": 0.6, "n_obs": 28, "confidence": "high"}
  },
  "scores": {
    "recovery": 62,
    "recovery_breakdown": {"hrv_z": 0.4, "rhr_z": -0.3, "sleep_z": 0.1, "respiration_z": 0.0, "prev_strain_z": -0.5},
    "sleep_quality": 71,
    "acwr": 1.15,
    "training_monotony": 1.8,
    "weight_trend_7d_kg_per_week": -0.15,
    "weight_trend_28d_kg_per_week": -0.08,
    "macro_adherence_pct": 85.3
  },
  "eligibility": {
    "training_change": {"eligible": false, "reason": "insufficient_comparable_sessions", "detail": "1 comparable session, need 2"},
    "nutrition_change": {"eligible": false, "reason": "insufficient_weight_data", "detail": "10 days weight data, need 14"}
  },
  "data_confidence": "medium",
  "check_in": {...},
  "health_present_types": [...],
  "active_plan_version_id": "..."
}
```

## Nightly Cron

```sql
SELECT cron.schedule(
  'tracend-recompute-daily-metrics',
  '0 6 * * *',
  'SELECT public.recompute_stale_metrics()'
);
```

`recompute_stale_metrics()` finds yesterday's daily_health_summaries without an enriched snapshot, runs `compute_daily_metrics`, upserts. Idempotent.

## pgTAP Tests

File: `supabase/tests/database/feature_engine_baseline_test.sql`

1. EWMA with normal data → expected value
2. EWMA with outlier → Winsorized correctly
3. EWMA cold start (<3 obs) → returns NULL
4. Recovery score at known inputs → exact expected score
5. ACWR with 28 days of strain → exact ratio
6. Change eligibility gates → expected boolean outcomes
7. Cross-user RLS on new tables

## Contract Fixtures

| Fixture | Action |
|---|---|
| `test/contract/fixtures/training_hub_v1_4.json` | New — enriched shape |
| `test/contract/fixtures/coach_context_status.json` | Update — new source types |

## Deployment Order

```
1. backup-db.sh
2. db push --dry-run migration 1 (tables)
3. db push --linked migration 1
4. db push --dry-run migration 2 (functions)
5. db push --linked migration 2
6. db push --dry-run migration 3 (enrichment + constraints)
7. db push --linked migration 3
8. pre-deploy.sh (full gate)
```

## What Stays Untouched

- `coach-decide` Edge Function — reads enriched snapshot via existing JSONB field
- `coach-chat` Edge Function — same
- `health-sync` Edge Function — no changes (cron handles missed days)
- All Flutter screens, widgets, services
- All existing tables, columns, RLS policies
- `prepare_daily_coaching` signature and return shape
