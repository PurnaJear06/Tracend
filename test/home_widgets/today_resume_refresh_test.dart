import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';

import 'fake_home_widget_bridge.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

/// Answers each load with the date it was asked for and more protein every
/// time, so a widget snapshot that is not rebuilt from a new load shows.
class _CountingBriefs implements DailyBriefRepository {
  final dates = <DateTime>[];

  int get loads => dates.length;

  @override
  Future<DailyBrief> load(DateTime date) async {
    dates.add(date);
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return DailyBrief(
      localDate: day,
      workout: const {'name': 'Push day'},
      checkIn: const {'energy': 3},
      nutrition: {'calories': 1000, 'protein_g': 40 * dates.length},
    );
  }
}

Future<void> _background(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

Future<void> _foreground(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

void main() {
  late _CountingBriefs briefs;
  late FakeHomeWidgetBridge bridge;
  late DateTime now;
  late ValueNotifier<int> taps;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    briefs = _CountingBriefs();
    bridge = FakeHomeWidgetBridge();
    now = DateTime(2026, 10, 18, 7, 30);
    taps = ValueNotifier(0);
  });

  Future<void> pumpToday(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TodayScreen(
            environment: _environment,
            brief: briefs,
            clock: () => now,
            widgetTaps: taps,
            widgetPublisher: TodayWidgetPublisher(
              bridge: bridge,
              preferences: SharedPreferencesAsync(),
              clock: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> nutrition() =>
      bridge.stored!['nutrition'] as Map<String, dynamic>;

  testWidgets('a quick return keeps the brief and the snapshot', (
    tester,
  ) async {
    await pumpToday(tester);
    expect(briefs.loads, 1);

    await _background(tester);
    now = now.add(const Duration(minutes: 10));
    await _foreground(tester);

    expect(briefs.loads, 1);
    expect(bridge.writes, 1);
  });

  testWidgets('a return after half an hour loads again and republishes it', (
    tester,
  ) async {
    await pumpToday(tester);
    final firstTime = bridge.stored!['generated_at_millis'] as int;
    expect(nutrition()['protein_g'], 40);

    await _background(tester);
    now = now.add(const Duration(minutes: 31));
    await _foreground(tester);

    expect(briefs.loads, 2);
    expect(nutrition()['protein_g'], 80);
    expect(bridge.stored!['generated_at_millis'], greaterThan(firstTime));
  });

  testWidgets('a new day loads again at once, whatever the age', (
    tester,
  ) async {
    now = DateTime(2026, 10, 18, 23, 50);
    await pumpToday(tester);
    expect(bridge.stored!['local_date'], '2026-10-18');

    await _background(tester);
    now = DateTime(2026, 10, 19, 0, 5);
    await _foreground(tester);

    expect(briefs.loads, 2);
    expect(briefs.dates.last.day, 19);
    expect(bridge.stored!['local_date'], '2026-10-19');
  });

  testWidgets('a widget tap reloads an old brief and leaves a fresh one', (
    tester,
  ) async {
    await pumpToday(tester);

    taps.value++;
    await tester.pumpAndSettle();
    expect(briefs.loads, 1);

    now = now.add(const Duration(hours: 13));
    taps.value++;
    await tester.pumpAndSettle();

    expect(briefs.loads, 2);
    expect(nutrition()['protein_g'], 80);
  });

  testWidgets('a return after a failed first load tries again', (tester) async {
    final failing = _FailingOnceBriefs();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TodayScreen(
            environment: _environment,
            brief: failing,
            clock: () => now,
            widgetPublisher: TodayWidgetPublisher(
              bridge: bridge,
              preferences: SharedPreferencesAsync(),
              clock: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(bridge.stored, isNull);

    await _background(tester);
    await _foreground(tester);

    expect(failing.loads, 2);
    expect(bridge.stored, isNotNull);
  });

  testWidgets('a slow load from before midnight never overwrites the new day', (
    tester,
  ) async {
    final held = _HeldBriefs();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    now = DateTime(2026, 10, 18, 23, 59);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: TodayScreen(
            environment: _environment,
            brief: held,
            clock: () => now,
            widgetPublisher: TodayWidgetPublisher(
              bridge: bridge,
              preferences: SharedPreferencesAsync(),
              clock: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(held.requests, hasLength(1));

    // Past midnight the first request is still open, so the return asks
    // again; the new day's answer arrives first.
    await _background(tester);
    now = DateTime(2026, 10, 19, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(held.requests, hasLength(2));

    held.requests[1].complete(_brief('2026-10-19', protein: 80));
    await tester.pumpAndSettle();
    expect(bridge.stored!['local_date'], '2026-10-19');

    held.requests[0].complete(_brief('2026-10-18', protein: 40));
    await tester.pumpAndSettle();

    expect(bridge.stored!['local_date'], '2026-10-19');
    expect(nutrition()['protein_g'], 80);
    expect(bridge.writes, 1);
  });
}

DailyBrief _brief(String day, {required int protein}) => DailyBrief(
  localDate: day,
  workout: const {'name': 'Push day'},
  checkIn: const {'energy': 3},
  nutrition: {'calories': 1000, 'protein_g': protein},
);

/// Holds every request open until the test answers it.
class _HeldBriefs implements DailyBriefRepository {
  final requests = <Completer<DailyBrief>>[];

  @override
  Future<DailyBrief> load(DateTime date) {
    final request = Completer<DailyBrief>();
    requests.add(request);
    return request.future;
  }
}

class _FailingOnceBriefs implements DailyBriefRepository {
  int loads = 0;

  @override
  Future<DailyBrief> load(DateTime date) async {
    loads++;
    if (loads == 1) throw StateError('offline');
    return DailyBrief(localDate: '2026-10-18');
  }
}
