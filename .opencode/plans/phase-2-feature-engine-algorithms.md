# Phase 2 — Feature Engine: Algorithm Audit & Verification

**Parent plan:** `feature-engine-and-ui-alignment.md`
**Created:** 2026-07-25
**Branch:** `feature/feature-engine-phase-2` (off `feature/feature-engine`)
**Effort:** 2-3 days

---

## Objective

Audit the Phase 1 SQL functions against the parent plan's algorithm specs, fix discrepancies, add comprehensive regression/edge-case pgTAP tests, document algorithms with literature references, create a `daily_computed_metrics` persistence table, and verify end-to-end on hosted Supabase with real user data.

## What Changes

```
BEFORE: 7 algorithm assertions, spec-vs-code discrepancies, no persistence table, no algorithm docs
AFTER:  45+ algorithm assertions with exact boundary values, spec aligned, daily_computed_metrics
        table, ALGORITHMS.md published, hosted smoke test verified
```

## 1 Migration

| # | File | Purpose |
|---|------|---------|
| 1 | `20260725000000_feature_engine_phase_2_fixes.sql` | Fix algorithm discrepancies + create `daily_computed_metrics` table + add resp rate support + sleep debt |

## 1.1 Algorithm Discrepancy Fixes

### Recovery Score Weights
| Component | Spec | Code (now) | Fix (code →) | Reason |
|-----------|------|------------|-------|--------|
| HRV (SDNN) | 0.55 | 0.55 | No change | Match |
| RHR | 0.20 | **0.25** | **→ 0.20** | Spec is authoritative |
| Sleep | 0.15 | 0.15 | No change | Match |
| Resp rate | 0.05 | **Not implemented** | **→ Add** | Missing component per spec |
| Prev strain | 0.05 | **Always 0** | **→ Compute actual** | Dead code per spec |

### Resp Rate Scoring
- Add `resp_rate_avg_bpm` field to the recovery composite
- Read from `daily_health_summaries.respiratory_rate_bpm` if present
- Z-score against `user_baselines` with new metric `resp_rate_bpm`
- Weight: 0.05 (lower = better, same sign convention as RHR)

### Prev Strain Fix
- Compute previous 7-day average daily strain (not just today)
- Z-score against intra-user strain history
- Weight: 0.05 per spec

### Sleep Quality Formula
| Aspect | Spec | Code (now) | Fix |
|--------|------|------------|-----|
| Duration | 0.50 | z-score based (asymmetric) | **→ 0.50** |
| Efficiency | 0.20 | 0.20 | No change |
| Restorative | 0.20 | 0.20 | No change |
| Consistency | 0.10 | **Not implemented** | **→ Add 7-day stddev** |

Fix: replace `50 + (sleep_z * 15)` with `0.50 * duration_score + 0.20 * efficiency + 0.20 * restorative + 0.10 * consistency` per spec, where:
- `duration_score` = clip(target / actual_or_ewma, 0, 100)
- `efficiency` = (sleep - awake) / sleep × 100
- `restorative` = (deep + REM) / sleep × 100
- `consistency` = 100 - (stddev_7d / mean_7d × 50), floored at 0

### Sleep Debt
- Add to `scores_jsonb`: `sleep_debt_minutes` = target_8h - avg_7d_sleep
- Read target from user preferences or default to 480 minutes

## 1.2 New Table: `daily_computed_metrics`

One row per user per date. Persists `compute_daily_metrics` output.

| Field | Type | Description |
|-------|------|-------------|
| id | uuid PK | |
| user_id | uuid FK | |
| local_date | date | Coaching day |
| recovery_score | integer | 0-100 |
| sleep_quality_score | integer | 0-100 |
| sleep_debt_minutes | integer | Nullable |
| daily_strain | numeric | sRPE total |
| acwr | numeric | Nullable |
| training_monotony | numeric | Nullable |
| weight_trend_7d_kg_per_day | numeric | Nullable |
| weight_trend_28d_kg_per_day | numeric | Nullable |
| macro_adherence_pct | numeric | Nullable |
| data_confidence | text | cold_start/low/medium/high |
| scores_jsonb | jsonb | Full breakdown |
| baseline_snapshot_jsonb | jsonb | Baselines at compute time |
| eligibility_jsonb | jsonb | Change eligibility result |
| computed_at | timestamptz | When computed |
| schema_version | text | '2.0' |

UNIQUE (user_id, local_date). Forced RLS. Read-only for authenticated.

### Upsert Logic
`compute_daily_metrics` now upserts into this table before returning JSONB.
`prepare_daily_coaching` reads from this table (cheaper than recomputing).
`recompute_stale_metrics` cron works against gaps in this table.

## 1.3 New Baseline Metric: `resp_rate_bpm`

Add to `compute_user_baselines` loop. Reads from
`daily_health_summaries.respiratory_rate_bpm`. Same EWMA + Winsor treatment.

## 2. Comprehensive pgTAP Tests

**Current:** 22 tests (7 algorithm assertions)
**Target:** 67 tests (45+ algorithm assertions)
**File:** `supabase/tests/database/feature_engine_phase_2_test.sql`

### 2.1 EWMA (4 → 8 tests)
1. Normal data stays near dataset centre (>)
2. Normal data stays near dataset centre (<)
3. Outlier correctly down-weighted
4. Cold start (<3 obs) returns null
5. **NEW:** 30-observation convergence (converges to true mean within 5%)
6. **NEW:** Anti-anchoring transition at n=8 (lambda switches from 0.206 to 0.048)
7. **NEW:** All-identical values (spread=0 → returns last value)
8. **NEW:** Single extreme outlier in 3-observation series (still produces non-null)

### 2.2 Baselines (7 → 12 tests)
9-15. Existing 7 tests
16. **NEW:** n_observations increments correctly after second compute
17. **NEW:** Confidence transitions: <4 obs → 'low', 4-13 → 'medium', 14+ → 'high'
18. **NEW:** History was_outlier_rejected TRUE for hard outliers
19. **NEW:** History was_winsorized TRUE for boundary-clamped values
20. **NEW:** Lambda captured correctly (0.206 for obs 2-8, 0.048 for obs 9+)

### 2.3 Recovery Score (3 → 10 tests)
21-22. Existing 2 tests
23. **NEW:** Exact score at all z=0 → ~58 (population anchor)
24. **NEW:** Exact score at z_composite = -3 → ~1 (floor)
25. **NEW:** Exact score at z_composite = +3 → ~99 (ceiling)
26. **NEW:** Red band boundary: score < 34 at z = -1.5
27. **NEW:** Yellow-to-Green boundary: score > 67 at z = +0.5
28. **NEW:** HRV-only: when only HRV present, composite uses HRV weight only
29. **NEW:** Resp rate: negative z (lower RR is better, same sign as RHR)
30. **NEW:** Prev strain: 7-day avg properly reduces composite when positive

### 2.4 Sleep Quality (new: 0 → 6 tests)
31. **NEW:** All components nominal → score ~75
32. **NEW:** Efficiency = 0.85, restorative = 0.5, consistency = 0.9 → exact output
33. **NEW:** Duration_score clipped at 100 (oversleeping doesn't give >100)
34. **NEW:** Sleep debt = 480 - avg_7d (displays as minutes under target)
35. **NEW:** No sleep data → sleep_quality NULL
36. **NEW:** Consistency 7-day stddev zero → consistency = 100

### 2.5 ACWR & Monotony (2 → 7 tests)
37-38. Existing 2 tests
39. **NEW:** ACWR exact: avg7=100, avg28=80 → 1.25
40. **NEW:** ACWR danger zone: avg7=150, avg28=80 → 1.875 (>1.5 danger)
41. **NEW:** Monotony zero-variance: all-identical strains → NULL (not infinite)
42. **NEW:** ACWR NULL when <7 days strain history
43. **NEW:** Strain = effort × duration / 10 (formula verification)

### 2.6 Weight Trend (new: 0 → 5 tests)
44. **NEW:** Flat line (all 78.0 kg) → slope ~0
45. **NEW:** 2 observations only → NULL (needs ≥3)
46. **NEW:** Steep loss: -0.5 kg/day over 7 days → slope ~ -0.5
47. **NEW:** R² computed when enough data points
48. **NEW:** HealthKit + manual measurements merged (union deduplication)

### 2.7 Macro Adherence (new: 0 → 5 tests)
49. **NEW:** 7 days at target → ~100%
50. **NEW:** Over-target capped at 200%
51. **NEW:** Zero confirmed meals → NULL
52. **NEW:** No active target plan → NULL
53. **NEW:** 14-day window used per spec

### 2.8 Eligibility Gates (3 → 7 tests)
54-56. Existing 3 tests
57. **NEW:** Training ineligible: 1 comparable session + 50% adherence
58. **NEW:** Training eligible via adherence: 1 session + 85% adherence
59. **NEW:** Nutrition ineligible: 5 days weight data (need 14)
60. **NEW:** Nutrition ineligible: no active target plan

### 2.9 RLS (4 → 6 tests)
61-64. Existing 4 cross-user tests
65. **NEW:** Cross-user isolation on daily_computed_metrics
66. **NEW:** Anonymous access denied on daily_computed_metrics

### 2.10 Persistence (new: 3 tests)
67. **NEW:** compute_daily_metrics upserts into daily_computed_metrics
68. **NEW:** Recompute is idempotent (same input → same output, no duplicate rows)
69. **NEW:** recompute_stale_metrics fills gaps without overwriting

### 2.11 Edge Cases (new: 3 tests)
70. **NEW:** Empty tables (no health summaries, no workouts, no meals) — all NULLs, no crash
71. **NEW:** Timezone boundary — date crossing midnight produces correct local_date
72. **NEW:** Single observation for each metric — no division-by-zero, no crash

## 3. New Documentation: `docs/ALGORITHMS.md`

Published formula reference with literature citations.

### 3.1 Recovery Score
- Full formula with z-composite weights
- Logistic transform derivation (k=1.6, offset=-0.2)
- Band definitions with z-score boundaries
- Literature: Plews & Buchheit (2017) — HRV-guided training
- **SDNN vs RMSSD caveat** — documented limitation

### 3.2 Winsorized EWMA
- Lambda derivation: `1 - 0.5^(1/half_life)`
- Anti-anchoring transition: 3d → 14d at observation 8
- MAD via 1.4826 constant (consistency factor)
- Outlier thresholds: ±3σ Winsor, ±5σ hard reject
- Literature: Hunter (1986) — EWMA control charts

### 3.3 Sleep Quality
- Four-component weighted formula
- Duration score anchoring
- Literature: Ohayon et al. (2017) — sleep quality recommendations

### 3.4 Training Load (sRPE + ACWR)
- Session strain formula
- ACWR 7d/28d ratio with sweet-spot bands
- Monotony as CV inverse
- Literature: Gabbett (2016) — ACWR, Foster (1998) — sRPE

### 3.5 Weight Trend
- OLS regression via PostgreSQL REGR_SLOPE
- Minimum observation gating
- Literature: standard linear regression methodology

### 3.6 Macro Adherence
- Calorie + protein against active target
- 14-day window with 200% cap

### 3.7 Change Eligibility
- Training gates: 2 comparable sessions OR 2 weeks 80% adherence
- Nutrition gates: 14 days weight + active target
- Literature: AI_SAFETY_SPEC.md §6

### 3.8 Versioning Strategy
- Algorithm version tracked via `policy_evaluations.policy_version`
- Changes require new policy_version, ADR update, and pgTAP regression
- No silent algorithm changes

## 4. Contract Fixtures

| Fixture | Action |
|---------|--------|
| `test/contract/fixtures/training_hub_v1_4.json` | Update — add resp_rate_z, prev_strain_z, sleep_debt_minutes fields |
| `test/contract/fixtures/daily_brief_v1_1.json` | **New** — parsed enriched daily brief shape |
| `test/contract/fixtures/daily_computed_metrics.json` | **New** — snapshot of persisted table row |

## 5. Flutter Contract Tests / Updates

| Test | Action |
|------|--------|
| `test/contract/training_hub_contract_test.dart` | Update parse to handle new breakdown fields |
| `test/contract/daily_brief_contract_test.dart` | **New** — verify daily brief parse |
| `test/phase_4_healthkit_test.dart` | Add sleep_debt, resp_rate normalization tests |

## 6. Hosted End-to-End Smoke Test

Run directly on hosted Supabase against real user data:

```sql
-- Verify compute works against real data
SELECT compute_daily_metrics('<your-user-id>', CURRENT_DATE, 'Asia/Kolkata');

-- Check persistence
SELECT * FROM daily_computed_metrics
  WHERE user_id = '<your-user-id>'
  ORDER BY local_date DESC LIMIT 3;

-- Verify baselines populated
SELECT metric_name, baseline_value, spread, n_observations, confidence
  FROM user_baselines WHERE user_id = '<your-user-id>';

-- Verify eligibility
SELECT evaluate_change_eligibility('<your-user-id>', CURRENT_DATE);

-- Check cron is scheduled
SELECT * FROM cron.job WHERE jobname LIKE 'tracend%';
```

**Acceptance criteria:**
- Recovery score non-null, in 0-100 range
- At least one baseline metric has confidence ≥ 'low'
- No SQL errors or division-by-zero
- Eligibility gates return valid JSON

## 7. Performance Baseline

Add a performance guard to the pgTAP suite:

```sql
-- Time constraint: compute_daily_metrics must complete within 2 seconds
-- with 90 days of health data + 30 workouts
SELECT ok(
  clock_timestamp() - start_time < interval '2 seconds',
  'compute_daily_metrics completes within 2s'
);
```

## 8. Fix: `compute_user_baselines` — Prevent Double-Smoothing

`compute_user_baselines` iterates over raw observations to insert baseline history rows, then
calls `compute_winsorized_ewma` for the final value. Verify that both paths produce consistent
EWMA values — the manual iteration's `ewma` and the function's return value should match.

If they diverge, fix the manual iteration to use `compute_winsorized_ewma` for each step.
The purpose of the manual loop is only to capture per-observation metadata
(z_score, was_winsorized, was_outlier_rejected, lambda_used) — the final EWMA must be identical.

## 9. Fix: Confidence Tier in `compute_user_baselines`

Current code sets:
- ≥14 obs → 'high'
- ≥4 obs → 'medium'
- Else → 'low'

But `compute_winsorized_ewma` returns NULL for <3 obs. Fix:
- <3 obs → `cold_start`
- 3-6 obs → `low`
- 7-13 obs → `medium`
- ≥14 obs → `high`

Align `compute_user_baselines` with `compute_daily_metrics` data_confidence logic.

## Deployment Order

```
1. backup-db.sh
2. Verify current baseline values (save for regression comparison)
3. db push --dry-run migration (algorithm fixes)
4. db push --linked migration
5. Run hosted smoke test (step 6 above)
6. Run full pgTAP suite (67 tests)
7. Update contract fixtures
8. Flutter analyze + test (89 → ~92 tests)
9. iOS release build
10. pre-deploy.sh (full gate)
```

## What Stays Untouched

- `coach-decide` Edge Function — Phase 3
- `coach-chat` Edge Function — Phase 3
- `health-sync` Edge Function — no changes
- All Flutter UI screens, widgets
- All existing tables, columns, RLS policies (except added ones)
- `prepare_daily_coaching` signature (return shape unchanged, internal computation changes)
- `get_my_training_hub` and `get_my_daily_brief` signatures

## Architecture Rule Compliance

All 12 AGENTS.md rules verified. Deterministic calculations only. No model output mutation.
RLS on new table. Forward-compatible migration (additive + alter, no drops/renames).
Canonical units preserved. UTC timestamps.
