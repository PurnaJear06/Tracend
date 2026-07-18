# Plan: Completion State, Date Threading & Visual Indicators

## Issues Found

### A. Critical Bug: `_healthkitCandidate` not cleared after auto-complete
`_autoComplete` (`train_screen.dart:123`) does:
```dart
setState(() => _hub = _load());
```
`_healthkitCandidate` retains the old value → the prompt card stays visible after completion succeeds.

### B. Critical Bug: `DateTime.now()` hardcoded in all session operations
`loadSession` and `start` in `workout_repository.dart:462,480` always pass `DateTime.now()` as `p_local_date`. When user taps past weekday → `get_my_workout_session` RPC uses today's date. Since `get_my_workout_session` falls back to most-recent-completed-session (its ORDER BY: `started_at desc`), user sees the manually-logged session from a different day on every past weekday.

`_HealthkitCompleteCard.onManual` also loses `candidate.localDate` — navigates without passing the date.

### C. Gap: No per-day completion tracking in hub data
`get_my_training_hub` has aggregate `completed_sessions` count but no per-date map. `_WeekdayStrip` can't show completion dots. `_WorkoutHero` can't show completed state.

### D. Gap: Auto-completed sessions have no exercise data
`healthkit_auto_complete_workout` RPC creates a bare `workout_sessions` row — no `exercise_performances` or `exercise_sets`. When viewing the session, `ActiveWorkoutScreen._restoreAndStart` finds a completed session with empty exercises. Since it only hydrates from `state='in_progress'`, `_sessionId` stays null and a NEW session starts → duplicate or confusion.

### E. UX: Weekday strip + workout hero blind to completion
Gray dots only indicate "planned workout assigned" — no visual difference for completed days. `_WorkoutHero` always shows "Start workout" even when already done.

---

## Solutions

### 1. Fix `_autoComplete` — clear the candidate (train_screen.dart, 1 line)
```dart
setState(() {
  _hub = _load();
  _healthkitCandidate = null;
});
```

### 2. Thread date through navigation chain (4 files)

**workout_repository.dart** — Add optional `localDate` parameter:
```dart
Future<Map<String, dynamic>?> loadSession(PlannedWorkout workout, {DateTime? localDate});
Future<String> start(PlannedWorkout workout, String idempotencyKey, {DateTime? localDate});
```
Supabase implementations use `localDate ?? DateTime.now()`. Fixture/mock repos accept but ignore.

**workout_detail_screen.dart** — Accept `DateTime? sessionDate`:
```dart
class WorkoutDetailScreen extends StatefulWidget {
  const WorkoutDetailScreen({
    required this.workout,
    this.repository,
    this.sessionDate,
    super.key,
  });
```
Pass to `ActiveWorkoutScreen`.

**active_workout_screen.dart** — Accept `DateTime? sessionDate`:
```dart
class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({
    required this.workout,
    required this.repository,
    this.sessionDate,
    super.key,
  });
```
Use in `_restoreAndStart`:
```dart
final server = await widget.repository.loadSession(widget.workout, localDate: widget.sessionDate);
_sessionId ??= await widget.repository.start(widget.workout, _idempotencyKey, localDate: widget.sessionDate);
```

**train_screen.dart** — Pass date from both paths:
- `_WorkoutHero`: pass `_dateForWeekday(_weekday)` as `sessionDate`
- `_HealthkitCompleteCard.onManual`: pass `candidate.localDate` as `sessionDate`
- Both `WorkoutDetailScreen` calls gain the parameter

### 3. Add `completed_day_set` to hub (migration v1.3)

New migration `20260718150000_hub_completed_day_set.sql` replaces `get_my_training_hub`:
```sql
'completed_day_set', coalesce(
  (select jsonb_agg(distinct local_date) from completed), '[]'::jsonb
)
```
Returns e.g. `["2026-07-14","2026-07-15","2026-07-17"]`. Schema version 1.3.

### 4. Parse in Dart (workout_repository.dart)

`TrainingHubData` gains:
```dart
final Set<DateTime> completedDays;
bool isDayCompleted(DateTime date) => completedDays.any(
  (d) => d.year == date.year && d.month == date.month && d.day == date.day,
);
```
Parsed in `loadTrainingHub()` from `value['completed_day_set']`.

### 5. Weekday strip: green completion dots (train_screen.dart)

`_WeekdayStrip` gains:
```dart
final Set<DateTime> completedDays;
final DateTime Function(int weekday) dateForWeekday;
```
For each weekday chip, compute date via `dateForWeekday(day)`:
- Date is in `completedDays` → green `check_mark_circled_solid` (Color(0xFF34C759))
- Date has planned workout but NOT completed → gray `circle_fill` (current behavior)
- No planned workout → nothing

### 6. WorkoutHero: completed state (train_screen.dart)

`_WorkoutHero` gains:
```dart
final bool isCompleted;
final DateTime sessionDate;
```
When `isCompleted`:
- Status pill: "Completed" with `check_mark_circled_solid` icon + green tint
- Button: "View workout" (outlined) instead of "Start workout" (filled)
- Navigation still goes to `WorkoutDetailScreen` but passes `sessionDate`

### 7. Auto-completed session display (active_workout_screen.dart)

Modify `_restoreAndStart` to handle completed sessions:
```dart
if (server != null && server['state'] == 'completed') {
  _sessionId = server['session_id'] as String;
  _isViewingCompleted = true;
  final exercises = server['exercises'] as List?;
  if (exercises != null && exercises.isNotEmpty && exercises.first is Map) {
    _hydrateFromServer(server);  // manual session with sets
  } else {
    _hydrateFromPlan();  // auto-completed: show plan exercises as reference
  }
  if (mounted) setState(() {});
  return;
}
```

Add `_isViewingCompleted` flag:
- When true, show info banner at top: "Auto-completed from HealthKit — no individual sets logged" (if auto), or "Viewing completed session" (if manual)
- Sets are read-only (no editing)
- Complete button says "Done" and just pops back
- `_changed()` debounce does NOT fire (no autosave needed)

### 8. Tests

**Updated tests:**
- Fixture hub test: verify `completedDays` is empty
- `_HealthkitCandidateRepository`: add `completedDays` = empty
- Widget test: weekday strip shows green dot when date is in completedDays
- Widget test: workout hero shows "View workout" when completed
- Widget test: "Start workout" still shows when not completed
- Widget test: auto-complete popup clears and refreshing hub

**New tests:**
- Widget test: tapping past weekday with completed session shows "View workout"
- Widget test: `sessionDate` is passed through navigation chain (verify mock receives correct date)

### 9. Docs
- `docs/UX_FLOWS.md` §7: update for per-date + completion indicators
- `docs/TESTING_STRATEGY.md`: add hub completed_day_set + widget indicators
- `docs/handoff/frontend.md`: update date threading, completed state, migration
- `docs/PROGRESS_CONTEXT.md`: summarize all changes

---

## Files Changed
1. `supabase/migrations/20260718150000_hub_completed_day_set.sql` — NEW: replaces hub (v1.3, adds completed_day_set)
2. `lib/features/train/train_screen.dart` — candidate fix, weekday dots, hero state, date passing
3. `lib/features/train/workout_repository.dart` — completedDays, optional localDate params
4. `lib/features/train/workout_detail_screen.dart` — sessionDate param
5. `lib/features/train/active_workout_screen.dart` — sessionDate, completed viewing mode
6. `test/production_rebuild_flutter_test.dart` — updated + new tests
7. `docs/UX_FLOWS.md`, `docs/TESTING_STRATEGY.md`, `docs/handoff/frontend.md`, `docs/PROGRESS_CONTEXT.md`

## Execution Order
1. Migration (SQL)
2. Repository (Dart interface + implementation)
3. TrainScreen (visual indicators + date passing + candidate fix)
4. WorkoutDetailScreen (sessionDate param)
5. ActiveWorkoutScreen (sessionDate param + completed viewing)
6. Tests
7. Docs
8. Deploy + build + install
