import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/widgets/health_check_screen.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';

const _configured = AppEnvironment(
  name: 'test',
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'test-key',
);

const _moderateAnswers = ScreeningAnswers(
  exercisesRegularly: true,
  knownCondition: true,
  symptoms: false,
  clearedByProfessional: false,
);

class _Screening implements ScreeningRepository {
  _Screening({
    this.stored = const StoredScreening(
      outcome: ScreeningOutcome.moderateUntilCleared,
      answers: _moderateAnswers,
    ),
    this.failLoads = 0,
  });

  final StoredScreening stored;
  int failLoads;
  bool failRecord = false;
  final recorded = <ScreeningAnswers>[];
  Completer<void>? recordDelay;

  @override
  Future<StoredScreening> loadScreening() async {
    if (failLoads > 0) {
      failLoads--;
      throw Exception('offline');
    }
    return stored;
  }

  @override
  Future<ScreeningRecord> recordScreening(ScreeningAnswers answers) async {
    if (failRecord) throw Exception('offline');
    recorded.add(answers);
    await recordDelay?.future;
    // The server's own rule, as in the database.
    final outcome = answers.symptoms
        ? ScreeningOutcome.seeProfessional
        : answers.knownCondition && !answers.clearedByProfessional
        ? (answers.exercisesRegularly
              ? ScreeningOutcome.moderateUntilCleared
              : ScreeningOutcome.seeProfessional)
        : ScreeningOutcome.cleared;
    return ScreeningRecord(outcome: outcome, screenedAt: DateTime.utc(2026));
  }
}

Future<void> _pump(WidgetTester tester, ScreeningRepository repository) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: HealthCheckScreen(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, int question, bool yes) async {
  final choice = find.text(yes ? 'Yes' : 'No').at(question);
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Save answers');
  await tester.scrollUntilVisible(button, 200);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the stored answers and the moderate-effort note are shown', (
    tester,
  ) async {
    await _pump(tester, _Screening());
    expect(find.text('Update your health check.'), findsOneWidget);
    expect(
      find.text('Your plan will stay at moderate effort.'),
      findsOneWidget,
    );
    // The clearance question is there because of the known condition.
    expect(
      find.text('Has a health professional said you are fine to exercise?'),
      findsOneWidget,
    );
  });

  testWidgets('the athlete\'s own updated answers lift the cap', (
    tester,
  ) async {
    final repository = _Screening();
    await _pump(tester, repository);
    // Yes to "a professional said I am fine" is the athlete's own answer.
    final clearance = find.text('Yes').at(3);
    await tester.ensureVisible(clearance);
    await tester.pumpAndSettle();
    await tester.tap(clearance);
    await tester.pumpAndSettle();
    // Changing an answer clears the old outcome until it is saved again.
    expect(find.text('Your plan will stay at moderate effort.'), findsNothing);
    await _save(tester);
    expect(repository.recorded.single.clearedByProfessional, isTrue);
    expect(
      find.textContaining('Saved. Your answers set no limit'),
      findsOneWidget,
    );
    expect(find.text('Your plan will stay at moderate effort.'), findsNothing);
  });

  testWidgets('saving unchanged answers keeps the cap and says only Saved', (
    tester,
  ) async {
    final repository = _Screening();
    await _pump(tester, repository);
    await _save(tester);
    expect(repository.recorded.single, _moderateAnswers);
    expect(find.text('Saved.'), findsOneWidget);
    expect(
      find.text('Your plan will stay at moderate effort.'),
      findsOneWidget,
    );
  });

  testWidgets('a symptom answer asks for a professional first', (tester) async {
    final repository = _Screening();
    await _pump(tester, repository);
    await _answer(tester, 2, true);
    await _save(tester);
    expect(
      find.text('Please see a health professional first.'),
      findsOneWidget,
    );
    expect(find.textContaining('no limit'), findsNothing);
    // Nothing here tells the athlete they have a condition.
    expect(find.textContaining('diagnos'), findsOneWidget);
  });

  testWidgets('never screened starts empty and Save waits for every answer', (
    tester,
  ) async {
    final repository = _Screening(
      stored: const StoredScreening(
        outcome: ScreeningOutcome.cleared,
        answers: null,
      ),
    );
    await _pump(tester, repository);
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, 'Save answers'));
    expect(button().onPressed, isNull);
    await _answer(tester, 0, true);
    await _answer(tester, 1, false);
    expect(button().onPressed, isNull);
    await _answer(tester, 2, false);
    expect(button().onPressed, isNotNull);
    await _save(tester);
    expect(repository.recorded.single.knownCondition, isFalse);
  });

  testWidgets('a failed save says so and keeps the answers', (tester) async {
    final repository = _Screening()..failRecord = true;
    await _pump(tester, repository);
    await _answer(tester, 2, true);
    await _save(tester);
    expect(
      find.text(
        'Your answers were not saved. Check the connection and try again.',
      ),
      findsOneWidget,
    );
    repository.failRecord = false;
    await _save(tester);
    expect(
      find.text('Please see a health professional first.'),
      findsOneWidget,
    );
  });

  testWidgets('answers are locked while the server is recording them', (
    tester,
  ) async {
    final repository = _Screening()..recordDelay = Completer<void>();
    await _pump(tester, repository);
    final button = find.widgetWithText(FilledButton, 'Save answers');
    await tester.scrollUntilVisible(button, 200);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(find.text('Yes').at(2), warnIfMissed: false);
    await tester.pump();
    repository.recordDelay!.complete();
    await tester.pumpAndSettle();
    expect(repository.recorded.single, _moderateAnswers);
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('answers that fail to load offer a retry', (tester) async {
    final repository = _Screening(failLoads: 1);
    await _pump(tester, repository);
    expect(find.text('Your answers could not load'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Update your health check.'), findsOneWidget);
  });

  testWidgets('Account opens the health check', (tester) async {
    final repository = _Screening();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: AccountScreen(environment: _configured, screening: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Health check'), findsOneWidget);
    await tester.tap(find.text('Health check'));
    await tester.pumpAndSettle();
    expect(find.text('Update your health check.'), findsOneWidget);
  });

  testWidgets('Account without a backend has no health check row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const AccountScreen(
          environment: AppEnvironment(
            name: 'test',
            supabaseUrl: '',
            supabasePublishableKey: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Health check'), findsNothing);
  });
}
