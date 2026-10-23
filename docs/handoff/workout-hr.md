# Session Timing and Heart Rate Handoff

**As of:** 2026-10-23

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

Per-set start and end times, actual rest and reps-left (Contract 2), workout events (Contract 3), then per-set Apple Watch heart-rate summaries (Contract 4) and a personal heart-rate profile. Heart rate never sets the load.

## Chunks

C1 (Phase 1); C2 (Phase 2); C3 (Phase 3); C4 (Phase 4)

## State

**C1 (set timing, reps left, workout events): live** (#104, 2026-10-15). The migration is
deployed; the phone uses it from the next install built from `main`.

- Migration `20261015140031_set_timing.sql` (code 31): five nullable `exercise_sets` columns with
  checks (Contract 2); `sync_workout_draft` redefined from `20260711190000_workout_truth_repair.sql`
  (the latest) with the same signature and behaviour plus the five optional set keys: a missing key
  keeps the stored value, an explicit null clears it, malformed values and times more than 10
  minutes in the future or more than 10 minutes before the session's recorded start raise 22023,
  and so does an end before the start. Helpers `private.workout_set_time` and
  `private.workout_set_whole_number`. `get_my_workout_session` gains `schema_version` 1.1 (it had
  none) and the five set fields; `get_my_exercise_history` 1.1 adds them to the last session's
  sets. `complete_workout_v2` untouched. Privacy export already selects every column, so it needs
  no change. pgTAP `set_timing_test.sql`; `train_redesign_data_test.sql` and the Deno DB contract
  test expect history 1.1.
- The "before the session's start" rule allows the same 10 minutes as the future rule (Contract 2
  says "more than 10 minutes before the session's recorded start"). The app never sends a time
  from before the server's recorded start (read back with `get_my_workout_session` after
  `start_workout`; the phone clock only when that read fails), so a workout started offline keeps
  those times on the phone.
- Clock far off (review B1): when a sync is refused with 22023, the app sends the same revision
  again without the five keys, stores `timing_refused` in the local draft and syncs the rest of the
  workout without them (breadcrumb "Set times refused; syncing without them", no values). A finish
  whose final sync is refused (any code) does not call `complete_workout_v2`: the draft stays,
  the state reads Needs attention and Send finish retries.
- App (`lib/features/train/`): `set_timing.dart` records starts, ends and rest from wall-clock
  moments (rest end = Skip, or the timer's stored end even when the app notices late; a set ticked
  during its rest gets no start; a gap over an hour is no rest). `workout_draft.dart` carries the
  fields and sends them. `workout_events.dart` holds Contract 3 (`WorkoutEvent`s,
  `WorkoutCommand`s and `WorkoutEventHub`); `ActiveWorkoutScreen(events:)` publishes the events and
  obeys `CompleteCurrentSet`, `SkipRest`, `AddRest` (D1 wires the Live Activity to it). Skip and
  every rest change publish `RestAdjusted` (Skip with `endsAt` = now); `ExerciseAdvanced` fires when
  the exercise on screen changes; `WorkoutEnded` on finish (completed) and on discard or leave.
  `SetStarted.at` is the set's real start, which can be earlier than its publication (a start is
  known only once the set is edited or ticked); it is never withdrawn, so listeners that need a
  set's window read the stored times. Commands are ignored while finishing and after close. Undo
  clears the set's times and re-measures any rest counted from it.
- UI decision (reps left vs RPE): the 1–10 set-effort picker is replaced by `RirPicker` (0–4,
  5+). The old picker already asked "How many reps were left?" and labelled each RPE with reps
  left, so the redesign's intent is kept and the question is answered directly. The app still writes
  `rpe = 10 − rir` (the same mapping), so the Coach's set RPE stays consistent; sets logged before
  show their RPE as reps left (`WorkoutSetDraft.shownRir`, display only, so Fill skips them).
  `rpe_picker.dart` became `effort_scale.dart` (session effort only).
- Review fix: a set sends only the Contract 2 keys it knows (`WorkoutSetDraft._known`, per key): a
  set restored from a pre-C1 draft sends none until a tick, un-tick, reps-left answer or re-measured
  rest sets one, so it never clears another device's values; un-tick still sends nulls.
- Tests: `test/set_timing_test.dart` (rest maths, backgrounding, relaunch),
  `test/rir_picker_test.dart`, timing/event/command widget tests in
  `test/phase_3_workout_flow_test.dart`, contract fixtures `workout_session_v1_1.json` and
  `exercise_history_v1_1.json`.

Owner device check after install: log a few sets with rests (one Skip, one left to run out with the
phone locked), pick reps left during a rest, finish; then ask for the set rows (or check
`get_my_workout_session`) to confirm `started_at`, `completed_at`, `rest_before_seconds`, `rir`
and `timing_source = app`.

**C2 (per-set heart rate): in review** (stacked on D1's branch, PR #121, so its diff shows D1's
commits until that merges). Contract 4, summaries only; raw samples never leave the phone.

- Migration `20261016003032_set_heart_rate.sql` (code 32, re-stamp before handoff): table
  `exercise_set_heart_rate` (RLS on and forced, owner select only, CHECKs for ranges, peak at or
  above start and end, coverage 0–1), `persist_set_heart_rate_v1(session_id, summaries)` (security
  definer, empty search path, authenticated only, own workouts that are not discarded, upsert per
  set, 22023 on invalid values, returns `schema_version` 1.0 and `saved`) and
  `get_my_set_heart_rate_v1(session_id)` (security invoker, 1.0). Sets are named by
  `exercise_order` and `set_number`, not by set id, because `get_my_workout_session` does not
  return set ids and C1's RPC was not C2's to change. `privacy-export` lists the table; account
  deletion removes it through the `user_accounts` cascade (pgTAP proves it). pgTAP
  `set_heart_rate_test.sql`.
- Native: `ios/Runner/Native/HeartRateReader.swift` (channel `tracend/heart_rate`, registered in
  `SceneDelegate` next to `WorkoutActivityBridge`): `requestAccess` (HealthKit read access to heart
  rate only, no share types) and `readSamples` (an `HKAnchoredObjectQuery` over a window of at most
  4 hours, samples as `{at_millis, bpm}`). Heart rate was not among the types the health plugin
  requests, so the reader asks for it itself, after the athlete finishes a workout; resting heart
  rate and the sync types are unchanged. `NSHealthShareUsageDescription` now mentions workout
  heart-rate data.
- Dart (`lib/features/workout_hr/`): `set_heart_rate_summary.dart` (pure maths: nearest reading
  within 10 s for start, end and the drops; peak over the set; coverage in 10-second slots over the
  set plus 60 s; `watch_workout` when the median gap is 10 s or less over at least three readings;
  no summary when the window has no reading, so nothing is invented), `heart_rate_reader.dart`,
  `set_heart_rate_repository.dart`, `set_heart_rate_recorder.dart` and `set_heart_rate_line.dart`.
  The recorder listens to `WorkoutEventHub.events` only (never writes sets). On
  `WorkoutEnded(completed: true)` it asks for access, reads the finished workout back
  (`get_my_workout_session`, so the windows are the stored `started_at`/`completed_at`), and puts
  it on a waiting list in `SharedPreferencesAsync` (session id and set times only). The read runs
  60 s after the last set (the Watch syncs to Apple Health after the workout), up to three reads
  five minutes apart while the average coverage is below 0.8; a later save replaces an earlier one
  only when it ranks higher (sets covered, then average coverage, then readings), and the work ends
  only when the saved best reaches 0.8. A server refusal ends the work; no connection keeps it waiting
  (two days) without using a read. The list is also worked on when the app returns to the
  foreground and when a workout screen opens, so a read that came due while the app slept runs
  the next time it is open (a cold start that never opens a workout waits for the next workout).
- Train touchpoints (D1 reviews): one listener call in `ActiveWorkoutScreen.initState` (only for
  the Supabase repository) and, for the heart-rate line, `WorkoutSummaryBody` gains an optional
  `heartRate` loader and `LoggedSession` a `sessionId`: each exercise row in the finished-workout
  summary gets one extra line, "Heart rate peaks 148 · 152 bpm · 90% tracked". D9: it informs
  only.
  "Tracked" divides the readings' coverage by every completed set of the exercise (the detail's
  own set count), so sets with no readings count as 0: 1 tracked of 4 sets reads 25%, as the
  recorder's retry check (which divides by all timed sets) already did.
- Tests: `test/workout_hr/*`, `test/contract/set_heart_rate_contract_test.dart` with fixtures
  `set_heart_rate_v1_0.json` and `persist_set_heart_rate_v1_0.json`.

Owner device check after install (a build from `main` once the migration is deployed): start a
Watch workout (Strength) and a Tracend workout together, log three sets with the phone, finish both.
Allow Heart Rate in the Apple Health sheet if it appears. Wait two minutes, then open the
workout's summary: each exercise should show the heart-rate line, and "tracked" should be at least
80%. If it is lower, keep the app open for a few minutes (the Watch may not have synced yet) and
open the summary again.

**C3 (heart-rate profile, zones, recovery, sleeping heart rate in shadow mode): in review**
(based on the kickoff PR #130). Heart rate informs; it never sets a load (D9).

- Migration `20261017150233_heart_rate_profile.sql` (code 33, re-stamp before handoff): table
  `sleeping_heart_rate_nights` (RLS on and forced, owner select only; one derived row per night:
  median, lowest 10-minute mean with 2+ readings, readings, minutes asleep, coverage), `persist_sleeping_heart_rate_v1`
  (security definer, authenticated, 1 to 14 nights; an invalid night is skipped and counted in `skipped`, a null or malformed list raises 22023; `schema_version` 1.0),
  `get_my_heart_rate_inputs_v1(local_date)` (own data, 1.0) and `get_heart_rate_inputs_v1(user, date)`
  (service role only, the same object). The inputs hold the birth year, 14 days of resting heart rate,
  the usable per-set summaries of two 28-day windows (filtered first, 200 per window) and the 10 highest peaks of 365 days; no sleeping heart rate. The profile
  is not stored: it is computed on demand. `privacy-export` lists the new table; account deletion
  removes it through the `user_accounts` cascade (pgTAP proves it). pgTAP `heart_rate_profile_test.sql`.
- Maths (twins: `lib/features/workout_hr/heart_rate_profile.dart`,
  `supabase/functions/_shared/training/heart_rate/profile.ts`; both read `profile_cases.json`, so they
  cannot drift): resting = median of 14 days (from 3 days); maximum = Tanaka 2001 `208 - 0.7 x age`
  (ages 16 to 90) until a trusted workout peak is higher (Watch workout, 8+ readings, 60%+ coverage,
  120 bpm up to formula + 20, 210 with no age); zones = Karvonen at 50/60/70/80/90/100% of reserve,
  five bands; recovery = median 60-second drop over 28 days against the 28 before (6+ sets each,
  3 bpm for improving or slower). Full rules and sources in ALGORITHMS.md "Heart-Rate Profile".
- Sleeping heart rate (D10, shadow): `sleeping_heart_rate.dart` finds nights in the sleep samples the
  Health sync already read (sessions joined across gaps up to 1 hour, dated by the day they end, 3+
  hours asleep, awake time removed) and summarises the heart-rate readings taken asleep (20+ readings,
  50%+ of 10-minute slots covered, else no row). `SleepingHeartRateRecorder` runs after a successful
  `SupabaseHealthRepository.sync()` without delaying it, for the last 7 nights, reading each in windows
  of at most 3.5 hours (the Swift reader's cap is 4), and stops re-reading a saved night once it is two
  days old. Heart-rate access is requested in `connectAndSync` only (the user's tap), never by a
  background sync. `HeartRateReader.swift` needed no change.
- **Shadow proof:** pgTAP `sleeping_heart_rate_shadow_test.sql` computes `compute_daily_metrics` for a
  morning estimate, stores eight nights of sleeping heart rate (31 to 38 bpm, far from the resting
  values), computes again and asserts `scores`, `today_raw` and the baselines are identical; it also
  asserts no function in `public` or `private` other than `persist_sleeping_heart_rate_v1` mentions
  the table, and no view or rule depends on it. Moving sleeping heart rate into a score must update that
  test and SECURITY_PRIVACY §4. TypeScript and Dart profile inputs have no sleeping field (tests).
- App: `HeartRateZonesView` (`heart_rate_zones_view.dart`) at the end of the Apple Health sheet's
  `HealthStatusCard` (Account), shown when Apple Health is connected and the card is not compact: resting
  and maximum line, five zones, one recovery line, "For information only". Missing data is said plainly
  and no zone is drawn. `SupabaseHealthRepository` implements `HeartRateProfileSource`.
- Coach: `_shared/coach_context/contributors/heart_rate.ts` (`createHeartRateContributor(load)`, id
  `heart_rate_profile`, volatile, 900 characters) with `_shared/training/heart_rate/inputs.ts`
  (`loadHeartRateInputs(client, userId, localDate)` calls the service-role RPC). **Not registered in
  `registry.ts`**; the lead registers it with E3 in round 3, passing a loader built on the service
  client. The text states what is known and what is missing and never mentions sleep.
- Tests: `profile_test.ts`, `inputs_test.ts`, `heart_rate_test.ts` (Deno); `test/workout_hr/
  heart_rate_profile_test.dart`, `sleeping_heart_rate_test.dart`, `heart_rate_zones_view_test.dart`,
  `health_card_zones_test.dart`; `test/contract/heart_rate_profile_contract_test.dart` with fixtures
  `heart_rate_inputs_v1_0.json` and `persist_sleeping_heart_rate_v1_0.json`.
- Review fixes (Claude Opus review of #133): (1) `private.heart_rate_inputs` filters the recovery sets to
  the usable ones (60 s drop, end heart rate, 60%+ coverage) and caps each 28-day window at 200 on its own,
  instead of one newest-first limit of 400 over everything (pgTAP: a heavy-volume case). (2)
  `SupabaseHealthRepository.connectAndSync` wraps the heart-rate access request in try/catch (logged as
  non-critical) so it can never stop the sync; the reader is injectable (test: a throwing reader, the sync
  still runs). (3) The phone drops a night outside the server bounds (`withinServerBounds`) before sending, and
  `persist_sleeping_heart_rate_v1` skips an invalid night per item and returns `skipped` (additive, still
  `schema_version` 1.0; fixture updated). (4) A null `nights` raises 22023. (5) DATA_MODEL states the `local_date`
  rule (at most one day after the server's date). The migration is not on main, so it was edited in place.
- Review fixes (GPT 5.6 Sol review of #133): (1) `SleepingHeartRateRecorder.record` is bound to the
  athlete signed in when it starts: it checks the signed-in id before the RPC and before marking nights
  final, and sends nothing if another account signed in during the reads (test: switch account).
  (2) `private.heart_rate_inputs` applies the peak trust rules before `limit 10` (source, 8+ readings,
  60%+ coverage, 120 bpm up to the age ceiling + 1, 210 with no age), so ten untrusted higher peaks
  cannot hide a valid lower one (pgTAP case added; migration 33 is not on main, so it was edited in
  place). (3) The nightly lowest uses only 10-minute slots with at least 2 readings; a night with no
  such slot is not sent (`lowest_bpm` is NOT NULL). Sleeping heart rate has no TypeScript copy, so
  `profile_cases.json` is unaffected. (4) `NSHealthShareUsageDescription` in `Info.plist` now names
  overnight (sleeping) heart-rate data (granted to C3 for this one change); SECURITY_PRIVACY §4 mirrors it.

Owner device check after install (a build from `main` once the migration is deployed): open Account,
Apple Health, tap Refresh (allow Heart Rate in the Apple Health sheet if it shows). With 3 or more
days of resting heart rate the Heart-rate zones section lists five zones and "Max ... estimated from your
age" (it needs a birth year in the profile). After a few tracked workouts a recovery line appears. The
next morning, ask for the `sleeping_heart_rate_nights` rows (SQL editor) to see last night; no score
changes. A night with the Watch off has no row.

**C4 (Watch-workout suggestion, load signals for the engine): in review** (branch
`claude/watch-workout-prompt`). Heart rate informs; it never sets a load (D9).

- Migration `20261023120034_watch_workout_load_signals.sql` (code 34, re-stamp before handoff; adds
  no table, so nothing to export or delete): `get_my_watch_workout_status_v1(local_date)`
  (authenticated, own data, date within 2 days of today, `schema_version` 1.0) returns the last three
  finished workouts of the last 28 days that finished at least one set, each with `local_date`,
  `completed_sets` and `watch_sets` (finished sets with `watch_workout` heart rate and at least 50%
  coverage). `get_workout_load_inputs_v1(target_user, local_date)` (service role only, 1.0) returns the
  newest 12 finished workouts of the last 28 days with `completed_sets` and, for each finished set that
  has a heart-rate summary (120 per workout at most), `exercise_order`, `set_number`,
  `rest_before_seconds` and the Contract 4 values. It returns no load, repetitions, reps in reserve or
  effort, so a signal built on it cannot depend on them. Discarded, open and Apple Health completed
  (no set) workouts are left out; a set finished and later undone is left out even though its
  readings stay stored. pgTAP `watch_workout_load_signals_test.sql` (53 assertions).
- Suggestion (app, `lib/features/workout_hr/watch_workout_prompt.dart`): a card above the first
  exercise of a workout with no set done yet: "Track your heart rate. Start a Strength workout on your
  Apple Watch, then log your sets here..." with **Not now** and **I don't use a Watch**. It shows when
  none of the last three finished workouts had Watch heart rate (or there is no finished workout yet),
  and goes away by itself when the first set is ticked. Not now stays quiet for 7 days; the other button
  for good. Both answers live in `SharedPreferencesAsync` on the phone (`tracend.watch_prompt.muted`,
  `tracend.watch_prompt.snoozed_until`), are not tied to the account, and are checked before the server
  is asked. A server that cannot be read suggests nothing. A workout restored with a set done, or a
  finished one, is never asked. The one touchpoint in `ActiveWorkoutScreen` is the optional
  `watchPrompt` source, the banner and two small methods (D1 reviews).
- Load signals (engine, `supabase/functions/_shared/training/heart_rate/load_signals.ts`, loader in
  `load_signals_inputs.ts`): pure maths over the inputs above and the C3 profile, rules and thresholds
  in ALGORITHMS.md "Heart-Rate Load Signals". Output `engine`: `confidence` (`none` or `lower`, never
  higher), `rest` (`none` or `allow_longer`), `question` (`recovery_check` or null) and the `reasons`.
  `loadWorkoutLoadSignals(client, userId, localDate)` reads both service-role functions and returns null
  when either read fails, so the plan and its progression stand exactly as without heart rate.
- **Coach reads the signals (owner approved, fixed wording).** The registered `training_plan`
  contributor (`contributors/training_plan.ts`) loads them with `loadSignalsFromService` (over
  `coachServiceRpc`; a failed or empty read, or a throw, is no signals and the text is unchanged). With
  `engine.confidence` = `lower`, a target whose action is `add_load` or `add_reps` gets one fixed sentence
  after its "Next target" text ("Heart rate shows slower recovery than usual: treat this step as less
  certain (the target is unchanged)."); a hold, a cut or an exercise with no target gets nothing. With
  `engine.rest` = `allow_longer`, one fixed sentence ("Heart rate suggests resting a little longer
  between sets...") sits once before the session's exercise lines, not on each. Both sentences hold no
  figure and are not marked with `record`, so they ground nothing a reply could quote. The target, load,
  reps and sets are the same text with or without the signals (test). `createTrainingPlanContributor`
  takes the signals source as an optional second argument, so every other caller renders as before. The
  Coach answer schema is untouched (0 optional, 0 unions), and a test proves the largest plan still
  fits the 12,000-character budget with every sentence the signals can add. Train card and B4 are not
  done (below).
- Tests: `load_signals_test.ts` (20 tests: each rule with its edge, the D9 output check, parse and
  loader), `test/workout_hr/watch_workout_prompt_test.dart`, six widget tests in
  `test/phase_3_workout_flow_test.dart`, fixture `watch_workout_status_v1_0.json`.

Owner device check (iPhone + Apple Watch, a build from `main` once the migration is deployed): (1)
open a workout with no Watch workout in your last three sessions: the "Track your heart rate" card shows
above the first exercise; tick a set and it disappears. (2) Reopen the next workout: Not now keeps it
away for a week; I don't use a Watch removes it for good (reinstalling the app brings it back). (3) Start
a Strength workout on the Watch, log three sets, finish both and wait for the summary's heart-rate line;
open the next workout: the card no longer shows. (4) With the Watch off for three workouts the card
shows again.

**Follow-up (not built).** None may change a target's action, load, reps or sets.

1. Train card (Flutter): the training hub is SQL called straight from the app, so TypeScript signals do
   not reach it. A card line needs a Dart twin `load_signals.dart` with shared cases (the C3 pattern:
   `profile_cases.json` read by both) and a `get_my_workout_load_inputs_v1` for the signed-in athlete.
   It is a second copy of the rules and the owner has not asked for the line.
2. B4 (same-day readiness) reads `engine.confidence` and `engine.question` through
   `loadWorkoutLoadSignals`.

**Decisions for the owner (C4).** The program doc holds only the one-line brief "Watch-workout prompt,
load signals for the engine", so these readings are mine; each is the more conservative choice.
- The prompt asks the athlete to start a Watch workout (it cannot tell whether a Watch exists). It
  shows only before the first set, only when the last three workouts had no Watch heart rate, and is
  muted per phone. Other reading not built: asking about an Apple Health workout that has no Tracend
  session (the existing reconciliation card already handles the matched case).
- The thresholds (50% of reserve, 120 seconds, 12 sets in 2 workouts, 28 days) are Tracend's own and wait
  for a coach's review, like the progression thresholds.
- No signal raises confidence or sets anything. Coach seeing the signals with fixed wording is approved
  and built; whether Train should show a rest line (follow-up 1) is still yours.
- A beta-blocker blunts heart rate, which can only remove a caution; medications are unknown until L3.

## Next agent starts here

C4 is built and in review (above); what is left is the "Follow-up (not built)" list. Read the profile
with `buildHeartRateProfile` (Dart or TypeScript) from `get_my_heart_rate_inputs_v1`; do not read raw
samples through a new path without updating SECURITY_PRIVACY §4. Sleeping heart rate stays in shadow
mode (D10) until a reviewed change updates `sleeping_heart_rate_shadow_test.sql`. The `heart_rate_profile`
contributor is registered (E3). The brief is in the program doc.
