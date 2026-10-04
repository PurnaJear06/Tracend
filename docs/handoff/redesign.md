# Redesign Handoff: Graphite + Lime, App-Wide

**Status:** the foundation merged and deployed as #78 (`12f5bbb`) and is the owner's device check
1. The six screens are integrated on `claude/redesign-screens` (PR to `main`).

**Plan:** `/Users/purnajear/.claude/plans/hey-uh-in-my-tender-allen.md` (owner-approved
2026-10-03). Owner-chosen direction: palette A, graphite + lime, from the prototype at
https://claude.ai/artifact/CQuLCcrwPUH6bwHfd8rSMh.

**Delivery change (owner, 2026-10-03):** the owner asked for the whole redesign inside about five
hours, built by parallel agents with one orchestrator. The ten sequential PRs became two
integrated PRs, and the three device checkpoints became two.

**Worktrees** (remove each after the final merge): `/Volumes/Crucial X9/dev/.tracend-worktrees/`
`redesign`, `rd-foundation`, `rd-widgets`, `rd-logging-data`, `rd-train-data`, `rd-brand`,
`rd-base`, `rd-screens`, `rd-slug`, and `ui-logging`, `ui-train`, `ui-today`, `ui-coach`, `ui-nutrition-progress`,
`ui-account`.

## Status

| Piece | Branch | State |
| ----- | ------ | ----- |
| Backend data (SQL) | `claude/redesign-backend` (#74) | 7/7 green; included in the foundation PR |
| Workout logging data, rest alert channel | `claude/redesign-logging-data` (#75) | 7/7 on a scratch CI branch; in foundation |
| Train data, load sheet model, muscle map | `claude/redesign-train-data` (#76) | 7/7 on a scratch CI branch; in foundation |
| Icon, launch screen, intro, loader | `claude/redesign-brand` (#77) | 7/7 green; in foundation |
| Tokens, Archivo, theme, tab bar, shared widgets | `claude/redesign-foundation` + `claude/redesign-widgets` | in foundation |
| **Foundation** (all of the above) | `claude/redesign-base` (#78) | Merged and deployed (`12f5bbb`); migration applied. 🔒 device check 1 |
| Workout logging UI | `claude/redesign-ui-logging` | integrated into screens |
| Train | `claude/redesign-ui-train` | integrated into screens |
| Today | `claude/redesign-ui-today` | integrated into screens |
| Coach | `claude/redesign-ui-coach` | integrated into screens |
| Nutrition and Progress | `claude/redesign-ui-nutrition-progress` | integrated into screens |
| Account, onboarding, auth | `claude/redesign-ui-account` | integrated into screens |
| **Screens** (six branches integrated) | `claude/redesign-screens` (#79) | Owner merges, then installs from `main` for device check 2: a real workout |
| Catalog links for older plans (SQL) | `claude/plan-exercise-links` (#80) | Merged 2026-10-03 |

## Phase 0 picks (owner, 2026-10-03)

1. Logging style: **focus mode**.
2. Muscle map: **on**. The owner liked the idea but called round 3 "not up to the mark"; the map
   was redrawn as an athletic figure from real muscle shapes, with two lime tones from set counts
   (main at 60% or more of the top group's sets), a 3D turn with body thickness, a drag to turn,
   and a front-and-back pair in focus mode and the muscles sheet. It was reviewed from scratch
   renders and goes straight into the app rather than another prototype round.
3. New best: **big moment**.
4. Week: **day boxes**.
5. Icon: **white and lime** (chalk T, lime arc and dot, on graphite). The rebuilt load sheet and the
   launch motion were not objected to and ship as prototyped.

The muscle map needs planned exercises linked to the catalog. Older plans have no slug, so they
lit nothing. Migration `20261003120000_plan_exercise_catalog_links.sql` (owner decision 2026-10-03:
"implement it as the plan said") links each planned exercise whose name is exactly a catalog name
(exercise history key: lowercased, trimmed, spaces collapsed; a single match only) and gives its
prescribed performances the same slug. Everything else stays unlinked and shows no muscles;
nothing is guessed.

## Decisions made during the build

- Brand: the Runner target now compiles `Assets.xcassets` so the icon can carry the iOS 18 dark and
  tinted variants (ADR 0012). The launch screen stays storyboard-free: `UILaunchScreen` names a
  graphite colour set and the 132 pt mark.
- Rest alert toggle: stored on the device only (no server column, no migration).
- New best: "earlier set" means a lower set number in the same exercise, so un-ticking recomputes
  deterministically.
- Load sheet: keeps the week rail's thin-history rule (fewer than 4 sessions in 28 days reads as a
  new user even when a ratio exists).
- Muscle map: a tap opens the muscles sheet; a drag or the Front and Back control turns the body.
- Theme: the bottom sheet theme draws no drag handle; `showTracendSheet` draws its own.
- Cards: `TracendCard` and `PremiumGradientCard` are flat surfaces with no border, shadow or glow.
- Discard queue: only the final refusals (22023 finished, P0002 not found) settle a saved discard;
  any other server error keeps it waiting, like a lost connection (GPT review).
- Readiness line Good band reads "Recovery is good.": state only, never advice (GPT review).
- Integration fixes: large titles shrink to one line instead of breaking a word; a section label's
  value or action moves under it from 1.3× text; at large text a confirm is a full-width action
  sheet (the fixed 270pt alert broke words); the loader and muscle map follow the motion scope;
  one shared AI provider name map (`lib/shared/ai_provider_names.dart`); pushed screens get a
  centred inline bar; the shell wires Today to the Train tab and Train to Health and Account.
- The legacy `complete()` client path is removed; the app finishes only with the athlete's effort.
  The server keeps `complete_workout` for older installed builds.
- Train keeps the hub loaded this session when offline; persisting the hub across launches is not
  built.
- Account deletion now also clears workout drafts, pending finishes, queued discards and the
  exercise history copy.
- Stacked PRs get no CI (CI runs on PRs into `main` and `feature/**`), so stacked work was checked
  on scratch `feature/**` branches and then integrated.
- Device check of #79 (build 317), owner feedback: Today read as a health report, not a training
  app. Rebuilt it with a recovery dial and vitals, a check-in call to action, a bold workout card
  with a lime action, and food rings; food and the coach note now come before the evidence.
  Nutrition's "From confirmed meals" tiles got more room. The rest-alert toggle no longer needs
  the server: a rest-only change saves on the device, and a failed reminder save rolls back only
  the daily and weekly choices (GPT review P2).
- Muscle map missing on the owner's device: the owner's plan predates the catalog, so no planned
  exercise had a slug. Per the plan, a separate SQL PR links exact catalog names (#80); a workout
  with no linked exercise now says "Muscle map appears with your next plan." instead of nothing.
- Second device round (owner): the launch intro has no skip (it is about a second) and gained a
  scale-in with a soft overshoot, a lime bloom as the dot lands, a dot trail, a per-letter
  wordmark and a zoom-through exit into the app. Today's food rings sweep in with a count-up, a
  gradient stroke with a glow and a head dot, and a second lap past the target. Food stays on
  Today, as it was before the redesign.
- Owner, after build 329: the Today food rings repeated Nutrition and read as filler. Of three
  mockups (next plate, fuel rail, food folded into the hero) the owner chose the fuel rail:
  `FuelRailCard` leads with protein to go, splits it evenly over the meal-plan slots still ahead,
  and draws the day as a line with logged, planned and missed meals and a "now" needle. Today
  loads the meal plan and today's confirmed meals for it (`FuelDay.from`, plain arithmetic); a
  slot stays ahead until an hour past its time, computed on the phone.
- Owner, 2026-10-04: Today's hero "is not proper". From three prototypes the owner chose a
  recovery tick ring whose lit ticks are split by driver (lime fine, amber pulling down), a
  check-in that gates the day (the tab bar gives way to "Check in to start your day" until it is
  saved, with "Not today" always letting the athlete through), bento tiles (Sleep, Load, Fuel)
  that open the old cards in place, "Today's session" as a strip of set blocks that fill as Train
  logs them, with the coach's note as advice, and "Your week" as recovery tick stacks with session
  marks. The vitals list, check-in bar, workout card, coach note card, 7-day trend and the drivers
  and sleep sections fold into these; `SessionPlanCard`, `CheckInPromptBar` and
  `CoachPerspectiveCard` are gone. Brief 1.7 (`20261004130000`) carries the week, plan week, today's
  logged sets and yesterday's recovery; pgTAP `today_week_brief_test.sql`. The coach's
  adjustments stay plain sentences, so Today shows them as text and never alters the prescribed
  blocks; applying them to sets belongs to the plan-change loop (review G1).
- Owner, 2026-10-04 (build from #85): the ring read about 10 and changed from morning to evening.
  The owner rarely wears the watch to sleep. Cause: recovery averaged every HRV reading of the
  day, including the ones taken awake, recomputed on every Today load against a baseline mixing
  nights and days; resting HR was today's, which Apple revises through the day. Breathing showed
  no data because the watch records it only asleep (honest). Fix (`20261004160000`, scoring 2.3,
  brief 1.8): recovery modes (ALGORITHMS.md §1). A night with the watch scores that night's HRV
  against nights. Without one, a morning estimate scores the HRV taken 04:00–12:00 against
  mornings, plus the check-in, settling at noon (at most medium confidence). Resting HR is
  yesterday's final value. The app sends `hrv_sleep_ms` and `hrv_morning_ms` and re-reads 30 days
  once (versioned backfill flag) so both baselines start full. The Train readiness sheet uses the
  same readings. pgTAP `recovery_modes_test.sql`; the parity fixtures gained
  `morning_estimate_day` and `night_scores_from_night`. Migration first, then install.
  Review fixes in the same PR: the resting-HR baseline folds through yesterday (today's value moved
  it after noon), nap breathing never makes a night (app drops it; server needs 3 h of sleep), and a
  recomputed `daily_computed_metrics` row restamps `schema_version`. Sentry FLUTTER-H (build 336,
  a statement timeout on `get_my_daily_brief` from Progress at launch): Today, Train and Progress
  are built together and each loaded the brief, three recomputes of the same rows at once;
  `SharedDailyBriefRepository` now shares one in-flight request per day (a finished load is never
  reused). Locally one brief takes 40-70 ms with 90 days of data.
- Meal slot status on the athlete's clock (SQL only, `20261004100000`): `get_my_nutrition_schedule`
  judged `due`, `upcoming` and `skipped` with the database clock (UTC), so for the owner in IST a
  13:30 lunch was due at 19:00 local, and from local midnight to 05:30 every slot of today read
  `upcoming`. It now uses the request's time in `user_accounts.timezone` (UTC when unset or
  unknown), and a window near midnight no longer wraps. This fixes Nutrition's due badge and
  Today's `next_meal`. The fuel rail is unaffected: it trusts only `logged` and computes ahead and
  missed on the phone. No meal notification reads the status (reminders are the check-in and
  weekly review). pgTAP `meal_status_user_timezone_test.sql` (IST, a zone on another date than
  UTC, an unknown zone). No reinstall.
- Owner device check of build 325: on a pull day only Face Pull matched a catalog name, so the
  card lit shoulders alone for a back-and-biceps session. The Train card now shows the map only
  when linked exercises carry at least three quarters of the planned sets
  (`muscleMapCoversWorkout`); otherwise it says "Muscle map appears with your next plan." A
  single exercise's map in focus logging is unchanged.
- Owner: "it should understand the exercises". The catalog stays the onboarding allowlist, so a
  reviewed list `exercise_muscle_references` (migration `20261004090000`) gives the 34 unlinked
  names in the owner's active plan their primary muscles by hand; the hub reads catalog muscles
  first, then the list, by the history key, and never adds a slug. New free-text names need a
  reviewed row in a migration. pgTAP `exercise_muscle_references_test.sql`.
- GPT review of b39a05a (3 × P2, fixed): a permission granted by the rest toggle now saves the
  status with the reminder choices already on the server (a reinstall reports both off), and a
  later reminder save waits for it; a load the athlete cleared stays cleared after Save and leave
  or a relaunch (a phone-only `cleared_loads` list in the local draft, never sent to the server);
  the finish sheet no longer says unlogged sets are saved as skipped (they stay unknown, PRD).

## PR 1: backend data

Migration `20261003100000_train_redesign_data.sql` (additive):

- `workout_sessions.completion_source` (`manual`, `healthkit`) and `session_effort_source`
  (`athlete`, `legacy_default`, `healthkit_default`), backfilled from the `workout.completed` and
  `workout.auto_completed` audit codes. Never inferred from notes.
- `complete_workout_v2(session_id, client_revision, duration_seconds, session_effort, notes,
  session_energy default null)`: the athlete's whole-number 1–10 rating, energy optional. The old
  `complete_workout` keeps working for installed builds and records its fixed 8 as
  `legacy_default` and refuses any other effort (22023, GPT review 2026-10-03). Both share `private.complete_workout_session`; a discarded session cannot be
  finished (55000).
- `abandon_workout(p_session_id)`: open → `abandoned` with a `workout.abandoned` audit event; a
  repeat returns `replayed: true`; a completed session is refused (22023); another athlete's is
  not found (P0002). Rows stay; every read counts completed sessions only, and
  `get_my_workout_session` no longer returns a discarded session.
- `exercise_performances.exercise_slug`, kept by a trigger: the planned exercise's slug for a
  prescribed performance, none for substitutions and extras.
- `get_my_exercise_history(p_keys, p_sessions default 8)` 1.0: 1–20 keys of 1–120 characters
  (repeats answered once), sessions clamped to 1–12, violations 22023. Per key: `kind`, `last_session`,
  `best_set` and `top_sets` (best set per completed session, newest first). `kind` says how sets
  rank: `load` (heaviest, then most reps, then earliest), `reps` (bodyweight: most reps) or
  `assistance` (catalog `assisted-` slugs, or names starting "assisted" without a slug: the logged
  load is machine help, so the least assistance wins and 0 is unassisted; sets with no logged
  assistance are not ranked). A catalog key takes older unslugged rows by name only when they were
  prescribed; substitutions and extras never join a catalog exercise by name (GPT review). Review fix, 2026-10-03: ranking every load descending would have
  called the most-assisted pull-up the best.
- `get_my_training_hub` 1.6 adds `local_today`; `active_plan.effective_date` (falls back to the
  local approval day), `approved_on` and `progression_rule`; each exercise's `exercise_slug` and
  `primary_muscles`; `completion_source` and `effort_source` on recent sessions; and `daily_load`
  (28 local days, ALGORITHMS §4 "Day Level").

Deviation from the plan, on purpose: the day-level reference set uses only days whose effort the
athlete reported, so the default efforts of the first 28 days never shape the personal
percentiles. The plan's "28 days before, zero days excluded" rule is otherwise as written.

Not in PR 1: the name → slug link for older planned exercises. It shipped separately in
`20261003120000_plan_exercise_catalog_links.sql`; pgTAP `plan_exercise_catalog_links_test.sql`.

Verification: pgTAP `train_redesign_data_test.sql` (65 checks) through CI, because the local
Colima VM hung on start again; Dart contract fixtures `training_hub_v1_6.json` and
`exercise_history_v1_0.json`; `db_contract_test.ts` updated for 1.6 and the history RPC. No app
change, so no reinstall. After the deploy, confirm the live hub reports `schema_version` 1.6 with a
read-only dashboard query.

## Deferred

- Move a workout to another day (schedule-override table, RPC, audit).
- Live Activity lock-screen timer (widget extension and signing).
- Add or remove a set mid-workout (sync RPC change).
- A true 3D body model (licensed asset and renderer), only if the 2.5D map is loved.

## Public-release blocker

Terms and Privacy checkboxes in onboarding are not linked to hosted notices
(SECURITY_PRIVACY.md open release item). Acceptable for the owner-only beta; must be resolved
before any public release. PR 8 records it in the SECURITY_PRIVACY release checklist.
