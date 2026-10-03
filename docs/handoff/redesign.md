# Redesign Handoff: Graphite + Lime, App-Wide

**Status:** foundation integrated on `claude/redesign-base` (PR to `main`); six screen agents are
building on it in parallel.

**Plan:** `/Users/purnajear/.claude/plans/hey-uh-in-my-tender-allen.md` (owner-approved
2026-10-03). Owner-chosen direction: palette A, graphite + lime, from the prototype at
https://claude.ai/artifact/CQuLCcrwPUH6bwHfd8rSMh.

**Delivery change (owner, 2026-10-03):** the owner asked for the whole redesign inside about five
hours, built by parallel agents with one orchestrator. The ten sequential PRs became two
integrated PRs, and the three device checkpoints became two.

**Worktrees** (remove each after the final merge): `/Volumes/Crucial X9/dev/.tracend-worktrees/`
`redesign`, `rd-foundation`, `rd-widgets`, `rd-logging-data`, `rd-train-data`, `rd-brand`,
`rd-base`, and `ui-logging`, `ui-train`, `ui-today`, `ui-coach`, `ui-nutrition-progress`,
`ui-account`.

## Status

| Piece | Branch | State |
| ----- | ------ | ----- |
| Backend data (SQL) | `claude/redesign-backend` (#74) | 7/7 green; included in the foundation PR |
| Workout logging data, rest alert channel | `claude/redesign-logging-data` (#75) | 7/7 on a scratch CI branch; in foundation |
| Train data, load sheet model, muscle map | `claude/redesign-train-data` (#76) | 7/7 on a scratch CI branch; in foundation |
| Icon, launch screen, intro, loader | `claude/redesign-brand` (#77) | 7/7 green; in foundation |
| Tokens, Archivo, theme, tab bar, shared widgets | `claude/redesign-foundation` + `claude/redesign-widgets` | in foundation |
| **Foundation** (all of the above) | `claude/redesign-base` | PR to `main`. 🔒 device check 1 after deploy |
| Workout logging UI | `claude/redesign-ui-logging` | building |
| Train | `claude/redesign-ui-train` | building |
| Today | `claude/redesign-ui-today` | building |
| Coach | `claude/redesign-ui-coach` | building |
| Nutrition and Progress | `claude/redesign-ui-nutrition-progress` | building |
| Account, onboarding, auth | `claude/redesign-ui-account` | building |
| **Screens** (six branches integrated) | `claude/redesign-screens` | PR to `main` after the foundation. 🔒 device check 2: a real workout |

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
- Account deletion now also clears workout drafts, pending finishes, queued discards and the
  exercise history copy.
- Stacked PRs get no CI (CI runs on PRs into `main` and `feature/**`), so stacked work was checked
  on scratch `feature/**` branches and then integrated.

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
