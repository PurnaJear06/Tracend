import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/widgets/ai_usage_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: TracendTheme.dark, home: child);

void main() {
  testWidgets('shows a spinner while usage resolves', (tester) async {
    await tester.pumpWidget(
      _wrap(AiUsageScreen(coach: _LoadingUsageRepository())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

    expect(find.text('\$1.8400'), findsOneWidget);
    expect(find.textContaining('of \$5 hard stop'), findsOneWidget);
    expect(find.text('Requests today'), findsOneWidget);
    expect(find.text('4 of 30'), findsOneWidget);
    expect(find.text('Successful this month'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('Warning threshold'), findsOneWidget);
    expect(find.text('\$3'), findsOneWidget);
    expect(find.text('Monthly hard stop'), findsOneWidget);
    expect(find.text('\$5'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('not an invoice'), 200);
    expect(find.textContaining('not an invoice'), findsOneWidget);
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

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Warning threshold'), findsNothing);
    expect(find.text('Monthly hard stop'), findsNothing);
    expect(find.text('Requests today'), findsNothing);
    expect(find.text('No AI runs recorded this month.'), findsOneWidget);
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

    expect(find.text('Paused at safety limit'), findsNWidgets(2));
  });

  testWidgets('unavailable usage offers a working retry', (tester) async {
    final repository = _FlakyUsageRepository();
    await tester.pumpWidget(_wrap(AiUsageScreen(coach: repository)));
    await tester.pumpAndSettle();

    expect(find.text('Usage could not load'), findsOneWidget);
    expect(repository.calls, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('\$0.0100'), findsOneWidget);
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
