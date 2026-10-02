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
| Resp Rate    | 0.05   | Lower = better      | z-score negated; collected via HealthKit since 2026-09-06 (previously dead code) |
| Prev Strain  | 0.05   | Lower recent = better | 7-day avg subtracted; needs 28-day spread > 0 |

Each z-score: `z = (observation - ewma_baseline) / spread`. HRV is scored in the natural-log
domain (2026-09-07, math honesty): the fold stores `ln(hrv_ms)`, today's value enters as
`ln(hrv_ms_today)`, and the spread is on the ln scale. Raw-ms z over-weights HRV's long upper tail
(a 100→110ms night moved the score more than 40→44ms despite being the same proportional change);
the ln form gives proportional changes equal weight — two users whose histories differ only by a
constant factor (device or physiology scale) receive identical z-scores. Other metrics stay raw.
Sign inverted for RHR and resp rate
components. A component is usable only when it has BOTH a value today (inside its plausibility
band) AND a baseline with `spread > 0 AND n_observations >= 3` — the fold actually ran. A
present value without a usable baseline (cold start) previously masqueraded as
"exactly at baseline" (z = 0) with full weight. For prev_strain, "usable" means the 7-day
strain average is > 0 AND the 28-day window of daily strains has `stddev > 0`: a single strain
day (stddev undefined) or identical days (stddev 0) cannot produce a z-score, so prev_strain is
reported missing instead of joining at z = 0. Unusable components are excluded,
`weight_total` is recalculated from included weights only, and the component key is listed in
`recovery_breakdown.missing_components`. All five z-score keys stay present and non-null
(0 when unusable) so shipped clients keep parsing the shape they know. When no component is
usable, `recovery_score` is NULL — never a fabricated number.

### Raw Values Alongside z (2026-09-07, brief 1.4)

Z-scores answer "how does today compare to *your* baseline" but hide what was actually
measured, which misread in the owner's dogfooding (`−1.2 z` was a 38 ms night against a
~50 ms ln-baseline). The brief's `computed.today_raw` object passes today's measured values
through verbatim — `hrv_ms`, `resting_hr_bpm`, `sleep_minutes`, `resp_rate_bpm`, plus the
computed `daily_strain` — with `null` for anything not measured that day (never zero). It is
a passthrough from `daily_health_summaries`, never derived; the future-date guard payload
carries the key with every value null so consumers never see a missing key. Client driver
rows render `38 ms · +0.5` (raw · z); unmeasured components keep "No data" rather than a
fake `+0.0`.

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
| 1 (seed)     | —         | —          | First observation seeds the EWMA |
| 2-8 (early)  | 3 days    | 0.206      | Fast adapt from cold start |
| 9+ (stable)  | 14 days   | 0.048      | Slow, stable tracking      |

The first observation is the seed (no update runs); the 8th update still uses the fast
half-life and the 9th is the first slow one. This transition at observation 8 (Pass-5
reference reconciliation, 2026-09-08 — the table previously read "1-7 / 8+", one step
early) prevents the first few readings from permanently anchoring the baseline.

### Winsorizing

```text
median = percentile_50(values)
MAD    = 1.4826 * percentile_50(|values - median|)

±3×spread boundary  → Winsorize (clamp to boundary)
> ±5×spread         → Hard reject (skip entirely, record was_outlier_rejected=true)
```

The `1.4826` constant makes MAD consistent with standard deviation for normally-distributed data
(Hunter 1986).

**Two Winsor regimes in one fold** (Pass-5 reference reconciliation, 2026-09-08 — previously
undocumented): the fold runs *two parallel passes* over the observation array, and they clamp
at slightly different scales:

- **Stored center** (`compute_winsorized_ewma`): bounds from the raw unfloored 1.4826·MAD.
  Its historical cold-start shortcut is still live in the SQL — `MAD = 0 → return the last
  observation` (an all-identical history anchors on its final value).
- **Stored spread** (the fold loop): bounds from the *floored* spread
  (`max(floor, 1.4826·MAD)`) plus the 21-day spread EWMA below. The floor is what keeps the
  two regimes from producing a usable-center/unusable-spread disagreement.

The reference implementation (`test/reference/recovery_reference.dart`, Pass 5) reproduces
both passes exactly; changing one without the other drifts them apart.

### Spread as EWMA + Floors (2026-09-07, Pass 3)

The **stored** `user_baselines.spread` is no longer the static full-history MAD. Two failure modes
motivated the change: a metric whose day-to-day noise *shrank* kept being z-scored against its
whole noisy past, and one whose noise *grew* kept being scored on an ancient calm window.

- **Stored spread** = a 21-day-half-life EWMA over per-observation |deviation from the running
  center| (`0.9670·spread + 0.0330·|x_t − ewma_t|`, using the SQL's rounded literals —
  λ = 0.0330, not the unrounded `1 − 0.5^(1/21) ≈ 0.0327`), one step wider than the 14-day
  center half-life for stability. Winsor bounds for the fold still use the static full-history
  MAD scale (a static scale is right where the bounds clamp).
- **Per-metric floors** (`baseline_floor_spread`): HRV 0.05 (ln-ms domain), RHR 2 bpm, sleep 15
  min, weight 0.5 kg, resp 0.5 bpm. A spread below its floor would amplify noise into dramatic
  z-scores on near-identical histories — including the all-identical history whose raw spread is
  exactly 0.
- **z usability gate** (hardened with the floors): a component z-scores only when the baseline has
  `spread > 0` AND `n_observations >= 3` (the fold actually ran). The floor gives cold-start rows
  a non-zero spread, so `spread > 0` alone would let a one-night baseline masquerade as usable —
  a present value with a cold baseline is still reported missing, never "at baseline".

### Baseline Staleness (2026-09-07, Pass 3)

`user_baselines.last_observation_date` stamps the TRUE newest observation date (it previously
recorded the compute's target date, so syncing on 09-07 with newest data from 08-26 read as
fresh). The brief's per-metric baseline objects carry additive `last_obs_date` + `age_days`
(0 = observed today); a never-observed metric reports null for both, never 0. This is the
anti-masquerade rule: an old value can never silently present as current. Z-scoring policy is
unchanged — a stale-but-valid baseline still z-scores (that is what a personal baseline is); the
fields make staleness visible to display and the AI context (Pass 4).

### Fold Domains and Plausibility Bands (2026-09-07)

Each observation must pass a plausibility band before entering the fold — out-of-band values are
**rejected** (counted in neither `n_observations` nor the baseline), never clamped into it. A
today-value outside its band is reported missing rather than z-scored.

| Metric            | Band           | Fold domain |
| ----------------- | -------------- | ----------- |
| HRV (SDNN)        | 5–250 ms       | ln(ms)      |
| Resting HR        | 30–120 bpm     | raw         |
| Sleep duration    | 1–960 min      | raw (a 0-minute night is absence, not zero sleep) |
| Weight            | 30–300 kg      | raw         |
| Respiratory rate  | 8–25 bpm       | raw         |

HRV folds in ln(ms) per §1; `metric_baseline_history.raw_value` keeps the raw observation in ms
for the audit trail (only `hrv_sdnn_ms` differs from its raw fold). Stored `user_baselines` rows
for HRV were converted once (20260907120000): `baseline_value = ln(ms)`,
`spread = spread_ms / ewma_ms` (first-order delta conversion — both SET expressions read the
pre-update row).

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

### Sub-Score Honesty (2026-09-07)

A sub-score whose input is missing scores NULL — never a fabricated 0 (which the weighted sum
would read as a terrible night) or a coalesced 100. Missing awake minutes → efficiency NULL;
missing deep OR REM stages → restorative NULL; fewer than 2 nights of sleep history in the
7-day window → consistency NULL (measured on sleep duration, not stage data). Each NULL
sub-score drops out and the composite **renormalizes over the remaining weights** (the same
pattern as the recovery composite):

```text
sleep_quality = sum(weight_i * score_i for non-null i) / sum(weight_i for non-null i)
```

The full `sleep_breakdown` object is emitted **only when all four sub-scores are computable** —
the shipped Dart parser requires every key when the object exists. A new additive scores key,
`sleep_breakdown_missing`, names the dropped sub-scores (`["efficiency","restorative"]`) for
consumers that want to explain the gap. Deployed clients render the card without sub-scores
(an already-tolerated state) rather than crashing on null keys.

### Cold-Start Duration Floor (2026-09-07)

Duration score uses the personal sleep EWMA only when the sleep baseline has **≥ 7 nights**;
below that the 480-minute population floor is the need. The EWMA cold-starts at the first
observed night, so before this floor a first-ever 420-minute night anchored the baseline to
itself and scored exactly 100.

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
               where duration_seconds <= 10800 (3-hour cap; longer sessions are excluded —
               the 2026-08-22 cap that fenced off the July-22 403-strain outlier)
```

Session effort = 0–10 RPE. Strain normalised per 10-minute block. The same 10800-second
cap applies to every strain window (ACWR, monotony, prev-strain z).

### Acute:Chronic Workload Ratio (ACWR)

```text
ACWR = avg_strain_7d / avg_strain_28d   (over calendar windows, rest days = strain 0)
```

Computed over zero-filled 28-day **calendar** windows (every date in `target_date - 27 ..
target_date`, rest days carrying strain 0 — that is what a workload ratio means) rather than
averaging only over logged-session days. ACWR is **null until ≥ 14 strain days** exist in the
chronic window (noop minChronic parity, 2026-09-07); the previous `avg28 != 0` guard let a single
logged session produce ACWR = 1.0 — the "average training day" asserted from one data point.
Denominator zero also nulls.

### ACWR Bands

Unified app-wide convention (owner-approved 2026-09-04; previously this table and the two
Train/Today UIs carried three different banding schemes):

| Band       | ACWR      | Signal                                       |
| ---------- | --------- | -------------------------------------------- |
| Low load   | < 0.8     | Lighter than the athlete's normal training   |
| Optimal    | 0.8–1.3   | Matches the normal — productive range        |
| High load  | > 1.3     | Heavier than normal — scale back above 1.5   |

Above 1.5 escalates the UI copy ("much heavier — scale back to protect progress"), never a
fourth band label. Every UI reading an ACWR (Train's week rail, Today's session plan) uses
`LoadBand.forAcwr`'s mapping verbatim. Thin-history caveat: ACWR from fewer than ~4 weeks of
sessions is noise (finding #6, docs/reviews/2026-09-02-post-deploy-verification-and-findings.md);
Train's week rail gates any ratio verdict on ≥4 sessions in the 28-day payload and renders
"Building baseline" below that floor.

### Training Monotony

```text
monotony = avg_strain_7d / stddev_strain_7d   (zero-filled acute week, rest days = 0)
```

Higher = more repetitive loading pattern. Null unless **≥ 4 strain days** in the acute week AND
stddev > 0 (2026-09-07). The zero-filled calendar week fixes the production symptom of monotony
5.57 reported on a window of identical loads: rest days are now real variance, and only a week
where every acute day carries the same strain (all trained identically, no rest) stays null.
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
- Regression needs at least 2 observations (the REGR_* aggregate's own floor — 1 point yields
  null). The "minimum 3" this section documented before 2026-09-08 was never enforced by the
  SQL; a future migration may raise the gate, and the reference implementation tracks the
  SQL's actual behavior until then.
- R² computed via `REGR_R2` for the 28-day window
- Sources merged: `body_measurements` UNION `daily_health_summaries` (manual entries take priority)

### Coach Calculators (2026-09-30)

`supabase/functions/_shared/coach_calculations.ts` computes exact numbers from the Coach athlete
file (`prepare_coach_chat_v8`) and renders them as the "Calculated by Tracend" context section. The
model quotes these instead of doing its own arithmetic. Windows end on the coaching date.

- **Weight trend:** the same OLS slope, sources and precedence as above (body measurements, plus
  HealthKit daily weights only on dates without a body measurement; identical readings count
  once), over 4 weeks (28 days) and 8 weeks (56 days), reported in kg/week. A window needs
  readings on at least 4 days spanning at least 14 days; otherwise no trend is given.
- **Weight projection (labeled estimate):** the current pace is the 4-week trend (the 8-week trend
  when the 4-week one lacks readings). The other window widens the range only when it points the
  same way. Under 0.05 kg/week the weight counts as stable and no date is projected. The section
  lists the weeks to each of the next 10 whole kilograms in the trend's direction (plus a goal
  weight, if one is stored), capped at 104 weeks, and the weight expected in 4, 8, 12 and 26
  weeks.
- **Training:** sessions, minutes, completed sets, volume, average RPE and average session length
  for the last 7 days, the previous 7 days and the last 28 days; the week-over-week session and
  volume change; the 28-day pace per week next to the plan's sessions per week.
- **Watch metrics:** sleep, resting heart rate, HRV, steps, active energy and workout minutes, each
  averaged over its measured days only (with the day count) for the last 7, previous 7 and last 28
  days, plus the 28-day range. A week-over-week change needs at least 3 measured days in each week.
- **Nutrition:** averages per day with confirmed meals (unlogged days are unknown, not zero) over 7
  and 28 days, and the difference from each nutrition target.
- Rounding is half away from zero, like PostgreSQL `round(numeric, n)`, so the averages match the
  SQL ones already in the file.

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
| Baselines function   | `engine_version`       | `baseline-v2`|
| Daily metrics        | `feature_engine_version` | `daily-v2`  |
| Daily scoring JSON   | `schema_version`       | `2.2`        |
| Eligibility          | `policy_version`       | `eligibility-v1` |
| Training hub RPC     | `schema_version`       | `1.5`        |
| Daily brief RPC      | `schema_version`       | `1.6`        |
| Onboarding plan      | `policy_version`       | `onboarding-policy-v2` |
| Exercise catalog     | `catalog_version`      | `catalog-v1` |
| Onboarding proposal  | `schema_version`       | `2.0`        |

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

## 9. Onboarding Plan Policy (`onboarding-policy-v2`, 2026-10)

Code: `supabase/functions/_shared/onboarding/policy.ts`. An onboarding plan, from a model or from
Tracend's rules, must stay inside these ranges. `plan_contract.ts` rejects it otherwise. The ranges
are evidence-based guardrails, not a prescription; the model chooses within them.

### Energy

```text
BMR  = 10·kg + 6.25·cm − 5·age + 5      (male)
BMR  = 10·kg + 6.25·cm − 5·age − 161    (female)
     unspecified sex: both, as a range (female … male); confidence low

TDEE = BMR × daily-activity factor + training energy
       factor: mostly sitting 1.2 · some standing 1.375 · mostly standing 1.55 · physical labour 1.725
       training energy (kcal/day) = 4 × 3.5 × kg / 200 × session minutes × sessions per week / 7
```

- **Two separate answers:**
  - Daily activity is its own answer, so planned lifting is not counted twice. NIDDK's Body Weight
    Planner also treats activity as its own input.
  - Training energy uses net MET 4: resistance training is about 5 METs (Compendium of Physical
    Activities), minus the resting MET the base factor already counts.
- **Equation choice:** Mifflin-St Jeor is the equation most often within 10% of measured resting
  energy (Frankenfield 2005). For unspecified sex there is no published single equation, so both
  are kept as a range rather than inventing a midpoint.

### Calories

| Goal | Window around TDEE |
| --- | --- |
| Fat loss | −25% … −10% |
| Muscle gain | +5% … +15% |
| Recomposition | −10% … 0% |
| Strength | 0% … +10% |
| Aesthetic | −5% … +5% |

- **Floor:** max(BMR, 1,200 kcal female / 1,500 kcal male or unspecified), from NHLBI guidance.
- **When the floor applies:** if the window starts below the floor, the floor wins and confidence
  is capped at low.
- **Ceiling:** 6,000 kcal, the database bound. A window above it is capped (a 180 kg labourer
  gaining muscle on six 2-hour sessions estimates about 6,500–7,100 kcal), confidence is capped at
  low, and the plan says so.
- **Basis:** fat loss of about 0.5–1% of body weight a week preserves lean mass (Helms 2014). A
  lean-gain surplus of about 10–20% gains about 0.25–0.5% of body weight a week (Iraki 2019).

### Macros

- **Protein:** 1.6–2.2 g/kg, up to 2.6 g/kg in a deficit (fat loss, recomposition). Iraki 2019;
  ISSN 2017 gives 1.4–2.0 g/kg and 2.3–3.1 g/kg of lean mass in a deficit.
- **High BMI:** at BMI ≥ 30, protein and the fat minimum use the weight at BMI 25. This is a design
  choice; no source sets that cutoff. With total weight, a 250 kg athlete's 0.5 g/kg fat minimum
  passed the 35% maximum at their calorie target.
- **Fat:** at least max(20% of calories, 0.5 g/kg) and at most 35% of calories (US DRI 20–35%).
- **Carbohydrate:** the rest, 20–1,000 g. Below 2 g/kg it is flagged as an assumption, not
  rejected. The rules plan raises fat (within its maximum) when carbohydrate would pass 1,000 g.
- **Absolute bounds:** calories 1,000–6,000, protein 30–400 g, carbohydrate 20–1,000 g, fat
  20–300 g, equal to `private.is_valid_initial_proposal_v2`.
- **Macro sum:** 4·protein + 4·carbohydrate + 9·fat must be within 5% of the calorie target.

### Training

| Days (chosen weekdays, at most 6) | Split |
| --- | --- |
| 1–3 | Full body |
| 4 | Upper / lower |
| 5 | Upper, lower, push, pull, legs |
| 6 | Push / pull / legs ×2 |

- **Per session:**
  - working sets at most min(30, minutes / 3);
  - exercises at most min(8, 2 + minutes / 15);
  - estimated length = 8 min warm-up + Σ sets × (45 s + rest), within the athlete's minutes
    + max(5, 15%).
- **Weekly sets per target muscle** (the catalog's first muscle): at most 12 for beginners and 20
  for intermediates. ACSM 2026 gives about 10+ sets per muscle a week; Schoenfeld 2017.
- **Coverage:** every week includes a squat or lunge, a hinge, a push and a pull. A pattern the
  athlete avoids is not required; a group with no pattern left that they can do is dropped.
- **Movements to avoid:** squat, lunge, hinge, horizontal push, vertical push, horizontal pull,
  vertical pull. Every exercise with an avoided pattern is excluded.
- **Prescription ranges:**
  - Reps 6–20, or 3–20 for strength.
  - RPE 7–8.5 for beginners (RIR 2–3) and 7–9 for intermediates.
  - Rest 60–180 s, or up to 240 s for strength.
  - Sets per exercise 1–5.
- **Blocks:** 4–8 weeks before a review. The app repeats one weekly template, so the plan never
  promises a deload or a different week; progression is adding reps or load within the ranges.
  (Deloads in practice come about every 5–6 weeks, Sports Med Open 2024, and need a week-by-week
  plan the app does not have yet.)
- **Rules plan:**
  - The same limits, using split templates and the first equipment-compatible catalog exercise for
    each movement slot.
  - Sessions of 45 minutes or less keep compound rests at 2 minutes so that they still cover the
    patterns.
  - A slot with nothing the athlete can do takes its sibling pattern (squat ↔ lunge, horizontal ↔
    vertical push or pull).
  - It is validated before use. Answers it cannot meet are refused as infeasible (see
    AI_SAFETY_SPEC §6), never stored.
  - Deno tests prove it is valid for every equipment set × 1–6 days × both paths × every goal ×
    30–120 minutes; its nutrition is valid and storable for 14,400 combinations of body size, age,
    activity, goal, sex and schedule; and it is valid with any one movement avoided.

### Apple Health summary (2026-10)

Code: `supabase/functions/_shared/onboarding/health_summary.ts`.

- **Window:** the 28 dates before the athlete's local today (`user_accounts.timezone`). Today's
  partial row is left out; yesterday's is kept.
- **Included only with enough data:**
  - steps and active energy: averages over days with a value, at least 7 such days;
  - sleep: average over nights with a value, at least 7 nights;
  - workouts: per week, minutes per week and the three commonest types, only when at least one
    workout was found. None found is listed as missing information, never read as inactivity:
    HealthKit hides whether read access was denied;
  - weight: the latest reading in the window, and the least-squares trend (`coach_calculations.ts`
    `weightTrendKgPerWeek`, at least 4 readings across 14 days).
- **Left out:** resting heart rate, HRV and breathing rate, which need a personal baseline the
  athlete does not have yet.
- **Rounding:** steps and kcal to whole numbers, sleep to whole minutes, workouts per week 0.1,
  weight 0.1, trend 0.01, so the same data gives the same snapshot hash.
- **What it changes:**
  - **Short sleep** (average under 6 h): the RPE ceiling drops 0.5 and the rules plan's targets
    drop 0.5 (`startLighter`). Short sleep impairs recovery and strength-endurance; a lighter
    first block is the conservative choice.
  - **Nothing else changes a number.** The athlete's answers set the calorie and protein ranges.
  - **Notes:** an Apple Health weight more than 3 kg from the answer, and average steps two or
    more activity levels from the daily-activity answer.
- **Steps to daily activity** (shared with the app's About you step): under 5,000 mostly sitting;
  5,000–7,499 some standing; 7,500 and over mostly standing (Tudor-Locke step bands). Steps never
  suggest physical labour.
- **Short sleep note:** when the usual months have enough sleep (below), the note says whether the
  short sleep is the athlete's usual or below it.

### Coach intake (`onboarding-policy-v2`, 2026-10)

Code: `strength.ts`, `policy.ts`, `health_history.ts`, `questions.ts` in
`supabase/functions/_shared/onboarding/`.

- **Training years** (experienced path): under 1, 1–2, 3–5, over 5. Under a year keeps the beginner
  limits; older drafts without the answer keep the experience they were built with. Years never
  raise a volume limit: someone back after a long break has the years but not the work capacity.
- **Reported top sets:** barbell bench press, back squat, deadlift, overhead press and row only, as
  the load on the bar × reps (1–15) with 0–4 reps left. Dumbbell, cable, machine and pull-up loads
  wait until their load basis (per hand, assistance, stack increments) is represented.
- **One-rep max:** Epley with reps in reserve, `load × (1 + (reps + reps_left) / 30)`, to 0.5 kg.
- **Starting load** for an exercise that is a reported lift:
  `e1RM / (1 + (rep_max + (10 − target_RPE)) / 30) × 0.95`, rounded **down** to 2.5 kg; none below
  an empty 20 kg bar. Deterministic code adds it after validation; the model never writes a load.
- **Ratios** (row ÷ bench, deadlift ÷ squat) are passed to the model only for pairs the athlete
  reported, as hints. Code states no norm: published ratio norms vary with build and technique,
  so no band is hard-coded.
- **Focus muscles** (0–2, the catalog's target muscles): each gets a weekly-set minimum of
  `min(10, floor(set budget per session × days × 0.3 ÷ focus muscles))`, never above the maximum.
  Volume counts on the catalog's first muscle only, as the maximum does. Prioritising one or two
  muscles is how Alpha Progression, Dr. Muscle and MacroFactor specialise; volume is the main
  hypertrophy lever (Pelland 2025) and exercise order does not change growth (Nunes 2021), so the
  plan moves sets, not limits.
- **Feasible minimum:** the rules plan fills the focus muscles first by adding sets, then an
  exercise, then by swapping an accessory aimed at another muscle, inside every limit.
  `policiesFor` lowers each minimum to what that reached, so a valid plan always exists (Deno
  sweep: every schedule × 30/60/90 minutes × equipment set × 0, 1 or 2 focus muscles).
- **Follow-up questions:** 0–3, each in one allowed topic (split history, recovery between
  sessions, a stalled lift, exercise preference, schedule flexibility, daily eating routine), up
  to 160 characters, optionally 2–4 quick answers. Injury, pain and medical questions are refused.
  Stored per hash of the answers and Apple Health data, so a retry never asks the model again and
  an edited answer makes earlier follow-up answers stale.

### Usual months (2026-10)

Code: `health_history.ts` (server) and `lib/features/health/health_baseline.dart` (app).

- **Window:** the 11 completed calendar months before the athlete's current month; the month in
  progress never counts. The app sends one row per month: workouts, strength workouts
  (`TRADITIONAL_` and `FUNCTIONAL_STRENGTH_TRAINING`), workout minutes, nights of sleep and their
  average, weigh-in days and their average, days with any data, and the first and last date with
  data. No raw sample leaves the phone. During onboarding the follow-up questions and the plan wait
  up to 30 s for the upload (retrying one that failed), because both are hashed with these months.
- **Counted months:**
  - strength: from the first month with any workout (earlier months may predate the watch);
  - sleep: months with at least 20 nights;
  - weight: months with at least 4 weigh-in days.
- **Usual values** need at least 3 counted months: the median strength workouts a week, the mean
  sleep, and the change between the first and last counted month's weight.
- **Returning from a break:** usual strength at least 2 a week and the last 28 days under half of
  it (none found lately counts as none, because the history proves workouts are readable). The
  session set budget drops a fifth and the RPE ceiling 0.5 (`startLighter`) for the first block,
  and a note says why.

