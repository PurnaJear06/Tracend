import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/plan_changes.dart';

const _offline = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
  authMode: 'owner_email_password',
);

const _brief = 'Today: daily brief';

/// A brief request that waits until it is released, then fails or answers.
class _HeldBrief implements DailyBriefRepository {
  final requests = <Completer<bool>>[];

  @override
  Future<DailyBrief> load(DateTime date) async {
    final request = Completer<bool>();
    requests.add(request);
    if (!await request.future) {
      throw const PostgrestException(message: 'refused', code: '42501');
    }
    return DailyBrief(localDate: date.toIso8601String().substring(0, 10));
  }
}

/// Only the brief load Today shows counts toward a run of failures.
void main() {
  late PlanChanges planChanges;

  setUp(() {
    resetLoadFailures();
    planChanges = PlanChanges();
    addTearDown(resetLoadFailures);
  });

  Future<void> pump(WidgetTester tester, DailyBriefRepository brief) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [TracendColors.dark],
        ),
        home: TodayScreen(
          environment: _offline,
          brief: brief,
          planChanges: planChanges,
          queueFactory: () => CheckInQueue(preferences),
          clock: () => DateTime(2026, 10, 1, 9),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('a load replaced by a newer one is not counted', (tester) async {
    final brief = _HeldBrief();
    await pump(tester, brief);
    planChanges.announce();
    await tester.pump();
    expect(brief.requests, hasLength(2));

    brief.requests[0].complete(false);
    await settle(tester);
    expect(loadFailuresInARow(_brief), 0);

    brief.requests[1].complete(false);
    await settle(tester);
    expect(loadFailuresInARow(_brief), 1);

    planChanges.announce();
    await tester.pump();
    brief.requests[2].complete(true);
    await settle(tester);
    expect(loadFailuresInARow(_brief), 0);
  });

  testWidgets('one request shared by several loads counts once', (
    tester,
  ) async {
    final inner = _HeldBrief();
    await pump(tester, SharedDailyBriefRepository(inner));
    planChanges
      ..announce()
      ..announce();
    await tester.pump();
    expect(inner.requests, hasLength(1));

    inner.requests.single.complete(false);
    await settle(tester);
    expect(loadFailuresInARow(_brief), 1);
  });
}
