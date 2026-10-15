# Session Timing and Heart Rate Handoff

**As of:** 2026-10-15

Part of the coaching platform program:
[`docs/plans/coaching-platform-2026-10/README.md`](../plans/coaching-platform-2026-10/README.md).
Read it first; it holds the contracts, file owners and migration codes.

## Goal

Per-set start and end times, actual rest and reps-left (Contract 2), workout events (Contract 3), then per-set Apple Watch heart-rate summaries (Contract 4) and a personal heart-rate profile. Heart rate never sets the load.

## Chunks

C1 (Phase 1); C2 (Phase 2); C3 (Phase 3); C4 (Phase 4)

## State

**C1 (set timing, reps left, workout events): in review** on `claude/c1-set-timing` (draft PR
#104 to `main`). Not merged, not deployed; needs migration first, then an app install.

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

## Next agent starts here

After C1 merges: C2 (native heart-rate reader, per-set summaries) waits for D0. Read set windows
from `exercise_sets.started_at`/`completed_at` and listen to `WorkoutEventHub.events`; never write
sets.
