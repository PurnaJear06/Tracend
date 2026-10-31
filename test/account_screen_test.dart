import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';

const _configured = AppEnvironment(
  name: 'test',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'test-key',
);

const _offline = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

Future<TracendThemeController> _pump(
  WidgetTester tester, {
  AppEnvironment environment = _offline,
  CoachRepository coach = const FixtureCoachRepository(),
  HealthRepository health = const ManualHealthRepository(),
  ThemeData? theme,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = TracendThemeController(ThemeMode.dark);
  await tester.pumpWidget(
    TracendThemeScope(
      notifier: controller,
      child: MaterialApp(
        theme: theme ?? TracendTheme.dark,
        home: AccountScreen(
          environment: environment,
          coach: coach,
          health: health,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  test('Apple Health status reads in plain words', () {
    final now = DateTime(2026, 10, 3, 18);
    expect(
      appleHealthStatusText(
        HealthSyncStatus(
          state: HealthConnectionState.connected,
          lastSuccessfulSync: DateTime(2026, 10, 3, 14, 5),
        ),
        now: now,
      ),
      'Updated today at 14:05',
    );
    expect(
      appleHealthStatusText(
        HealthSyncStatus(
          state: HealthConnectionState.partial,
          lastSuccessfulSync: DateTime(2026, 10, 2, 9, 30),
        ),
        now: now,
      ),
      'Updated yesterday at 09:30 · some signals missing',
    );
    expect(
      appleHealthStatusText(
        HealthSyncStatus(
          state: HealthConnectionState.stale,
          lastSuccessfulSync: DateTime(2026, 9, 28, 7, 0),
        ),
        now: now,
      ),
      'Updated Mon 28 Sep at 07:00 · needs a refresh',
    );
    expect(
      appleHealthStatusText(
        const HealthSyncStatus(state: HealthConnectionState.manualOnly),
        now: now,
      ),
      'Not connected · manual logging works',
    );
  });

  testWidgets('one grouped settings page with no dead Edit control', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Private beta'), findsOneWidget);
    for (final section in [
      'Plan',
      'Health',
      'Appearance',
      'Notifications',
      'AI coach',
      'Privacy',
    ]) {
      await tester.scrollUntilVisible(find.text(section), 200);
      expect(find.text(section), findsOneWidget);
    }
    expect(find.text('Rest timer alerts'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Delete account'), 200);
    expect(find.text('Export data'), findsOneWidget);
    expect(find.text('Consent history'), findsOneWidget);
    expect(find.text('Consent ledger'), findsNothing);
    expect(find.textContaining('audit'), findsNothing);
  });

  testWidgets('Appearance switches between System, Dark and Light', (
    tester,
  ) async {
    final controller = await _pump(tester);
    await tester.scrollUntilVisible(find.text('Light'), 200);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(controller.mode, ThemeMode.light);
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(controller.mode, ThemeMode.system);
  });

  testWidgets('AI usage this month renders only the server values', (
    tester,
  ) async {
    await _pump(
      tester,
      environment: _configured,
      coach: const _UsageCoach({
        'successful_runs': 9,
        'failed_runs': 0,
        'estimated_cost_usd': 0.4231,
        'warning_threshold_usd': 7.5,
        'hard_stop_usd': 12.25,
        'warning': false,
        'blocked': false,
      }),
    );
    await tester.scrollUntilVisible(find.text('AI usage this month'), 200);
    expect(find.text('\$0.42 of \$12.25 · warning at \$7.50'), findsOneWidget);
  });

  testWidgets('a cost under a cent reads <\$0.01 on the Account row', (
    tester,
  ) async {
    await _pump(
      tester,
      environment: _configured,
      coach: const _UsageCoach({
        'successful_runs': 1,
        'failed_runs': 0,
        'estimated_cost_usd': 0.002,
        'warning_threshold_usd': 1,
        'hard_stop_usd': 2,
      }),
    );
    await tester.scrollUntilVisible(find.text('AI usage this month'), 200);
    expect(find.text('<\$0.01 of \$2.00 · warning at \$1.00'), findsOneWidget);
    expect(find.textContaining('\$0.00'), findsNothing);
  });

  testWidgets('Apple Health opens its status in a sheet', (tester) async {
    await _pump(tester, health: const _SyncedHealth());
    await tester.scrollUntilVisible(find.text('Apple Health'), 200);
    expect(find.textContaining('Updated '), findsOneWidget);
    await tester.tap(find.text('Apple Health'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh Apple Health'), findsOneWidget);
  });

  for (final theme in [TracendTheme.dark, TracendTheme.light]) {
    testWidgets(
      'the whole page lays out at 320pt × 2 text (${theme.brightness.name})',
      (tester) async {
        await _pump(
          tester,
          environment: _configured,
          theme: theme,
          size: const Size(320, 844),
          textScale: 2,
          coach: const _UsageCoach({
            'successful_runs': 9,
            'failed_runs': 1,
            'estimated_cost_usd': 1.12,
            'warning_threshold_usd': 1,
            'hard_stop_usd': 2,
            'warning': true,
          }),
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -4500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Sign out'), findsOneWidget);
      },
    );
  }

  testWidgets('a double tap on Sign out signs out once and leaves Account', (
    tester,
  ) async {
    var calls = 0;
    final answer = Completer<void>();
    await _pushAccount(
      tester,
      onSignOut: (_) {
        calls++;
        return answer.future;
      },
    );
    final button = find.widgetWithText(OutlinedButton, 'Sign out');
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

    answer.complete();
    await tester.pumpAndSettle();
    // Back on the page below Account, never on an empty navigator.
    expect(find.text('Open account'), findsOneWidget);
    expect(find.byType(AccountScreen), findsNothing);
  });

  testWidgets('Account does not pop again when the gate already closed it', (
    tester,
  ) async {
    await _pushAccount(
      tester,
      // The gate pops every pushed route when the session ends.
      onSignOut: (context) async =>
          Navigator.of(context).popUntil((route) => route.isFirst),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Open account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pushAccount(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) onSignOut,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (inner) => AccountScreen(
                    environment: _offline,
                    onSignOut: () => onSignOut(inner),
                  ),
                ),
              ),
              child: const Text('Open account'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open account'));
  await tester.pumpAndSettle();
}

class _UsageCoach implements CoachRepository {
  const _UsageCoach(this.usage);

  final Map<String, dynamic> usage;

  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate({String? localDate}) =>
      throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async => usage;
}

class _SyncedHealth implements HealthRepository {
  const _SyncedHealth();

  static final _status = HealthSyncStatus(
    state: HealthConnectionState.connected,
    lastSuccessfulSync: DateTime.now().subtract(const Duration(minutes: 5)),
    availableMetrics: const {HealthMetric.steps, HealthMetric.sleep},
  );

  @override
  Future<HealthSyncStatus> loadStatus() async => _status;
  @override
  Future<HealthSyncStatus> connectAndSync() async => _status;
  @override
  Future<HealthSyncStatus> sync() async => _status;
  @override
  Future<HealthHistory> loadHistory() async => const HealthHistory([]);
}
