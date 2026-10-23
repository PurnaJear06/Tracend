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

### Recovery Modes (2026-10-04, scoring 2.3, brief 1.8)

The score used to average every HRV reading of the day, including the ones the watch takes while
the athlete is awake, and was recomputed on every Today load. A day without the watch overnight
therefore scored scattered daytime readings against a baseline that mixed nights and days, and
the number moved from morning to evening (owner report: "around 10, and it changes"). Recovery
now has two modes, chosen per day:

| Mode      | When                                                          | HRV scored                                        | Composite weights |
| --------- | ------------------------------------------------------------- | ------------------------------------------------- | ----------------- |
| `night`   | The watch was worn asleep: HRV taken asleep, or breathing rate with 3 h+ of sleep | Mean HRV taken during the night ending today, against a baseline of nights (`hrv_sleep_ms`) | HRV 0.55, RHR 0.20, sleep 0.15, resp 0.05, prev strain 0.05 |
| `morning` | No night recorded                                              | Mean HRV taken 04:00–12:00 awake, against a baseline of mornings (`hrv_morning_ms`) | HRV 0.40, check-in 0.25, RHR 0.20, sleep 0.10, prev strain 0.05 |

- **Night.** A sleep session (samples less than an hour apart) of three hours or more is a night;
  an HRV reading taken inside it belongs to the morning the night ends on, so a 23:30 reading
  counts for the next day like the sleep around it (breathing rate too). Shorter sessions are naps:
  their HRV is neither night nor morning and their breathing readings are left out, so a nap never
  makes a night (the server also requires three hours of sleep before breathing alone does).
- **Morning.** HRV readings taken between 04:00 and 12:00 local time outside any sleep. Readings
  after 12:00 never enter, so the estimate stops moving at noon (`recovery_settled`). The morning
  check-in stands in for the missing night: sleep quality, energy, soreness (reversed) and mood,
  each 1–5 with 3 as "OK" (McLean et al. 2010); `check_in_z = clamp(mean − 3, −2, 2)`. Breathing
  rate has no weight (the watch records it only asleep). A night score ignores the check-in.
- **Separate baselines.** Readings taken asleep and awake are different measurements (posture,
  activity and caffeine move awake readings), so each folds into its own baseline with the same
  ln domain, band, floor and EWMA as HRV (§2) and is only ever compared with its own kind. The
  day's all-reading HRV (`hrv_sdnn_ms`) is kept for display and the coach context and is no longer
  scored.
- **Resting HR** is yesterday's final value in both modes, against a baseline folded through
  yesterday. Apple measures it awake and revises it through the day, so today's value would move
  the score, or its baseline, after every sync.
- **Confidence.** A night keeps the rule below. A morning estimate is at most `medium`: `medium`
  with a morning HRV reading, `low` without one. `check_in` joins `missing_components` when a
  morning estimate has no check-in.
- **Published.** `recovery_mode`, `recovery_settled`, `recovery_breakdown.check_in_z`,
  `recovery_breakdown.weights` (percent per component for the day's mode) and
  `today_raw.hrv_scored_ms` / `today_raw.resting_hr_scored_bpm` (the values the score used).

This is the industry pattern. WHOOP, Oura, Bevel by default and Apple's own Readiness give no
score without a night. Athlytic, the best-documented Apple Watch fallback, scores a morning HRV
reading against readings taken the same way and keeps the score from following daytime samples.
A one-minute Mindfulness (Breathe) session in the morning writes an HRV reading into the morning
window.

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

A morning estimate (Recovery Modes, above) is `medium` with a morning HRV reading and `low`
without one. For a night, `data_confidence` counts the four HealthKit components (HRV, resting HR, sleep,
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

### Athlete-Reported Session Effort (2026-10-03)

At finish the athlete answers "How hard was this workout overall?" on a whole-number 1–10 scale
(1–2 very easy, 3–4 easy, 5–6 moderate, 7–8 hard, 9 very hard, 10 max). The answer is required,
nothing is preselected, and there is no floor. The app sends it through `complete_workout_v2`
with `session_energy` null; the server stores it with `session_effort_source = 'athlete'` and
rejects anything that is not a whole number from 1 to 10. This replaces the fixed 8 (and energy 3)
that every logged workout carried before.

The finish request (effort and duration) is saved on the device before the call. When the call
fails it is sent again with the same values; a repeat after the server already finished the
workout returns `replayed: true` and changes nothing, so effort is written once.

### Effort Provenance (2026-10-03)

`workout_sessions.session_effort_source` records where a session's effort came from:

| Source              | Written by                              | Effort                         |
| ------------------- | --------------------------------------- | ------------------------------ |
| `athlete`           | `complete_workout_v2`                   | The athlete's 1–10 rating      |
| `legacy_default`    | `complete_workout` (builds before v2)   | The app's fixed 8; other values refused |
| `healthkit_default` | `healthkit_auto_complete_workout`       | A fixed 5                      |

Every session completed before 2026-10-03 is `legacy_default` or `healthkit_default` (backfilled
from the `workout.completed` and `workout.auto_completed` audit codes).

**Calibration window.** Strain, ACWR and monotony still sum every completed session, whatever its
source. For the first 28 days after the logging build ships, the chronic window therefore mixes
`legacy_default` sessions (effort 8, usually higher than a typical athlete rating) and
`healthkit_default` sessions (effort 5) with real athlete ratings. A ratio in that period compares
real recent weeks against a partly assumed baseline, so it reads as provisional. The Train load sheet
labels the window "Calibrating: older workouts used a default effort" until every day in it with a
session is `effort_reported`; the day level never uses a default-effort day (see Day Level).
Installed builds that still call `complete_workout` keep writing `legacy_default` 8, so the window
only closes for workouts finished on the new build.

**Set RPE vs session effort.** They are two different measurements and neither is derived from the
other:

| Field                             | Scope         | Required       | Used for                                     |
| --------------------------------- | ------------- | -------------- | -------------------------------------------- |
| `exercise_sets.rpe`               | One set       | No             | Set history and display; never in any strain |
| `workout_sessions.session_effort` | Whole workout | Yes, at finish | Session strain, ACWR, monotony, day level    |

Averaging set RPE would skip warm-ups, rest, cardio and fatigue across the session, and blank sets
would bias it; the session rating asks for the whole workout directly (Foster 1998). Set RPE stays
editable on every set, blank allowed.

### Workout Logging Calculations (on device, 2026-10-03)

The logging screen computes these from the sets on the device; the server returns no volume.

- **New best.** A completed set is a new best only if it beats both the historical `best_set` from
  `get_my_exercise_history` and every completed set before it in the same exercise this workout,
  by the exercise's `kind`: `load` (heavier, then more reps; only sets with a load above 0 rank),
  `reps` (more reps) or `assistance` (less machine help, 0 is unassisted, then more reps). Sets
  without reps never rank. With no history the exercise shows "First log" and no set is a new best;
  with unknown history (offline, no saved copy) neither is shown. Un-ticking a set recomputes.
- **Weight lifted.** `sum(load_kg × reps)` over completed sets with a logged load above 0, exactly
  as entered (a dumbbell load is not doubled). Bodyweight sets and `assistance` exercises are
  excluded. Rounded to 0.1 kg.
- **Rest timer.** The end time is stored in the local workout draft, so a killed app resumes the
  same rest; ±15 s moves the end, skip ends it, and a rest that ended while the app was closed is
  cleared on resume.

`workout_sessions.completion_source` is `manual` or `healthkit` (null for sessions with no audit
evidence). The app reads it, never the session notes, to say a workout came from Apple Health.

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

### Day Level (Train load sheet, 2026-10-03)

`get_my_training_hub` 1.6 returns `daily_load`: the 28 local days ending on the athlete's local
today, each with `strain` (the session-strain sum above), `minutes`, `sessions`, `recorded`,
`effort_reported` and `level`.

```text
reference(d) = strain of days in [d-28, d-1] that were trained, had strain > 0,
               and where every session's effort was athlete-reported
if no session on d                      -> level = rest
elif any session on d used a default    -> level = null ("Calibrating")
elif count(reference(d)) >= 8:
    p33, p67 = percentile_disc(0.33), percentile_disc(0.67) of reference(d)
    strain <= p33 -> easy;  strain <= p67 -> moderate;  else hard      (ties go lower)
else (fixed cut-offs):
    strain < 20 -> easy;  strain <= 40 -> moderate;  else hard
```

For scale: 40 minutes at effort 5 is 20; 50 minutes at effort 8 is 40. Default-effort days stay
out of the reference set so a constant default is never presented as personal intensity.
`reference` reports which rule applied (`personal` or `fixed`). The classified day never counts in
its own reference.

### Progression from the Logged Sets (B3, 2026-10)

Next-session targets are arithmetic on the sets the athlete logged. They are computed in the
database (`private.next_session_targets`, `private.progression_decision`, migration
`20261017140023`) and reported as `next_targets` in `get_my_training_hub` 1.7. The coaching
standard's double progression (`_shared/training/standard/progression.ts`: ACSM 2009, Helms 2016)
is the model: reps rise inside the plan's range first; the load rises by one step only when every
working set reached the top of the range with the planned reps in reserve, then the reps restart
at the bottom.

```text
history      completed sessions of the exercise in the last 180 days, matched as
             get_my_exercise_history does (catalog slug, else name; a substitution or an
             extra never joins a catalog exercise)
working sets the session's completed sets with reps > 0 at the session's top load
             (warm-ups, back-off sets and unticked sets are not working sets)
rir(set)     set.rir, else 10 - set.rpe (0 to 5), else unknown
rir_target   10 - target_rpe, rounded (2 when the plan sets no RPE)
step         exercise_catalog.load_step_kg; none for bands, benches, bars and exercises
             without a catalog link (those progress by reps only)
assisted     assisted-* slug or "assisted ..." name: the load is machine help, the working
             load is the least help (0 = unassisted, kept), add_load = max(0, help - step)
             (nothing left at 0: hold), lower = help + step

first match wins, on the latest session (s1) and the two before it (s2, s3):
  pain flagged on s1 or on any later performance
    (even one with no completed set)            -> hold
  days since s1 >= 28 and a step exists         -> lower: load - step, reps = range minimum
  days since s1 >= 14                           -> hold
  skipped after s1                              -> hold
  min reps < range minimum                      -> twice at this load: lower; else hold at minimum
  sets done < planned sets                      -> hold (a cut-short session is never a stall)
  3 sessions at one load, reps < range maximum,
    reps per set(s1) <= reps per set(s3)        -> stall: lower (hold without a step)
  min rir < rir_target                          -> hold
  min reps >= range maximum                     -> add_load: load + step, reps = range minimum
                                                   (hold at the maximum without a step)
  otherwise                                     -> add_reps: min(range maximum, min reps + 1)
```

A hold repeats the last result (reps clamped into the range). The target's sets are the plan's
set count. A target is never more than one step above the last logged load and its reps always sit
in the plan's range. An exercise with no logged sets has no target, so the plan's prescription
stands. Missing reps in reserve does not block a target but sets `confidence` to `low`. Heart rate
is never an input (decision D9). The 14-day and 28-day thresholds, the three-session stall and the
one-step lowering are Tracend's own choices, not research values, and wait for a coach's review.

### Same-day Readiness Adjustment (B4, rules `readiness-v1`, 2026-10)

Computed in the database (`private.readiness_assessment`, `private.day_adjustment_changes`,
`private.day_adjustment_compute`, migration `20261023140024`); the numbers are mirrored with their
sources in `_shared/training/readiness/rules.ts`, and a test keeps the two equal. It proposes one of
three kinds for **today's scheduled workout only**; nothing in a plan version changes, and a model
never proposes, applies or accepts it (decision D9; AI_SAFETY_SPEC section 6).

```text
inputs  today's current check-in (leads); sleep minutes (Apple Health, counted when 1 to 960;
        0 means none recorded); the recovery score with its confidence and mode (computed
        once for the day if missing; a failure leaves it missing)
        NOT inputs: acute:chronic ratio, monotony, strain, sleeping heart rate

points  sleep quality 1 / 2            2 / 1       energy 1 / 2           2 / 1
        soreness 5 / 4                 2 / 1       mood 1                 1
        pain 4-6                       2           pain 1-3               0 (a note)
        sleep under 360 minutes        1           recovery under 35      1, only at medium or high
                                                   confidence and only when the check-in has at
                                                   least one point of its own (D9)

gates   (first match wins)
        check-in pain of 7 or more     band red, kind none, safety route pain_referral
        no check-in                    band unknown, kind none (a low recovery score adds the
                                       trigger "recovery_low" and asks for the check-in)
        the athlete cannot train       band from the points, kind none
        otherwise, by points P:
          0     green  none
          1     amber  hold_load      (none when no exercise would change)
          2-3   amber  reduce_sets    (hold_load, then none, when no set can go)
          4+    red    swap_to_easy_cardio

confidence  high  = check-in + sleep + recovery at high confidence from a night
            medium = check-in + sleep or a recovery at medium or high
            low   = check-in alone;  unknown band has none
```

What each kind changes (per exercise of today's workout; the rest of the week is untouched):

```text
hold_load            where B3's target is add_load or add_reps: the last working load (for an
                     assisted exercise the help; "body weight" or "unassisted" at 0) and the
                     fewest reps of that session, clamped into the range; sets and effort unchanged
reduce_sets          one set fewer on an exercise with 3 or more sets; effort one point lower,
                     not below 6 and never above the plan's; hold_load's loads. Needs at least one
                     set to go, else it falls back to hold_load
swap_to_easy_cardio  every exercise to 0 sets; 20 to 30 minutes of easy cardio you can talk
                     through (vigorous not allowed)
```

A load is never above the last logged one, sets never go up, and effort never rises. The sentences
are fixed templates keyed by trigger and kind. Availability: `no_plan`, `rest_day`,
`session_started`, `session_done`, `coach_adjusted` (a Coach next-session block already ends
today). Only the athlete's own local today can be read or answered.

**Answers.** The athlete accepts the proposed kind, or chooses any kind that would change today's
session (`options`), with one tap, and can Undo until the session starts (at most 20 answers a day;
Undo of a standing accepted answer is never refused). The sentence of a choice depends on the kind
alone, not on whether the athlete has checked in. Each answer is stored with the kind the rules
proposed at the time. An answer stands while it belongs to today's workout and the rules do not now
ask for something stricter than what they asked then or than what the athlete answered (kind order:
none, hold_load, reduce_sets, swap); otherwise the card asks again and names the answer it replaces
with the reason, `check_in` (a different check-in) or `new_data` (sleep or scores that arrived
since). A standing answer replaces only the kind, status, changes, cardio and origin; the band and
reasons stay today's. A safety route wins over every stored answer and over a started or finished
session: the payload then carries the referral and none of the old answer.
`start_workout` takes the athlete's lock for the day (the one `respond_to_day_adjustment_v1`
takes), then applies and links the current accepted answer for this workout when the start is for
the athlete's own today, whatever the rules say now: it can only make the day easier, and asking
again is the card's job. It builds the adjusted set counts for `reduce_sets`; for `hold_load` and
the easy-cardio swap it links the answer and keeps the plan's sets (the plan stays usable); a start
for another date gets the plan as written; the app pre-fills held loads. Today's scores are made
when none exist and again when Apple Health data arrived after them, at most once in ten minutes
per athlete and day, failed attempts included.

**B3 meets the adjustment.** An exercise that an accepted hold_load or reduce_sets answer lists, done
in that session, is `adjusted`; its planned set count is the adjusted one (`sets_planned`). An
exercise the answer left alone is judged as ever, however easy the rest of the session was. In the
progression decision an adjusted session never counts towards lowering a load (rule 4, below the
range, holds at the minimum instead of lowering; rule 6, a stall, needs three unadjusted
sessions), and rule 5 compares the sets with `sets_planned`. A good performance on a lighter day still earns add reps or add load.
A single poor workout never restructures training (PRD section 5.3).

In-house numbers needing a coach's review after four weeks of the owner's data (O2): the points, the
band cut-offs, the pain bands, 360 minutes and 35. Sources are in `rules.ts`: Saw 2016 (the check-in
leads), Craven 2022 (six hours), Hickmott 2022 (easing back on a poor day), Bell 2023 (fewer sets is
the way to cut volume), ACSM 2011 and WHO 2020 (the cardio dose), Impellizzeri 2020 (why the load
ratio is not used).

### Literature

- Gabbett, T.J. (2016). The training-injury prevention paradox. *Br J Sports Med* 50(5), 273–280.
- Foster, C. (1998). Monitoring training in athletes with reference to overtraining syndrome. *Med
  Sci Sports Exerc* 30(7), 1164–1168.

### Heart-Rate Profile (C3, 2026-10)

Deterministic arithmetic over stored summaries; code lives twice (Dart
`lib/features/workout_hr/heart_rate_profile.dart`, TypeScript
`supabase/functions/_shared/training/heart_rate/profile.ts`) and both must give the results in
`profile_cases.json`. Heart rate informs (rest, cardio dosing, recovery talk, a question); it never
sets a load or a prescription (D9). Sleeping heart rate is **not** an input (D10, shadow mode).

- **Resting heart rate:** the median of the Apple Health daily values of the last 14 days (values
  30–120 bpm), from at least 3 days; otherwise missing.
- **Estimated maximum:** Tanaka, Monahan and Seals (2001): `208 - 0.7 x age`, rounded, for ages 16 to
  90 (their sample was 18 to 81, residual about 10 bpm); no birth year or an age outside the range
  gives no formula. An **observed peak** replaces it when it is the highest trusted peak and is above
  the formula. A set peak is trusted only when the set came from a Watch workout (`watch_workout`),
  has at least 8 readings and covered at least 60% of the set and the minute after it, and is at least
  120 bpm and at most the formula plus 20 bpm (two residuals; 210 bpm with no age). Wrist sensors spike,
  so a peak above that ceiling is ignored, not clipped. Lifting sets rarely reach a true maximum, so the
  formula usually stands until a hard effort exceeds it. With neither, the maximum is missing.
- **Zones:** heart-rate reserve (Karvonen, Kentala and Mustala 1957): `resting + fraction x (max -
  resting)` at 50, 60, 70, 80, 90 and 100% of reserve, five zones (Easy, Aerobic, Tempo, Hard,
  Maximum), the five-zone layout common to heart-rate watches; the anchors agree with the ACSM
  Guidelines (moderate 40–59% of reserve, vigorous 60–89%, near-maximal 90% and above). Cut points are
  rounded to whole beats; each zone ends one beat below the next one's start, the last at the maximum.
  Below 50% is no zone. Zones need a resting heart rate and a maximum with a reserve of at least 20 bpm;
  otherwise the reason (`no_resting`, `no_max`, `narrow_reserve`) is shown and no zone is drawn.
- **Recovery after sets:** the median `drop_60s_bpm` of qualifying sets in the last 28 days against the
  28 days before, both from at least 6 sets. A set qualifies with a 60-second drop, coverage of at least
  60% and an end heart rate at least 20 bpm above resting (100 bpm when resting is unknown). A change of
  3 bpm or more is "improving" or "slower"; less is "steady"; fewer sets in either window is "not enough
  data". It is a trend of the athlete against themselves; one-minute recovery after maximal exercise
  (Cole et al. 1999, N Engl J Med 341:1351–1357) has no threshold for lifting sets, so none is used.
- **Sleeping heart rate (shadow):** per night from Apple Health sleep (sessions joined across gaps up
  to 1 hour, dated by the day they end, at least 3 hours asleep, awake time removed): the median of
  readings asleep, the lowest mean of any 10-minute slot holding at least 2 readings (a night with none has no row), readings, minutes asleep and coverage of
  10-minute slots. A night is stored only with at least 20 readings and 50% coverage. No score uses it.

### Heart-Rate Load Signals (C4, 2026-10)

`supabase/functions/_shared/training/heart_rate/load_signals.ts`: arithmetic over the last 28 days of
finished workouts (`get_workout_load_inputs_v1`, no load, repetitions or reps in reserve) and the
heart-rate profile above. Heart rate informs rest, recovery and confidence; it never sets a load, a
repetition target or a set count (D9), and no signal raises confidence. Sleeping heart rate is not an
input (D10). The thresholds are Tracend's own choices, not research values, and wait for a coach's
review. The output is only `engine: {confidence: none | lower, rest: none | allow_longer, reasons}`.
Coach reads it in the plan context (AI_SAFETY_SPEC section 11.1): a fixed sentence on a step up
(`add_load` or `add_reps`) when confidence is `lower`, a fixed rest sentence once per session when rest
is `allow_longer`. The signals do not ask the athlete a question (B4 may add one later).

- **Tracked set:** a `watch_workout` summary with coverage of at least 60% (the same line the
  Watch-workout suggestion uses to count a tracked set).
- **Start of set:** for tracked sets with a start heart rate and a rest of at least 30 seconds before
  them (a shorter one is a set ticked during its own rest), the share of heart-rate reserve at the
  moment the set began: `(start - resting) / (maximum - resting)`. Needs a resting heart rate and a
  maximum with a reserve of at least 20 bpm (the profile's zones), at least 12 such sets in at least 2
  workouts; otherwise it fires nothing. The middle (median) share at or above 50% of reserve (where the
  Easy zone begins) is elevated. Elevated with a middle rest under 120 seconds is `rest_short` (rest
  `allow_longer`; confidence unchanged, since a longer rest is the cure); elevated with a middle rest of
  120 seconds or more is `slow_settling` (confidence `lower`). This is a fixed line, not a comparison with
  the athlete's usual, so it is never worded "than usual".
- **Recovery:** the profile's recovery state `slower` (a 60-second drop at least 3 bpm below the 28 days
  before) is `recovery_slower` (confidence `lower`); it is a comparison with the athlete's own earlier
  weeks and the only reason that may be worded "slower than usual".
- A heart rate a medicine blunts (beta-blocker) reads low, which only removes a caution.

### Literature

- Tanaka, H., Monahan, K.D., Seals, D.R. (2001). Age-predicted maximal heart rate revisited. *J Am
  Coll Cardiol* 37(1), 153–156.
- Karvonen, M.J., Kentala, E., Mustala, O. (1957). The effects of training on heart rate: a
  longitudinal study. *Ann Med Exp Biol Fenn* 35(3), 307–315.
- Cole, C.R., Blackstone, E.H., Pashkow, F.J., Snader, C.E., Lauer, M.S. (1999). Heart-rate recovery
  immediately after exercise as a predictor of mortality. *N Engl J Med* 341(18), 1351–1357.
- ACSM (2021). *ACSM's Guidelines for Exercise Testing and Prescription*, 11th ed., intensity
  classification by percent of heart-rate reserve.

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
  **B7:** a reading that cannot be real against its neighbours is excluded before any window is
  fitted (the rule below) and listed as "Excluded reading" in the section.
- **Weight projection (labeled estimate):** the current pace is the 4-week trend (the 8-week trend
  when the 4-week one lacks readings). The other window widens the range only when it points the
  same way. Under 0.05 kg/week the weight counts as stable and no date is projected. The section
  lists the weeks to each of the next 10 whole kilograms in the trend's direction (plus a goal
  weight, if one is stored), capped at 104 weeks, and the weight expected in 4, 8, 12 and 26
  weeks. **B7:** a trend is history, not a goal, so the "weight in N weeks" rows appear only while
  the athlete's own target weight is still ahead of the current weight; the "reach N kg" rows also
  appear only then and stop at the target; no row (kilogram or horizon) goes below the healthy-BMI
  floor (BMI 18.5 at `height_cm`; with no height the floor is
  unknown and only the target rule applies). With no target weight the section shows the pace and
  nothing about a future weight.
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

### Goal phase review (B7, 2026-10)

`supabase/functions/_shared/training/goal_phase/**`. Coach chat saw about six weeks of weight, called
a 15 kg loss "7 kg" and projected a weight the athlete read as advice. The phase summary and review
are deterministic and reach Coach as a Contract 7 contributor (`goal_phase`, volatile slot, 2,200
characters); the model explains the outcome and never sets it.

**Inputs** (`get_goal_phase_inputs_v1`, service role): the active goal (type, the date it was
activated in the athlete's time zone, target), `height_cm`, and every current weight reading (body
measurements with a weight, an amended reading replaced by its amendment, plus HealthKit daily
weights only on dates with no body measurement, as above; newest 400). The goal's saved `current_weight_kg` is
never a start weight.

**Implausible readings.** A reading is excluded when it is further from the reading before it and
the reading after it than `neighbour_kg x (3% + 1.5% x weeks between them)`. An end reading is
judged against its one nearest believed neighbour. Fewer than three readings are never judged.
Excluded readings are reported, never silently dropped. The same rule runs in the Coach calculators
(`weightReadings` in `coach_calculations.ts`).

**Summary.** Phase start is the goal activation date (the first reading when it is unknown). Start
and current weight are the median of up to three readings within seven days of the first and last
reading in the phase. Change is current minus start, in kg and as a percentage of the start;
weeks are first to last reading; the average rate is change over weeks (kg and % of start weight a
week); the recent rate is the least-squares slope of the last 28 days (at least three readings
spanning 14 days). BMI is weight over height squared when height is known. Confidence is high
with eight or more readings over at least four weeks and a known activation date, low when the
latest reading is older than 14 days or fewer than three readings exist.

**Recorded history (B7.1).** The goal is often activated well after the weight started to fall
(production case: goal activated 3 July, first weight 90.0 kg on 3 June, 74.8 kg on 13 October:
-15.2 kg and -16.9% over 18.9 weeks, against -8.2 kg and 13.7 weeks inside the goal). The summary
therefore also carries a `history` block over every kept reading, ending at the same current weight as the phase (the latest weight smoothed over all kept readings, so every rendered change equals start minus current) (the implausible-reading
exclusion applies): the first reading's date and smoothed weight (median of up to three readings
within seven days, like the phase start), change in kg and %, weeks and reading count. It is
present only when the first reading is at least 7 days before the first reading of the goal phase
(`historyMinimumLeadDays`), so a history equal to the goal phase adds no second line. Coach sees
both blocks with their dates, the history first.

**Continuous loss.** `continuousLoss` is the run of falling weight that ends now. Walking back from
the current weight, each higher smoothed reading moves the run's start back to it; the walk stops
at a reading lower than the high so far by more than 3% (`continuousRunTolerancePct`, the day-to-day
scatter), because the weight was rising before that (a gain phase or a rebound). So after a gain
the run starts at the high point, and a diet-break rise under 3% does not end it. It is kept only
when it differs from the goal phase: a start before the goal phase must also sit at least 3%
above the phase's start weight (a flat stretch before the goal is not a loss that began earlier),
and a start after the phase began (weight rose, then fell inside the goal) is kept as it is. The
run needs a loss and at least 2 weeks. Its start, weight, change, weeks and whether it began before the goal are rendered
as "Continuous loss", or folded into the history line ("one continuous loss") when it starts at the
first reading.

**Evidence for a run.** Two weights months apart do not show a continuous loss. A run (and the
history) is *confirmed* only with at least 4 readings (`runMinimumReadings`) and no two consecutive
readings more than 35 days apart (`runMaximumGapDays`); both are in-house values. A run that is not
confirmed never feeds the review (the rules fall back to the goal phase and its pace), and the
history and run lines say "sparse readings, trend not confirmed". The RPC returns the newest 400
readings; when the input holds 400, the history line reads "the newest 400 readings, from DATE
(older readings may exist)" instead of "all weight readings", so a capped window is
never presented as the whole journey.

**Block order.** The host clips a contributor block from its tail, so the text starts with the review outcome and its reasons; at most 3 excluded readings are listed, the rest counted ("and N more").

**Review outcomes**, first match wins:

1. `target_reached`: the target weight is met within 0.5 kg in the goal's direction.
2. `consider_maintenance_or_diet_break`: BMI below 18.5, or, while the weight is still falling
   (at least 0.1 kg a week), any of BMI below 19.5, 16 weeks or more with a loss of at least 5%,
   12 weeks or more with a loss of at least 10%. The two loss rules judge the confirmed continuous loss
   (its weeks and its % from its high point) whenever one exists, else the goal phase; the
   reason text names the date the run began (the first reading when there is no separate run).
   "Still falling" reads the recent rate, else the confirmed run's average rate, else the phase
   average, so a sparse history whose phase rose but whose run fell is still judged. **One
   staleness rule:** when the latest reading is older than 14 days, no rate of any kind (recent,
   run or phase) counts as losing now, so the rate-driven outcomes (`slow_down`, the 16-week and
   10% rules, BMI near the floor) cannot fire; only the absolute-state reasons (BMI below 18.5,
   target reached) can, and their text names the reading's date. The text Coach sees never says
   "now" or "current" for a weight: it reads "latest weight 74.4 kg (median of the last 3 readings, up to DATE, N days ago)" (or
   "reading on DATE" when one reading is used) in the history, run, phase, BMI and reason lines, fresh or stale, and a stale average rate carries a note that
   it is not evidence of the present trend. The
   history and the run are shown even when the goal is days old and the phase has no rate yet. The pace rule (`slow_down`) and the precedence of the
   outcomes are unchanged.
3. `slow_down`: a loss above 1% of body weight a week after at least three weeks.
4. `ask_target`: the goal has no weight, body-fat range or physique target.
5. `continue`.

`needs_target` is true whenever a goal has no target, whatever the outcome, so Coach asks for one
even beside a safety outcome.

| Value | Basis | Source |
| --- | --- | --- |
| BMI floor 18.5 | Bottom of the healthy adult range; targets and projections never go below it | WHO 2004 |
| 1% of body weight a week | Athletes keeping muscle lose 0.5 to 1% a week; 1.4% a week lost lean mass | Helms 2014; Garthe 2011 |
| 16 weeks, 5% | A 16-week continuous deficit; intermittent arms lost more; 3 to 5% is clinically meaningful | Byrne 2018; Trexler 2014; Jensen 2014 |
| 10% at 12 weeks | Top of the 5 to 10% first-goal range | Jensen 2014 |
| 19.5, 3 weeks, 0.1 kg, 0.5 kg, 3%, 1.5%, 12 weeks, 14 days, 3% run tolerance, 7 days history lead, 4 readings and 35 days gap for a run | Tracend in-house values | listed for owner review in `docs/handoff/training-engine.md` |

Sources and DOIs live in `goal_phase/sources.ts` (each checked against Crossref, 2026-10-17).

**Reply check.** After every Coach answer a deterministic check refuses a sentence that is below
the healthy-BMI floor and looks ahead or proposes a target, or (with no target) a sentence with a
time or pace cue ("in 12 weeks", "by March", "at this pace", "if you keep going") naming a weight
beyond today's in the direction of the trend. Questions and sentences that propose a target ("aim
for 70 kg", "a goal of 72 kg") are not forecasts unless they also carry a pace cue. A limit word
("below", "under", "less than") excuses only the weight it directly governs. See `docs/AI_SAFETY_SPEC.md` section 11.

### Literature

- Standard ordinary least squares regression methodology. Neter, J. et al. (1996). *Applied Linear
  Statistical Models*.

---

## 6. Macro Adherence

### Complete logging day (A10, 2026-10)

An athlete who logs breakfast and nothing else has not eaten 400 kcal. A logging day is
**complete** when it has at least 3 confirmed meals **or** its confirmed energy reaches 70% of the
active calorie target. Every other day with a confirmed meal is **partial**, and a day with no meal
is unknown, never zero. One definition serves every reader: `private.nutrition_complete_day_rules()`
holds the numbers (`min_meals` 3, `min_target_share` 0.7) and `private.nutrition_day_totals()`
returns each day's meals, energy, macros and `complete` flag. `evaluate_change_eligibility`, the
Coach `nutrition_state` contributor and the `meals` lookup all read it.

- The contributor reports "k of n logged days are complete", averages **complete days only**
  against the target, and lists the partial days as partial.
- Only confirmed meals with confirmed items count.

### Formula

```text
macro_adherence_pct = avg over complete days of
                      (daily calories / target_calories * 100) capped at 200%
```

- 14-day window: target_date - 13 through target_date (inclusive)
- Only complete days enter the average (they were all-day logs). `evaluate_change_eligibility`
  reports the number of complete days it averaged (`nutrition_change.complete_days`).
- Returns null when: no active nutrition target, no complete day, or target calories = 0
- `compute_daily_metrics` still averages every logged day for the daily score the app shows; the
  change-eligibility gate and the Coach use the complete-day rule.

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
| AND Adherence Minimum       | ≥ 80% macro adherence over the complete logging days of the last 14 days (section 6) |
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
| Eligibility          | `policy_version`       | `eligibility-v2` (A10: nutrition adherence averages complete logging days; v1 rows stay as written) |
| Training hub RPC     | `schema_version`       | `1.5`        |
| Daily brief RPC      | `schema_version`       | `1.6`        |
| Onboarding plan      | `policy_version`       | `onboarding-policy-v2` |
| Exercise catalog     | `catalog_version`      | `catalog-v1` |
| Onboarding proposal  | `schema_version`       | `2.0`        |
| Coach proposal       | `schema_version`       | `3.0`        |

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
  for intermediate and advanced lifters. ACSM 2026 gives about 10+ sets per muscle a week;
  Schoenfeld 2017.
- **Coverage:** every week includes a squat or lunge, a hinge, a push and a pull. A pattern the
  athlete avoids is not required; a group with no pattern left that they can do is dropped.
- **Movements to avoid:** squat, lunge, hinge, horizontal push, vertical push, horizontal pull,
  vertical pull. Every exercise with an avoided pattern is excluded.
- **Prescription ranges:**
  - Reps 6–20, or 3–20 for strength (6–20 until a moderate-effort screening outcome clears).
  - RPE 7–8.5 for beginners (RIR 2–3) and 7–9 for intermediate and advanced lifters (6–7 until
    cleared).
  - Rest 60–180 s, or up to 240 s for strength.
  - Sets per exercise 1–5.
- **Blocks:** 4–8 weeks before a review. The app repeats one weekly template, so the plan never
  promises a deload or a different week; progression is adding reps or load within the ranges.
  (Deloads in practice come about every 5–6 weeks, Sports Med Open 2024, and need a week-by-week
  plan the app does not have yet.)
- **Rules plan:** see "Templates and fractional volume" below. In short: the same limits, a
  template chosen by split, goal, experience and session length, prescriptions from the coaching
  standard, and weekly sets spread toward the standard's volume. It is validated before use;
  answers it cannot meet are refused as infeasible (see AI_SAFETY_SPEC §6), never stored. Deno
  tests prove it is valid for every equipment set × 1–6 days × both paths × every goal ×
  30–120 minutes × every screening outcome; its nutrition is valid and storable for 14,400
  combinations of body size, age, activity, goal, sex and schedule; and it is valid with any one
  movement avoided.

### Week ahead and back-to-back muscles (2026-10-18)

Code: `supabase/functions/_shared/training/schedule/` (`muscles.ts`, `week_ahead.ts`), the schedule
resolution in `coach_context/contributors/training_plan.ts`; rule value
`minimumDaysBetweenSessionsPerMuscle` in `training/standard/volume.ts`. Deterministic: the model
explains the result and may offer a change as a proposal the athlete approves; it never decides it.

- **Schedule.** The seven days from the athlete's coaching date (their own local date, not the
  calendar week), one line each with the session and its muscles. The plan repeats weekly; after a
  temporary block's last day the sessions are those of the plan the block replaced. Inside the
  athlete's ISO week a session already finished (even early, as a swap) is not planned again: its
  slot says when it was done. From next week on every session is planned again. Overlaps are
  computed from the same resolved schedule.
- **Undone sessions.** Sessions of earlier days this week that are still undone are stated as a
  fact. One is made up today only when it is not tomorrow's own session (tomorrow covers that one)
  and does not train a muscle tomorrow's session trains: the first undone session that is not
  tomorrow's is the candidate; if it repeats tomorrow's muscles nothing is made up and the day says
  so, with the muscles.
- **Muscles of a session.** The catalog's primary muscles of each exercise, summed over its sets
  (logged sets for a finished session, planned sets for the rest); a muscle counts at 2 direct sets,
  the standard's weekly minimum (4) over its minimum sessions a week (2). The catalog's `shoulders`
  group is split by the exercise's movement pattern: `rear_delts` work (face pulls, rear-delt flies)
  is "rear delts", every other exercise listing shoulders is "front and side delts". Exercises
  without catalog muscles are counted as unknown and said so.
- **Overlap.** Two sessions, done or planned, on consecutive calendar dates (fewer days between
  them than the standard's 1) that train a common muscle, where the later session is today or within
  the next 2 days. A rest day between them ends the pair. Yesterday's finished session counts. The
  data are dates, not times, so no hour count is used. No overlap, no line.

### Templates and fractional volume (B2, 2026-10)

Code: `supabase/functions/_shared/training/templates/` (the week's shape and volume counting),
`onboarding/rules_plan.ts` (exercise choice, prescription, set spreading). Values from the coaching
standard (`_shared/training/standard/`, B1) are cited there; the choices below are Tracend's.

**Template choice.** The policy still decides the split from the number of days (table above);
the template then depends on the goal, the experience and the session length.

| Input | What it changes |
| --- | --- |
| Days (split) | Full body A/B/C for 1–3 days; Upper A/B + Lower A/B for 4; Upper A, Lower A, Push, Pull, Legs for 5; Push, Pull, Legs, then Push 2, Pull 2, Legs 2 for 6 |
| Goal | Strength: main lifts every session, two accessories at most. Muscle gain: shoulders, arms, calves and trunk after the lifts. Aesthetic: shoulders, rear delts and arms first. Fat loss and recomposition: compound-led, trunk first, few isolation exercises |
| Experience | A beginner keeps at most 2 accessory exercises a session (in-house); only an intermediate or advanced lifter is offered pull-ups (catalog level); an advanced lifter gets the advanced variant below |
| Session length | Slots are in priority order (main, support, accessory); a session keeps as many from the top as its exercise limit (2 + minutes / 15) and set budget (minutes / 3) allow. Length also sets rest (below) |

The plan names a template id (split, days, profile, experience, length) in the Deno tests; the
rationale text names the split and the goal.

**Exercise choice (owner decision 2026-10-15).** Full-gym plans use the lat pulldown for the
vertical pull; the second vertical-pull slot of a week (full body C, Upper B, Pull 2) rotates, so an
intermediate with a pull-up bar gets the pull-up as the variation. Trunk work rotates: a trunk
exercise is not reused in a week while another is available, and loaded and bodyweight forms count
the same there. A regression is never the variation.

**Fractional volume.** One working set counts 1 toward the target muscle and the exercise's other
catalog muscles, and 0.5 toward each secondary muscle (catalog v2; Pelland 2026, fractional method).
Weekly targets (indirect sets included): strength goals 6 (2 sessions × 3 sets, the standard's
frequency and strength sets); other goals the growth level of 10, then, with spare session room, a
stretch halfway to the experience's maximum (11 beginner, 15 intermediate, 16 advanced from a growth
level of 12); trunk 4 (the minimum),
because every lift braces it. The rules plan starts every exercise at 2 sets, brings the main lifts
to 3, then adds one set at a time where the weekly shortfall is largest (a main lift before an
accessory when equal). An added set never passes the session set budget, the session length, the
exercise count, the policy's weekly maximum for the exercise's target muscle (12 beginner, 20
intermediate, direct sets as before), or the standard's maximum for that muscle with indirect sets
counted. The plan the spreading starts from is not trimmed, so a muscle many exercises train
indirectly (glutes) can pass the standard's maximum when counted fractionally; only the policy's
direct count is a hard limit. An exercise stops at 4 sets (3 for strength goals or isolation).

**Reconciling the standard with the policy.**

| Point | Standard | Policy (before B2) | Rules plan now, and why |
| --- | --- | --- | --- |
| Strength compound rest | 180–300 s | cap 240 s | 120 s in sessions of 45 minutes or less, 180 s up to 75 minutes, 240 s from 90 minutes. 240 s is the policy cap, kept because 300 s rests would cost most of a 60–90 minute session (each set also costs 45 s of work); the short-session 120 s is below the standard's 180 s because longer rests cannot hold the four movement patterns in 45 minutes |
| Beginner strength reps | 8–12 | rules plan 4–6 | 8–12, the standard's novice range (ACSM 2009): heavy loading comes after the technique is learned. The policy minimum of 3 reps still applies to a model plan |
| Intermediate strength compound reps | 3–6 | rules plan 4–6 | 3–6 (the policy's lowest allowed count) |
| Hypertrophy compound rest | from 90 s | 150 s (120 s in short sessions) | 90 s in sessions of 45 minutes or less, otherwise 120 s; both inside the standard (Singer 2024: no clear gain beyond 90 s) and shorter than before, which leaves room for more sets |
| Hypertrophy compound reps | beginner 8–12, intermediate 6–12 | 8–12 / 6–10 | the standard's ranges |
| Isolation reps | 10–15 (strength: 8–12 beginner, 6–12 intermediate) | 10–15 | the standard's ranges |
| Effort | reps in reserve 2–3 beginner, 1–3 intermediate and advanced | RPE 7–8.5 / 7–9 | compound lifts stop at the middle of the range (RPE 7.5 beginner, 8 intermediate and advanced), isolation at 2 reps left (RPE 8); the half point for short sleep still applies |
| Weekly sets | 4 minimum, 10 growth, 12/20 maximum | at most 12/20, no minimum | as above; the model path keeps the policy's direct-set limit |

**Screening (Contract 8).** `PlanPolicies.screening` is optional; a missing outcome means `cleared`.
`moderate_until_cleared` (`trainingPolicy`): no strength emphasis (the 3-rep floor becomes 6, rest at
most 180 s, the strength goal builds the general-fitness template with hypertrophy reps), effort at
most RPE 7 (at least 3 reps in reserve, range RPE 6–7), and no conditioning, which the rules plan
never contains. The athlete sees a note first in the plan's assumptions, and the model prompt carries
the same cap. `see_professional` builds no plan: `buildRulesPlan`, `validRulesPlan`,
`validateOnboardingPlan` and `generateOnboardingProposal` throw `PlanBlockedByScreeningError` before
any model call, and the caller answers with professional guidance (today's excluded path: the app
stops at the eligibility step and nothing is built).

### Advanced level (2026-10-23)

Code: rule values in `training/standard/{prescription,volume,sources}.ts`, the week in
`training/templates/advanced.ts`, exercise choice and prescription in `onboarding/rules_plan.ts`,
the athlete's choice in `onboarding/answers.ts` and the onboarding Training step, and the four staple
lifts in the catalog (`catalog.ts`, `catalog_v2.ts`, migration `20261023100050_advanced_level_catalog.sql`).
Existing athletes keep their level; the level changes only when the athlete chooses it again in
onboarding (a new plan version they approve) or Coach proposes and they approve a change.

**Who is advanced.** The athlete, from three years of training. The Training step asks which fits
better (intermediate or advanced) once "3–5 years" or "Over 5 years" is chosen; the server reads
`experience: "advanced"` only with those years and otherwise reads intermediate (under a year stays
beginner). ACSM 2009 calls an advanced lifter one with years of training; the three-year cut is
in-house, because the answer bands are "1–2" and "3–5" years.

**The numbers, and what each rests on.** A level with no source of its own uses the nearest cited value
and says so.

| Rule | Advanced | Intermediate (unchanged) | Source and note |
| --- | --- | --- | --- |
| Weekly sets, build-up level (indirect sets count 0.5) | 12 | 10 | Baz-Valle 2022: below 12 sets was its low-volume group, 12–20 its standard for trained lifters (at least a year of training; no study separates advanced lifters) |
| Weekly sets, stretch with spare room | 16 (halfway from 12 to 20) | 15 | the halfway rule is in-house (`stretchTarget`) |
| Weekly sets, maximum | 20 | 20 | Baz-Valle 2022 found no gain above 20 for the quadriceps or biceps; Pelland 2026: returns diminish. No source puts advanced lifters above 20 |
| Strength weekly target | 6 | 6 | ACSM 2026 (2 sessions × 2–3 sets) |
| Training days a week | 4–5 (a note when fewer) | 3–4 | ACSM 2009; Pelland 2026: frequency matters little for size once volume is counted |
| Sessions per muscle | 2 or more | 2 or more | ACSM 2011/2026 |
| Compound reps | strength 3–6, size 6–12 | same | ACSM 2009 gives intermediate and advanced lifters one recommendation (1–12 RM, eventual emphasis on 1–6 for strength and 6–12 for size); ACSM 2026: ≥ 80% 1RM for strength |
| Heavy and light days | heavy takes the lower part of the compound range, light the upper | none | ACSM 2009 (periodized); Moesgaard 2022: undulating periodization gave trained lifters a small 1RM gain and no difference for size; ACSM 2026 finds no consistent periodization effect. The split point (lower half rounded down: 3–4 / 5–6, 6–9 / 10–12) is Tracend arithmetic on the cited range |
| Isolation reps | strength 6–12, size 10–15 | same | ACSM 2009, Iversen 2021 |
| Reps in reserve | 1–3 (compound mid-range, isolation 2) | 1–3 | Robinson 2024, ACSM 2026, Helms 2016; Refalo 2023 finds no gain from failure, so the range is not narrowed |
| Rest | by goal and session length, as before | same | ACSM 2009, Singer 2024 |
| Progression | double progression; one equipment step | same | ACSM 2009 (2–10%); no source sets a slower advanced rate, so none is invented |
| Deload cadence | none | none | no cited cadence; Bell 2023 gives only the purpose of a deload and Coleman 2024 tested one week off in week 5 of 9 without a cadence. The block model has no deload week; B5 owns deloads |

**Heavy and light days (periodisation inside the block model).** The block stays six weeks and the app
repeats one week, so the variation is inside the week. Every muscle meets a heavy and a light day:
full body A heavy, B light, C the whole range; upper/lower: both heavy sessions, then both light;
upper, lower, push, pull, legs: upper and lower heavy, the three others light; push/pull/legs twice:
the first pass heavy, the second light. Only compound lifts take the part range; isolation work keeps
its range. A heavy session's objective says so ("Heavy day: lower reps on the big lifts").

**Specificity.** The sessions are the intermediate sessions plus, in non-strength goals, one more
direct accessory where the session has room (below 8 slots): the first of a short list for that
session type that it does not already train directly (biceps, triceps, calves, chest fly, hamstring
curl, quad extension; no shoulder work, which presses and rows already carry past the standard's
maximum when indirect sets are counted). The single-leg slot of the first lower session prefers the
Bulgarian split squat, and the push day of the five-day split presses on an incline (`prefers` on
a slot: the exercise comes after a focus muscle that still needs sets and only until the week has
used it). The weighted pull-up and the close-grip bench press arrive through the normal rotation
of a lift not yet used that week.

**The staples.** `weighted-pull-up` (pull-up bar and dumbbells: a dumbbell held between the feet, load =
added weight, step 2.5 kg, 0 kg added is a real value for progression), `close-grip-bench-press`,
`incline-barbell-bench-press`, `bulgarian-split-squat`; all advanced level, so the plans of the other
levels are unchanged (the 10,080-case digests in `catalog_plans_test.ts` are untouched). The
conventional deadlift is `barbell-deadlift`. Joint stress is in-house: the weighted pull-up is
shoulder `high` (the pull-up is `moderate`), the two bench variations keep the bench press's
shoulder `high` (a narrower grip moves work to elbows and wrists, which are not rated, so no relief
is claimed), the Bulgarian split squat is knee `high`. A swap into a harsher exercise is never
offered; a swap away is.

**No muscle loses to a staple.** Preferring a staple can displace a lift that trained a muscle
(the weighted pull-up wins the vertical pull from the lat pulldown), and the higher advanced targets
move sets between exercises. After building, `buildAdvancedPlan` compares the plan with the same
athlete's intermediate plan: no muscle may end below the intermediate plan's weekly sets, capped at
the growth level (10). If one would, the fewest staples that restore it are left out; if none does,
all are left out; if the advanced targets alone still leave a muscle short, the plan keeps the
intermediate week's exercises and set targets with the advanced prescription and heavy/light
days. A sweep of 4,320 cases (5 goals x 6 day counts x 6 lengths x 4 equipment sets x 2 screening
outcomes x 3 focus sets) is a permanent test: before the rule 206 plans had a muscle short (132 of
them below the 10-set growth level where the intermediate twin met it), after it none do and 1,769
of the 1,800 plans with the equipment keep a staple.

**Progression with heavy and light days.** A lift planned more than once with different rep ranges
(an advanced plan's bench on a heavy and on a light day) keeps one history per range in
`private.next_session_targets`: only performances logged against a planned exercise with that range
count, so a heavy 100 kg x 9 is never read as a light day's 100 kg x 10. A lift repeated with the
same range, or planned once, keeps one shared history as before; a Deno test pins the redefinition
as B3's function plus exactly the changed hunks. The weighted pull-up is flagged `added_load` in the
catalog: its logged load is the weight added to the body, and no load and 0 both read as none added,
so a set of bodyweight reps at the top of the range earns the first 2.5 kg step. Other exercises
still read an empty or zero load as no load (a pull-up holds at the top of its range).

Matching by range has one consequence on a level change. An athlete who moves from an intermediate
plan (one range per lift) to an advanced plan has no target for a split lift's day until that day
has been logged once under its own range: the earlier sets, logged in the other range, are not read
as the new day's history. That day keeps the plan's prescription and is shown without a target.
This is deliberate: missing data lowers confidence and is never filled from another day's sets. A
next-session adjustment matches its target on the planned exercise id (`get_coach_proposal_inputs_v1`
1.1 carries it), so a heavy day's target is never applied to the light day of the same lift, and a
day without a target is adjusted from its planned load only.
A plan rebuild (a change of training days, a goal or a setup) carries each exercise's start load
the same way: a lift in one rep range carries by slug, a lift on a heavy and a light day carries
each range's load only to the same lift in the same range, and otherwise starts without one.

**Screening and safety.** Nothing about the screening gate changes: `moderate_until_cleared` caps
effort at RPE 7, drops strength emphasis and uses hypertrophy reps (split into heavy and light days
all the same); `see_professional` builds no plan; the avoided patterns, the joint-stress swaps and
every policy limit apply to the new exercises as to any other. Advanced never relaxes a policy limit.

**Measured** (the 7 equipment sets × 6 day counts × 5 goals × 5 lengths × 2 avoid × 3 focus sweep of
`catalog_plans_test.ts`, extended with 120 minutes, 6,300 plans per level, rules plan, intermediate
against advanced twin): sets per plan 52.2 → 53.2, exercises 18.3 → 18.5; weekly sets by muscle
(indirect at half) back 11.5 → 11.7, biceps 10.9 → 11.3, quads 10.2 → 10.5, shoulders 14.3 → 14.6,
triceps 12.4 → 12.7, chest 7.6 → 7.7, glutes 18.9 → 19.2. The growth targets rise (12/16 against
10/15) but session length and the 8-exercise cap bind first: weekly sets rise 0% at 30 minutes, 0.8%
at 45, 1.6% at 60 and 2.5% at 90 or more (a 90-minute session is already at the set budget of 30), and
283 of the 6,300 advanced plans carry slightly fewer weekly sets than their intermediate twin (1 to
3% in the cases inspected), because the staples change the mix of exercises. Chest remains the muscle the templates serve
least in 60-minute sessions (two pressing slots), for both levels.

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


### Home alternatives (A10, 2026-10)

For each planned exercise Coach is given catalog exercises that train the same movement without gym
kit, so it can build a routine for days away from the gym without inventing an exercise
(`_shared/training/home_alternatives.ts`). Candidates come from the exercise's catalog links
(substitutes, then regressions, then progressions) and then from the catalog exercises with the same
movement pattern and first-listed muscle (compound, beginner and alphabetical order break ties).
Two kinds, at most two each: **bodyweight** (no equipment) and **minimal kit** (only dumbbells,
kettlebells, bands or a pull-up bar). A movement pattern the athlete asked to avoid is left out. An
exercise outside the catalog has none. The plan itself is not changed; a different plan is a
proposal the athlete approves.

### Exercise history lookup (A10, 2026-10)

The `exercise_history` lookup returns, per completed session, the heaviest completed set, the sets
done and the fewest reps in reserve, and an estimated one-rep max by the Epley formula
(`load x (1 + reps / 30)`, sets of 1 to 12 reps with a load, the highest of the session). It is a
figure Tracend computes from logged sets; Coach quotes it and never recomputes it.

## 10. Coach Proposal Rules (`_shared/coach_proposals`, 2026-10)

Code: `supabase/functions/_shared/coach_proposals/`. Every number in a Coach proposal comes from
the rules below or from the onboarding policy (§9); the model chooses an intent. The refusals and
the approval flow are in AI_SAFETY_SPEC §6 ("Coach proposals").

- **Maintenance energy:** the middle of the policy's TDEE range (`nutritionPolicy`, §9), rounded to
  10 kcal. A diet break and a maintenance phase use it.
- **Calorie step:** "lower" or "raise" without a figure moves the target 5% of the current target,
  rounded to 10 kcal, never below the floor and never above 15% over the top of the TDEE range (the
  top of the muscle-gain range, §9). A figure the athlete asked for is used as given if it passes
  the same limits.
- **Limits on any target:** at least the calorie floor (the higher of the sex-based minimum and the
  resting energy); at most 6,000 kcal; at most the surplus cap; a loss of at most 1% of body weight
  a week (`goalPhaseThresholds.fastRatePctPerWeek`), where the weekly loss is the gap to
  maintenance × 7 ÷ 7,700 kcal per kg (the 3,500 kcal per pound rule of thumb, used only to size a
  gap, never to set a target); no loss target at BMI under 19.5.
- **Macros:** protein in the middle of the policy range, fat at a quarter of the calories inside the
  policy's minimum and maximum, carbohydrate the remainder (at least 20 g); macros add up to the
  calories within 5%.
- **Fat-loss phase:** the gentler end of the fat-loss range (−10% of TDEE); needs the nutrition
  change gate (§7) and a goal phase review that does not already call for a maintenance period.
- **Diet break:** 2 weeks (`goalPhaseThresholds.dietBreakWeeks`, the 2-week breaks of the MATADOR
  intermittent arm) at maintenance energy, only in a fat-loss goal or cut phase. The goal stays fat
  loss; nutrition does not revert by itself at the end.
- **Target weight and date:** at least the weight at BMI 18.5 for the athlete's height (§5), on the
  right side of the current weight for the phase, a date within three years, and a pace within the
  1% a week ceiling (otherwise the earliest date that fits is given).
- **Temporary block:** up to 42 days, starting when approved (a start date at most 2 days ahead).
  Sessions are the rules plan (§9) for the equipment left (bodyweight, or the portable equipment the
  athlete owns), on the athlete's training days, inside the same weekly volume, effort and length
  limits. The block's last day is the end date given; the regular plan returns the day after.
- **Schedule:** the rules plan for the new days (kept where possible, new days placed furthest from
  the others) and length; loads of exercises that stay are carried over; the block length given is
  the review period, and the schedule stays until changed.
- **Swap:** only a B1 catalog substitute of the exercise, owned equipment, an allowed movement, and
  no harsher than the original on the knee, back or shoulder; same sets, reps and effort; no
  starting load; weekly sets for the new target muscle stay inside the policy maximum.
- **Deload:** half the sets of every exercise (rounded up, at least 1) at effort 7 or lower, for 1 to
  8 weeks (an in-house choice in the range coaches use; B5 replaces it with the full deload rule).
  **Moderate** caps effort at 7. A **strength** or **size** phase rebuilds the week for that goal
  for 1 to 8 weeks.
- **Next session:** the next planned session (or today's, until it is done). Lighter: one set fewer
  on exercises with 3 or more sets, effort one point lower (not below 6), and the load one step
  below the logged-set target. Heavier: one load step above the logged-set target, only where B3's
  target is to add load or reps with high confidence. A step is the exercise's catalog load step.
- **Expiry:** 72 hours; 24 hours for a next-session adjustment. Undo: 7 days.
