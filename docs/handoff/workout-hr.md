# Session Timing and Heart Rate Handoff

**As of:** 2026-10-17

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

- Migration `20261017110233_heart_rate_profile.sql` (code 33, re-stamp before handoff): table
  `sleeping_heart_rate_nights` (RLS on and forced, owner select only; one derived row per night:
  median, lowest 10-minute mean, readings, minutes asleep, coverage), `persist_sleeping_heart_rate_v1`
  (security definer, authenticated, 1 to 14 nights, 22023 on invalid values, `schema_version` 1.0),
  `get_my_heart_rate_inputs_v1(local_date)` (own data, 1.0) and `get_heart_rate_inputs_v1(user, date)`
  (service role only, the same object). The inputs hold the birth year, 14 days of resting heart rate,
  60 days of per-set summaries and the 10 highest peaks of 365 days; no sleeping heart rate. The profile
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
- Not done (owner or lead): `Info.plist` purpose string still reads "selected activity, recovery and
  workout heart-rate data"; it does not name sleeping heart rate (the file is not C3's).

Owner device check after install (a build from `main` once the migration is deployed): open Account,
Apple Health, tap Refresh (allow Heart Rate in the Apple Health sheet if it shows). With 3 or more
days of resting heart rate the Heart-rate zones section lists five zones and "Max ... estimated from your
age" (it needs a birth year in the profile). After a few tracked workouts a recovery line appears. The
next morning, ask for the `sleeping_heart_rate_nights` rows (SQL editor) to see last night; no score
changes. A night with the Watch off has no row.

## Next agent starts here

C4 (Watch-workout prompt, load signals for the engine), Phase 4, after C3 merges. Read the profile
with `buildHeartRateProfile` (Dart or TypeScript) from `get_my_heart_rate_inputs_v1`; do not read raw
samples through a new path without updating SECURITY_PRIVACY §4. Sleeping heart rate stays in shadow
mode (D10) until a reviewed change updates `sleeping_heart_rate_shadow_test.sql`. The lead registers the
`heart_rate_profile` contributor with E3. The brief is in the program doc.
