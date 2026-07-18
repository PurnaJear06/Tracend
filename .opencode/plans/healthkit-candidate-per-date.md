# Plan: Per-Date HealthKit Quick-Complete

## Problem
`get_my_training_hub` hardcodes `current_date` in the `healthkit_candidate` CTE (lines 50, 57, 60). Only today ever shows the "Apple Health detected workout" prompt. Past weekdays never get quick-complete.

## Approach
Remove hub-level candidate, create standalone per-date RPC. Train screen fetches candidate for whichever weekday the user selects (including today). Hub stays fast — no heavyweight reload on weekday switch.

## Changes

### 1. New SQL Migration
File: `supabase/migrations/20260718110000_healthkit_candidate_per_date.sql`

**a) Replace `get_my_training_hub`:**
- Remove `healthkit_candidate` CTE entirely
- Remove `healthkit_completion_candidate` from final JSON
- Bump `schema_version` to `1.2`

**b) New RPC `get_healthkit_completion_candidate(p_local_date date)`:**
```sql
create or replace function public.get_healthkit_completion_candidate(p_local_date date)
returns jsonb language sql security definer set search_path='' stable as $$
  select jsonb_build_object(
    'planned_workout_id', w.id,
    'planned_workout_name', w.name,
    'workout_count', h.workout_count,
    'workout_minutes', h.workout_minutes,
    'local_date', h.local_date
  )
  from public.planned_workouts w
  join public.training_plan_versions v
    on v.id = w.plan_version_id and v.user_id = w.user_id and v.status = 'active'
  join public.daily_health_summaries h
    on h.user_id = v.user_id and h.local_date = p_local_date
    and h.source_scope = 'healthkit' and h.workout_count > 0
  where w.user_id = auth.uid()
    and w.preferred_weekday = extract(isodow from p_local_date)::integer
    and not exists (
      select 1 from public.workout_sessions s
      where s.user_id = w.user_id and s.planned_workout_id = w.id
        and s.local_date = p_local_date and s.state = 'completed'
    )
  limit 1;
$$;
grant execute on function public.get_healthkit_completion_candidate(date) to authenticated;
```

### 2. Repository
File: `lib/features/train/workout_repository.dart`

- Remove `healthkitCompletionCandidate` field from `TrainingHubData` (line 137)
- Remove `_parseHealthkitCandidate` parsing in `loadTrainingHub()` (lines 294-300)
- Add to `SupabaseWorkoutRepository`:
```dart
Future<HealthkitCompletionCandidate?> getHealthkitCandidate(DateTime date) async {
  final value = await _client.rpc(
    'get_healthkit_completion_candidate',
    params: {'p_local_date': date.toIso8601String().substring(0, 10)},
  );
  if (value == null || value is! Map || (value as Map).isEmpty) return null;
  return _parseHealthkitCandidate(Map<String, dynamic>.from(value));
}
```

### 3. Train Screen
File: `lib/features/train/train_screen.dart`

**New state:**
```dart
HealthkitCompletionCandidate? _healthkitCandidate;
```

**New computed date from weekday:**
```dart
DateTime _dateForWeekday(int weekday) {
  final today = DateTime.now();
  final diff = (today.weekday - weekday + 7) % 7;
  return DateTime(today.year, today.month, today.day - diff);
}
```

**New fetch method:**
```dart
Future<void> _fetchHealthkitCandidate() async {
  final date = _dateForWeekday(_weekday);
  if (_source is! SupabaseWorkoutRepository) return;
  final candidate = await (_source as SupabaseWorkoutRepository).getHealthkitCandidate(date);
  if (!mounted) return;
  setState(() => _healthkitCandidate = candidate);
}
```

**In `initState`, after `_hub = _load()`:**
```dart
_fetchHealthkitCandidate();
```

**In `_weekday` setState (line 175):**
```dart
onSelected: (value) => setState(() {
  _weekday = value;
  _healthkitCandidate = null;
  _fetchHealthkitCandidate();
}),
```
Wait — `setState` can't be async. Need to call `_fetchHealthkitCandidate` after `setState`. Use a helper:
```dart
void _selectWeekday(int day) {
  if (day == _weekday) return;
  setState(() {
    _weekday = day;
    _healthkitCandidate = null;
  });
  _fetchHealthkitCandidate();
}
```

**In `build()` (lines 207-227), replace `hub.healthkitCompletionCandidate` with `_healthkitCandidate`:**
```dart
if (_healthkitCandidate != null)
  _HealthkitCompleteCard(
    candidate: _healthkitCandidate!,
    onComplete: () => _autoComplete(_healthkitCandidate!),
    onManual: () => Navigator.of(context).push<bool>(...).then(...),
  )
else
  _WorkoutHero(...)
```

### 4. Tests
File: `test/production_rebuild_flutter_test.dart`

- Line 77: Remove `expect(hub.healthkitCompletionCandidate, isNull);`
- `_HealthkitCandidateRepository`: Remove `healthkitCompletionCandidate` from `loadTrainingHub()` return.
  BUT — the widget test at line 80-96 relies on seeing the prompt. After this change, the prompt data won't come from the hub.
  
  **Two options:**
  A) Use a real `SupabaseWorkoutRepository` with a mock Supabase client
  B) Restructure the test: manually set `_healthkitCandidate` state via a test-only setter, or add a new interface
  
  **Recommendation:** Add a `HealthkitCandidateRepository` abstract interface:
  ```dart
  abstract interface class HealthkitCandidateRepository {
    Future<HealthkitCompletionCandidate?> getHealthkitCandidate(DateTime date);
  }
  ```
  Have `_HealthkitCandidateRepository` implement it, and have the train screen accept it via its repository. This keeps the test clean.

  Actually — simpler: just have the train screen check `_source is SupabaseWorkoutRepository || _source is HealthkitCandidateRepository` or cast to a common interface. Or just have the test mock override `getHealthkitCandidate` on `_HealthkitCandidateRepository`.

  Simplest approach: make `_HealthkitCandidateRepository` extend `FixtureWorkoutRepository` and override a new method. Or, add `getHealthkitCandidate` as a method on the repository and have the train screen call it through a type check.

  Let me think about the cleanest way...

  The train screen already does `_source is SupabaseWorkoutRepository` checks. I'll do the same pattern. Add the method to `SupabaseWorkoutRepository`, and in the test, `_HealthkitCandidateRepository` just doesn't return the candidate from the hub — it implements a mock method.

  Actually the simplest: make `_HealthkitCandidateRepository` implement `getHealthkitCandidate` and have the train screen check `if (_source is SupabaseWorkoutRepository)`. For the test, `_HealthkitCandidateRepository` won't match, so `_fetchHealthkitCandidate` won't call anything. The test will fail because the prompt won't appear.

  I need a clean way to inject the candidate. Options:
  1. Make the train screen accept an optional `HealthkitCompletionCandidate? initialCandidate` parameter
  2. Add a `HealthkitCandidateRepository` interface
  3. Have the test widget pump, then call a method on the state

  I'll go with approach 2 — a narrow interface:

  ```dart
  abstract interface class HealthkitCandidateRepository {
    Future<HealthkitCompletionCandidate?> getHealthkitCandidate(DateTime date);
  }
  ```
  
  Add this to `SupabaseWorkoutRepository`:
  ```dart
  class SupabaseWorkoutRepository ... implements HealthkitCandidateRepository { ... }
  ```

  In `_HealthkitCandidateRepository`:
  ```dart
  class _HealthkitCandidateRepository extends FixtureWorkoutRepository implements HealthkitCandidateRepository {
    @override
    Future<HealthkitCompletionCandidate?> getHealthkitCandidate(DateTime date) async =>
        HealthkitCompletionCandidate(
          plannedWorkoutId: PlannedWorkout.fixture.id,
          plannedWorkoutName: 'Full body push',
          workoutCount: 1,
          workoutMinutes: 60,
          localDate: date,
        );
  }
  ```

  In train screen, change `_fetchHealthkitCandidate`:
  ```dart
  Future<void> _fetchHealthkitCandidate() async {
    if (_source is! HealthkitCandidateRepository) return;
    final date = _dateForWeekday(_weekday);
    final candidate = await (_source as HealthkitCandidateRepository).getHealthkitCandidate(date);
    if (!mounted) return;
    setState(() => _healthkitCandidate = candidate);
  }
  ```

  The widget test: tap a different weekday, wait, verify prompt still shows (since the mock returns a candidate for any date).

  Actually the existing test at line 80-96 doesn't tap a weekday — it just renders with `_HealthkitCandidateRepository` and expects the prompt. But now the prompt won't appear on initial load because `_fetchHealthkitCandidate()` is async and the initial `_healthkitCandidate` is null.

  Fix: In `initState`, we need to wait for the candidate. But `initState` can't be async. Options:
  - Use `WidgetsBinding.instance.addPostFrameCallback` → fetch after first build
  - Fetch in `didChangeDependencies`
  - Return a different state from `initState` that triggers `_hub` load which then triggers candidate load

  Actually the simplest: just call `_fetchHealthkitCandidate()` from `initState` — it's async, it'll update state when done. On first render, `_healthkitCandidate` is null, so the WorkoutHero shows briefly, then when the candidate resolves, the card swaps. This is acceptable behavior (and actually might even reduce perceived flicker since the candidate is usually null anyway).

  For the test, we need to wait for the async candidate to resolve:
  ```dart
  await tester.pumpAndSettle(); // first render
  // _fetchHealthkitCandidate is called in initState, needs another pump
  await tester.pumpAndSettle(); // wait for async
  ```

  Actually `pumpAndSettle` should handle this since it keeps pumping until no more frames are scheduled. But the async callback from `_fetchHealthkitCandidate` might need an extra pump. Let me think... 

  `_fetchHealthkitCandidate()` is called in `initState`. It does `await repo.getHealthkitCandidate(date)`, then `setState`. The `setState` triggers a rebuild. `pumpAndSettle` should catch this. But the `await` means the callback is scheduled as a microtask. `pumpAndSettle` pumps frames, and between frames, microtasks run. So `pumpAndSettle` should work.

  Let me also add a test for the per-date scenario:
  ```dart
  testWidgets('Train shows HealthKit prompt for past weekday with data', (tester) async {
    // ...
    // Tap Tuesday chip
    await tester.tap(find.byType(ChoiceChip).at(1)); // Tuesday
    await tester.pumpAndSettle();
    // Verify prompt still shows (mock returns candidate for any date)
    expect(find.text('Apple Health detected workout'), findsOneWidget);
  });
  ```

  And the "no candidate" test (line 98-110) should still work since `FixtureWorkoutRepository` doesn't implement `HealthkitCandidateRepository`.

### 5. Documentation
- `docs/DATA_MODEL.md`: Remove `healthkit_completion_candidate` from hub JSON schema, add `get_healthkit_completion_candidate` RPC
- `docs/UX_FLOWS.md`: Update §7 to note candidate appears for any selected date, not just today
- `docs/TESTING_STRATEGY.md`: Update RPC entry for new function name, update widget test entries
- `docs/handoff/frontend.md`: Update with new per-date candidate behavior
- `docs/PROGRESS_CONTEXT.md`: Update with this change

### 6. Deploy & Verify
- `npx supabase db push` to deploy new migration
- `flutter analyze` — must be clean
- `flutter test` — all tests must pass (including updated widget tests)
- Rebuild iOS profile, install via `xcrun devicectl`

## Files Changed
- `supabase/migrations/20260718110000_healthkit_candidate_per_date.sql` — NEW (replaces hub, creates per-date RPC)
- `lib/features/train/workout_repository.dart` — remove hub candidate, add `HealthkitCandidateRepository` interface + `getHealthkitCandidate`
- `lib/features/train/train_screen.dart` — add `_healthkitCandidate`, `_selectWeekday`, `_fetchHealthkitCandidate`, `_dateForWeekday`
- `test/production_rebuild_flutter_test.dart` — update tests
- `docs/DATA_MODEL.md`, `docs/UX_FLOWS.md`, `docs/TESTING_STRATEGY.md`, `docs/handoff/frontend.md`, `docs/PROGRESS_CONTEXT.md`
