import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/widgets/account_widgets.dart';
import 'package:tracend/features/account/widgets/ai_usage_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';

Widget _wrap(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? TracendTheme.dark, home: child);

void main() {
  test('dollars show two decimals and never a misleading zero', () {
    expect(usdText(1), '\$1.00');
    expect(usdText(2), '\$2.00');
    expect(usdText(1.84), '\$1.84');
    expect(usdText(0.004), '<\$0.01');
    expect(usdText(0.0001), '<\$0.01');
    expect(usdText(0.005), '\$0.01');
    expect(usdText(0), '\$0.00');
  });

  test('the Account line places the cost against the server limits', () {
    AiUsageSummary summary(Map<String, dynamic> usage) =>
        AiUsageSummary.fromJson(usage);
    expect(
      summary({
        'estimated_cost_usd': 0.42,
        'warning_threshold_usd': 7.5,
        'hard_stop_usd': 12.25,
      }).accountLine,
      '\$0.42 of \$12.25 · warning at \$7.50',
    );
    expect(
      summary({
        'estimated_cost_usd': 8,
        'warning_threshold_usd': 7.5,
        'hard_stop_usd': 12.25,
        'warning': true,
      }).accountLine,
      '\$8.00 · approaching the \$12.25 limit',
    );
    expect(
      summary({
        'estimated_cost_usd': 12.3,
        'hard_stop_usd': 12.25,
        'blocked': true,
      }).accountLine,
      '\$12.30 · paused at the \$12.25 limit · plans and logging still work',
    );
    expect(
      summary({'successful_runs': 3, 'estimated_cost_usd': 0.01}).accountLine,
      '\$0.01 estimate · 3 requests',
    );
  });

  testWidgets('shows the brand loader while usage resolves', (tester) async {
    await tester.pumpWidget(
      _wrap(AiUsageScreen(coach: _LoadingUsageRepository())),
    );
    expect(find.byType(TracendLoader), findsOneWidget);
  });

  testWidgets('renders every value from the merged RPC response', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AiUsageScreen(
          coach: _UsageRepository({
            'period': 'current_month',
            'successful_runs': 28,
            'failed_runs': 2,
            'estimated_cost_usd': 1.84,
            'warning_threshold_usd': 3,
            'hard_stop_usd': 5,
            'warning': false,
            'blocked': false,
            'today_requests': 4,
            'daily_limit': 30,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\$1.84'), findsOneWidget);
    expect(find.text('Estimated this month, of \$5.00'), findsOneWidget);
    expect(find.text('Warning at \$3.00 · Stops at \$5.00'), findsOneWidget);
    expect(find.text('Available'), findsWidgets);
    expect(find.byType(AiUsageMeter), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('37 percent')), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(AiUsageMeter)).label,
      'AI usage this month: \$1.84 of \$5.00, 37 percent. Warning at \$3.00',
    );
    handle.dispose();
    await tester.scrollUntilVisible(find.text('Requests today'), 200);
    expect(find.text('Requests today'), findsOneWidget);
    expect(find.text('4 of 30'), findsOneWidget);
    expect(find.text('Successful this month'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('Warning at'), findsOneWidget);
    expect(find.text('\$3.00'), findsOneWidget);
    expect(find.text('Monthly limit'), findsOneWidget);
    expect(find.text('\$5.00'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('not an invoice'), 200);
    expect(find.textContaining('not an invoice'), findsOneWidget);
  });

  testWidgets('a tiny cost reads <\$0.01, not \$0.00', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AiUsageScreen(
          coach: _UsageRepository(const {
            'successful_runs': 2,
            'failed_runs': 0,
            'estimated_cost_usd': 0.0031,
            'warning_threshold_usd': 1,
            'hard_stop_usd': 2,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('<\$0.01'), findsOneWidget);
    expect(find.text('\$0.00'), findsNothing);
    expect(find.text('Warning at \$1.00 · Stops at \$2.00'), findsOneWidget);
  });

  testWidgets('degrades gracefully when budget fields are absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AiUsageScreen(
          coach: _UsageRepository(const {
            'period': 'current_month',
            'successful_runs': 0,
            'failed_runs': 0,
            'estimated_cost_usd': 0,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiUsageMeter), findsNothing);
    expect(find.text('Warning at'), findsNothing);
    expect(find.text('Monthly limit'), findsNothing);
    expect(find.text('Requests today'), findsNothing);
    expect(find.text('No AI runs recorded this month.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Estimates only'), 200);
    expect(find.text('Estimates only'), findsOneWidget);
  });

  testWidgets('blocked budget shows the paused state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AiUsageScreen(
          coach: _UsageRepository({
            'successful_runs': 40,
            'failed_runs': 0,
            'estimated_cost_usd': 5.2,
            'warning_threshold_usd': 3,
            'hard_stop_usd': 5,
            'warning': true,
            'blocked': true,
            'today_requests': 0,
            'daily_limit': 30,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Service'), 200);
    expect(find.text('Paused at the monthly limit'), findsNWidgets(2));
  });

  testWidgets('unavailable usage offers a working retry', (tester) async {
    final repository = _FlakyUsageRepository();
    await tester.pumpWidget(_wrap(AiUsageScreen(coach: repository)));
    await tester.pumpAndSettle();

    expect(find.text('Usage could not load'), findsOneWidget);
    expect(repository.calls, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('\$0.01'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('refresh refetches and initial usage skips the first fetch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _CountingUsageRepository();
    await tester.pumpWidget(
      _wrap(
        AiUsageScreen(
          coach: repository,
          initialUsage: const {
            'successful_runs': 1,
            'failed_runs': 0,
            'estimated_cost_usd': 0.5,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.calls, 0);

    await tester.tap(find.text('Refresh usage'));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
  });

  for (final theme in [TracendTheme.dark, TracendTheme.light]) {
    testWidgets('usage lays out at 320pt × 2 text (${theme.brightness.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _wrap(
          theme: theme,
          AiUsageScreen(
            coach: _UsageRepository(const {
              'successful_runs': 12,
              'failed_runs': 1,
              'estimated_cost_usd': 1.2,
              'warning_threshold_usd': 1,
              'hard_stop_usd': 2,
              'warning': true,
              'today_requests': 3,
              'daily_limit': 30,
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

class _UsageRepository implements CoachRepository {
  const _UsageRepository(this.usage);

  final Map<String, dynamic> usage;

  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async => usage;
}

class _LoadingUsageRepository implements CoachRepository {
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() =>
      Completer<Map<String, dynamic>>().future;
}

class _FlakyUsageRepository implements CoachRepository {
  int calls = 0;

  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async {
    calls += 1;
    if (calls == 1) throw StateError('offline');
    return {'successful_runs': 1, 'failed_runs': 0, 'estimated_cost_usd': 0.01};
  }
}

class _CountingUsageRepository implements CoachRepository {
  int calls = 0;

  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async {
    calls += 1;
    return {'successful_runs': 2, 'failed_runs': 0, 'estimated_cost_usd': 0.75};
  }
}
