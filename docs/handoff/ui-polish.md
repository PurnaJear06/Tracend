# UI Polish Handoff

**Goal:** make every screen read as a finished consumer app. The owner's complaint (2026-10-01):
Progress, and the lower half of Nutrition, felt like scrolling through logs. The cause was
structure, not missing data: a card per weigh-in, pose, photo set, and meal, wrapped in engineering
captions ("no AI estimate", "R² 0.43", "display-only, no detail destination yet", raw `ios_app`,
`lunch`, `confirmed`), with no single answer at the top.

## Principles (now in DESIGN_SYSTEM.md §3.3, §5, §9)

- One hero per screen answers the screen's question; only it uses the corner glow.
- Rows of one kind share a `TracendGroupedList`; at most three recent rows, then **See all**.
- Honesty labels survive once, in plain words: **Calculated from your logs · no AI**.
- Human formatting from `lib/shared/formatting.dart`: Today/Yesterday/Mon 28 Sep, kg/week,
  stored codes as words.
- Beta diagnostics stay (owner decision 2026-10-01) but sit on a smaller secondary line.
- Every layout is checked at 320pt with 2× text.

## Status

| Step | Scope | State |
| --- | --- | --- |
| P1 | Progress: period control on top, `WeightHeroCard` (goal-aware change, kg/week, steadiness words, chart), weekly review moved up, three recent weigh-ins + See all, strength tiles, one photo card + capture sheet | Merged #56 |
| P2 | Nutrition: one day timeline merging schedule and logged meals (foods, kcal, macros via `meal_items` embed), one **Log a meal** sheet with time-of-day meal type (fixes photo meals always saved as Lunch), coach insight demoted, confidence as words | Merged #57; build 235 installed |
| P2b | Today's meals in option A's row style (owner's pick after build 235): time, status glyph, **Lunch · 691 kcal**, a second line that opens with the status word, and a protein / carbs / fat split bar | PR #58 |
| P3 | Today: confidence pill and z-scores out of the first screenful; plain labels for PRECISION READOUTS, METABOLIC TARGET, T-COACH/N-COACH, g PRO; one "Today at a glance" list; tokens for two hard-coded colors | Queued |
| P4 | Train: verdict-first training load (ACWR, Ratio, Monotony behind ⓘ), "Effort 8/10" for RPE, one glow card, rewrite "No fixture workout was substituted" | Queued |
| P5 | Coach: one "How I got this" drawer for provider, evidence ids, and missing keys (friendly labels); beta diagnostic kept inside it; fix the ISO date in the context card | Queued |
| P6 | Account and onboarding: grouped lists, Appearance out of Connections, cost to 2 decimals, remove "The mock provider receives only this confirmed snapshot.", notice versions as dates, wire or remove the no-op Edit button | Queued |

## P1 notes

- Goal colour reads `user_goals.goal_type` through the optional `ProgressGoalRepository` (the same
  query Account uses). No migration.
- `ProgressScreen(now:)` injects the clock so period windows and relative dates are testable.
- `WeightTrendIndicator` and `MetricSparkline` were folded into the hero and deleted.
- `EvidenceTrendChart` now wraps its legend and footer, and shows dates as "1 Aug"; at 2× text the
  old rows overflowed by up to 264px.
- Only the first two sections use the entrance stagger; sections built later by scrolling appear
  at once.

## P2 notes

- `loadMeals` embeds `meal_items` and reads `confirmed_at` and `nutrition_schedule_item_id`. The
  select grant and RLS already exist (`20260702110000_phase_6_nutrition_foundation.sql`); a meal
  logged from a slot is matched through `nutrition_schedule_item_id`, the same column
  `get_my_nutrition_schedule` uses for `logged`.
- Photo meals were always saved as `lunch`; the chosen type now reaches `create_meal_photo_draft`.
- Delete lives in a **⋯** menu; its confirmation opens from `onSelected`, after the menu closes.
- The fallback photo error is plain words plus a `Beta diagnostic · step: code` line.

## P2b notes (#58)

- After build 235 the owner said Nutrition felt ordinary. Two directions were sketched: A, a "fuel
  line" chart of the day, and B, protein first with a Log again row. The owner chose A's **row
  style only**, kept the header, and declined the chart.
- `MacroSplitBar` sizes segments by energy (4, 4, and 9 kcal per gram). It draws only the macros a
  meal has, with gaps between visible segments only, so a zero-fat meal has no trailing gap.
- Not shown: meal photos, because SECURITY_PRIVACY limits them to proposing foods. Planned slots
  carry no calories, so nothing projects them.
- Owner liked Progress as built; keep its patterns for P3–P6.

