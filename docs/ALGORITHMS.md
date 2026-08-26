# Tracend Algorithms Reference

> **Audience:** Tracend developers and reviewers. Literature-backed formulas, versioning
> policy, and deterministic guarantees for the feature engine scoring pipeline.

## 1. Recovery Score

### Formula

```text
recovery_score = round(100 / (1 + exp(-1.6 * composite_z)))
```

Logistic transform with steepness `k = 1.6` and no offset — a composite of exactly 0
(every usable observation at its baseline) maps to 50. The previous `+0.2` optimism
offset was removed 2026-08-25 (recovery honesty): it fabricated ~58 on days with no
usable data.

### Z-Composite

```text
composite_z = (0.55 * hrv_z + 0.20 * rhr_z + 0.15 * sleep_z + 0.05 * resp_rate_z - 0.05 * prev_strain_z) / weight_total
```

| Component    | Weight | Direction           | Note                                        |
| ------------ | ------ | ------------------- | ------------------------------------------- |
| HRV (SDNN)   | 0.55   | Higher = better     | Dominant signal per Plews & Buchheit 2017   |
| RHR          | 0.20   | Lower = better      | z-score negated                            |
| Sleep        | 0.15   | Higher = better     | Quantity only in composite                 |
| Resp Rate    | 0.05   | Lower = better      | z-score negated; optional                  |
| Prev Strain  | 0.05   | Lower recent = better | 7-day avg subtracted; needs 28-day spread > 0 |

Each z-score: `z = (observation - ewma_baseline) / spread`. Sign inverted for RHR and resp rate
components. A component is usable only when it has BOTH a value today AND a baseline with
`spread > 0`; a present value without a usable baseline (cold start) previously masqueraded as
"exactly at baseline" (z = 0) with full weight. For prev_strain, "usable" means the 7-day
strain average is > 0 AND the 28-day window of daily strains has `stddev > 0`: a single strain
day (stddev undefined) or identical days (stddev 0) cannot produce a z-score, so prev_strain is
reported missing instead of joining at z = 0. Unusable components are excluded,
`weight_total` is recalculated from included weights only, and the component key is listed in
`recovery_breakdown.missing_components`. All five z-score keys stay present and non-null
(0 when unusable) so shipped clients keep parsing the shape they know. When no component is
usable, `recovery_score` is NULL — never a fabricated number.

### Recovery Score Bands

| Band      | Cutoff       | z-composite equivalent | Interpretation        |
| --------- | ------------ | ---------------------- | --------------------- |
| Excellent | r ≥ 80       | z ≥ 0.87               | Ready for best effort |
| Good      | 65 ≤ r < 80  | 0.39 ≤ z < 0.87       | Ready to train        |
| Moderate  | 50 ≤ r < 65  | 0 ≤ z < 0.39          | Balanced load         |
| Low       | 35 ≤ r < 50  | -0.39 ≤ z < 0         | Recovering poorly     |
| Poor      | r < 35       | z < -0.39              | Recovered poorly      |

Rendered by the recovery readout band chip (`RecoveryReadoutCard`); the previous
Red/Yellow/Green three-band table was never used by any code path.

### Baseline Anchor

When z_composite = 0 (all usable observations at baseline): exactly 50.
When z_composite = +3: ~99 (ceiling). When z_composite = -3: ~1 (floor).

### Data Confidence

`data_confidence` counts the four HealthKit components (HRV, resting HR, sleep,
respiratory rate): none missing → `high`, one or two → `medium`, three or more or no
stored summary for the day → `low`. Prior strain is reported missing but does not lower
confidence by itself (rest days are normal).

### SDNN vs RMSSD Caveat

Apple HealthKit reports SDNN. Research literature typically uses RMSSD. The z-score normalisation
partially compensates, but direct comparison with externally published normative RMSSD values is
not valid. This is a **documented device limitation** (see Plews & Buchheit 2017, Fig 3).

### Literature

- Plews, D.J. & Buchheit, M. (2017). Heart rate variability monitoring in elite athletes. *Sports
  Med* 47, 2115–2137.

---

## 2. Winsorized EWMA Baselines

### EWMA Update Rule

```text
lambda   = 1 - 0.5^(1 / half_life_days)
ewma_t   = lambda * winsorized_t + (1 - lambda) * ewma_{t-1}
```

### Anti-Anchoring Schedule

| Observations | Half-life | lambda     | Purpose                    |
| ------------ | --------- | ---------- | -------------------------- |
| 1-7 (early)  | 3 days    | 0.206      | Fast adapt from cold start |
| 8+ (stable)  | 14 days   | 0.048      | Slow, stable tracking      |

Transition at observation 8 prevents the first few readings from permanently anchoring the
baseline.

### Winsorizing

```text
median = percentile_50(values)
MAD    = 1.4826 * percentile_50(|values - median|)
spread = MAD

±3×spread boundary  → Winsorize (clamp to boundary)
> ±5×spread         → Hard reject (skip entirely, record was_outlier_rejected=true)
spread = 0          → All values identical → return last value
```

The `1.4826` constant makes MAD consistent with standard deviation for normally-distributed data
(Hunter 1986).

### Confidence Tiers

```text
<3 observations     → cold_start
3–6 observations    → low
7–13 observations   → medium
≥14 observations    → high
```

### Literature

- Hunter, J.S. (1986). The exponentially weighted moving average. *Journal of Quality Technology*
  18(4), 203–210.
- Rousseeuw, P.J. & Croux, C. (1993). Alternatives to the median absolute deviation. *JASA* 88,
  1273–1283.

---

## 3. Sleep Quality

### Formula

```text
sleep_quality = 0.50 * duration_score
              + 0.20 * efficiency_score
              + 0.20 * restorative_score
              + 0.10 * consistency_score
```

Result clipped to [0, 100].

### Component Definitions

| Component        | Weight | Formula                                        | Range    |
| ---------------- | ------ | ---------------------------------------------- | -------- |
| Duration Score   | 0.50   | clip(sleep_minutes / baseline_ewma * 100, 0, 100) | 0–100  |
| Efficiency Score | 0.20   | (sleep_minutes - awake_minutes) / sleep_minutes * 100 | 0–100 |
| Restorative Score| 0.20   | (deep_minutes + rem_minutes) / sleep_minutes * 100 | 0–100 |
| Consistency Score| 0.10   | 100 - (stddev_7d / mean_7d * 50), floored at 0 | 0–100   |

Duration score compares tonight's sleep duration against the personal EWMA baseline, falling
back to the 480-minute (8-hour) reference target when no usable baseline exists. Oversleeping
(>100) is clipped. The previous `480 / baseline_ewma` form ignored tonight's sleep entirely —
a 4-hour night scored identically to a 9-hour night, and any baseline ≤ 480 was pinned at 100
forever; changed 2026-08-26 after the noop StrandAnalytics rigor cross-check.
No sleep data today → sleep_quality null.

### Sleep Debt

```text
sleep_debt_minutes = 480 - avg_7d_sleep_minutes
```

Positive value = sleeping less than target on average over past 7 days.

### Literature

- Ohayon, M. et al. (2017). National Sleep Foundation's sleep quality recommendations. *Sleep
  Health* 3(1), 6–19.

---

## 4. Training Load

### Session Strain (sRPE)

```text
daily_strain = sum(session_effort * duration_seconds / 600) for all completed sessions on date
```

Session effort = 0–10 RPE. Strain normalised per 10-minute block.

### Acute:Chronic Workload Ratio (ACWR)

```text
ACWR = avg_strain_7d / avg_strain_28d
```

Computed from daily strain sums grouped by local_date. Null when fewer than 7 days of strain data
or when denominator is zero.

### ACWR Bands

| Zone         | ACWR   | Signal                   |
| ------------ | ------ | ------------------------ |
| Low risk     | < 1.0  | Undertraining possible   |
| Sweet spot   | 1.0–1.5| Optimal stimulus         |
| Danger zone  | > 1.5  | Elevated injury risk     |

### Training Monotony

```text
monotony = avg_strain_7d / stddev_strain_7d
```

Higher = more repetitive loading pattern. Null when stddev is zero (all sessions identical).
Monotony is the inverse of the coefficient of variation.

### Literature

- Gabbett, T.J. (2016). The training-injury prevention paradox. *Br J Sports Med* 50(5), 273–280.
- Foster, C. (1998). Monitoring training in athletes with reference to overtraining syndrome. *Med
  Sci Sports Exerc* 30(7), 1164–1168.

---

## 5. Weight Trend

### OLS Regression

```text
weight_trend = REGR_SLOPE(weight_kg, epoch_days) from PostgreSQL aggregate
```

- 7-day window: observations from target_date - 6 through target_date
- 28-day window: observations from target_date - 27 through target_date
- Minimum 3 observations required per window; otherwise null
- R² computed via `REGR_R2` for the 28-day window
- Sources merged: `body_measurements` UNION `daily_health_summaries` (manual entries take priority)

### Literature

- Standard ordinary least squares regression methodology. Neter, J. et al. (1996). *Applied Linear
  Statistical Models*.

---

## 6. Macro Adherence

### Formula

```text
macro_adherence_pct = avg(14-day daily calorie intake / target_calories * 100) capped at 200%
```

- 14-day window: target_date - 13 through target_date (inclusive)
- Only confirmed meals with confirmed items counted
- Returns null when: no active nutrition target, no confirmed meals, or target calories = 0

### Boundaries

| Adherence     | Signal                  |
| ------------- | ----------------------- |
| < 80%         | Under target            |
| 80–120%       | At target               |
| > 200%        | Capped (display maximum)|

---

## 7. Change Eligibility Gates

### Training Change

| Gate                        | Criterion                                    |
| --------------------------- | -------------------------------------------- |
| Comparable Sessions         | ≥ 2 completed sessions in last 14 days where `logging_completeness ≥ 0.5` |
| OR Adherence                | ≥ 80% completed rate over last 14 days       |

### Nutrition Change

| Gate                        | Criterion                                    |
| --------------------------- | -------------------------------------------- |
| Weight Data Minimum         | ≥ 14 distinct weight measurement days in last 28 days |
| AND Adherence Minimum       | ≥ 80% macro adherence over last 14 days      |
| AND Trend R² Minimum        | 28-day OLS R² ≥ 0.3                          |
| AND Active Target           | User must have an active nutrition target    |

### Disposition

```text
general = change_review_allowed  if training_eligible OR nutrition_eligible
        = maintain_only          otherwise
```

---

## 8. Versioning Strategy

| Component            | Version Field          | Current      |
| -------------------- | ---------------------- | ------------ |
| Baselines function   | `engine_version`       | `baseline-v1`|
| Daily metrics        | `feature_engine_version` | `daily-v2`  |
| Daily scoring JSON   | `schema_version`       | `2.1`        |
| Eligibility          | `policy_version`       | `eligibility-v1` |
| Training hub RPC     | `schema_version`       | `1.4`        |
| Daily brief RPC      | `schema_version`       | `1.2`        |

### Rules

1. Any formula change → bump relevant `policy_version` or `feature_engine_version`.
2. Any output field addition → bump `schema_version` on affected RPCs.
3. Any output field removal → two-phase: add new field, deploy consumers, then remove old field
   in a follow-up migration.
4. All algorithm changes require:
   - Updated pgTAP regression tests
   - Updated ADR if the change is architectural
   - Entry in `docs/ALGORITHMS.md` (this file)
5. No silent algorithm changes. Version bump in code must match version in constraint.
