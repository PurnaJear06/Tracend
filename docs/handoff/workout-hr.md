# Session Timing and Heart Rate Handoff

**As of:** 2026-10-16

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
  only when it has more readings. A server refusal ends the work; no connection keeps it waiting
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

## Next agent starts here

C3 (heart-rate profile, zones, recovery, sleeping heart rate in shadow mode, migration code 33),
Phase 3, after C2 merges. Read the per-set summaries with `get_my_set_heart_rate_v1`; do not read
raw samples through a new path without updating SECURITY_PRIVACY §4. Sleeping heart rate stays in
shadow mode (D10). The brief is in the program doc.
