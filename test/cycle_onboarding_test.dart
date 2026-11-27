import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/cycle/widgets/cycle_onboarding_block.dart';

import 'cycle_fakes.dart';

final _today = DateTime(2026, 11, 27, 9);

Future<void> _pump(
  WidgetTester tester,
  FakeCycle cycle, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CycleOnboardingBlock(repository: cycle, now: () => _today),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _yesAndAgree(WidgetTester tester) async {
  await tester.tap(find.text('Yes'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Agree'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agree'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks the optional question in the spec words', (tester) async {
    await _pump(tester, FakeCycle());
    expect(find.text('Your cycle'), findsOneWidget);
    expect(find.text('Take my menstrual cycle into account?'), findsOneWidget);
    expect(
      find.text(
        'Optional. It helps read your recovery, weight and energy fairly. '
        'You can change this any time in Account.',
      ),
      findsOneWidget,
    );
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('"Not now" asks nothing more and saves nothing', (tester) async {
    final cycle = FakeCycle();
    await _pump(tester, cycle);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Which fits you best?'), findsNothing);
    expect(
      find.text('You can turn on cycle tracking any time in Account.'),
      findsOneWidget,
    );
    expect(cycle.settings, isEmpty);
    expect(cycle.consentGrants, 0);
  });

  testWidgets('it shows nothing when she already has cycle settings', (
    tester,
  ) async {
    await _pump(tester, FakeCycle(answer: trackingAnswer()));
    expect(find.text('Your cycle'), findsNothing);
    await _pump(
      tester,
      FakeCycle(answer: const CycleAnswer(status: CycleStatus.regular)),
    );
    expect(find.text('Your cycle'), findsNothing);
  });

  testWidgets('it shows nothing when the cycle cannot be read', (tester) async {
    await _pump(tester, FakeCycle()..failLoads = true);
    expect(find.text('Your cycle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Yes asks for agreement; "Not now" there goes back to the '
      'question', (tester) async {
    final cycle = FakeCycle();
    await _pump(tester, cycle);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('Cycle data'), findsOneWidget);
    await tester.tap(find.text('Not now').last);
    await tester.pumpAndSettle();
    expect(cycle.consentGrants, 0);
    expect(find.text('Which fits you best?'), findsNothing);
    expect(find.text('Take my menstrual cycle into account?'), findsOneWidget);
  });

  testWidgets('the four ways her cycle works are offered', (tester) async {
    await _pump(tester, FakeCycle());
    await _yesAndAgree(tester);
    expect(find.text('Which fits you best?'), findsOneWidget);
    expect(find.text('Regular periods'), findsOneWidget);
    expect(
      find.text('Irregular or changing (for example perimenopause)'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Hormonal contraception (pill, implant, hormonal IUD, injection, ring '
        'or patch)',
      ),
      findsOneWidget,
    );
    expect(find.text('No periods at the moment'), findsOneWidget);
  });

  testWidgets('contraception is saved at once and asks nothing more', (
    tester,
  ) async {
    final cycle = FakeCycle();
    await _pump(tester, cycle);
    await _yesAndAgree(tester);
    await tester.tap(find.textContaining('Hormonal contraception'));
    await tester.pumpAndSettle();
    final saved = cycle.settings.single;
    expect(saved.tracking, isTrue);
    expect(saved.status, CycleStatus.hormonalContraception);
    expect(saved.typical, isNull);
    expect(find.text('When did your last period start?'), findsNothing);
    expect(
      find.text('Cycle tracking is on. You can change it any time in Account.'),
      findsOneWidget,
    );
    expect(cycle.days, isEmpty);
  });

  testWidgets('regular: the status is saved, then the date and the length', (
    tester,
  ) async {
    final cycle = FakeCycle();
    await _pump(tester, cycle);
    await _yesAndAgree(tester);
    await tester.tap(find.text('Regular periods'));
    await tester.pumpAndSettle();
    expect(cycle.settings.single.status, CycleStatus.regular);
    expect(find.text('When did your last period start?'), findsOneWidget);
    expect(find.text('How long is your cycle usually?'), findsOneWidget);
    expect(find.text('28 days'), findsOneWidget);

    await tester.tap(find.text('Choose a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Longer cycle'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(cycle.settings.last.typical, 29);
    final logged = cycle.days.single;
    expect(logged.date, DateTime(2026, 11, 27));
    expect(logged.flow, PeriodFlow.unspecified);
    expect(logged.cramps, isNull);
    expect(logged.isStart, isTrue);
    expect(
      find.text('Cycle tracking is on. You can change it any time in Account.'),
      findsOneWidget,
    );
  });

  testWidgets('"Not sure" on both saves no date and no length', (tester) async {
    final cycle = FakeCycle();
    await _pump(tester, cycle);
    await _yesAndAgree(tester);
    await tester.tap(
      find.text('Irregular or changing (for example perimenopause)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cycle-onboarding-date-unsure')),
    );
    await tester.tap(
      find.byKey(const ValueKey('cycle-onboarding-length-unsure')),
    );
    await tester.pumpAndSettle();
    expect(find.text('28 days'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(cycle.settings.last.status, CycleStatus.irregular);
    expect(cycle.settings.last.typical, isNull);
    expect(cycle.days, isEmpty);
  });

  testWidgets('a status that did not save says so and can be tried again', (
    tester,
  ) async {
    final cycle = FakeCycle();
    await _pump(tester, cycle);
    await _yesAndAgree(tester);
    cycle.failWrites = true;
    await tester.tap(find.text('Regular periods'));
    await tester.pumpAndSettle();
    expect(find.text('Not saved. Try again.'), findsOneWidget);
    expect(find.text('Which fits you best?'), findsOneWidget);
    cycle.failWrites = false;
    await tester.tap(find.text('Regular periods'));
    await tester.pumpAndSettle();
    expect(find.text('Not saved. Try again.'), findsNothing);
    expect(cycle.settings.single.status, CycleStatus.regular);
  });

  testWidgets('a refused agreement is not read as given', (tester) async {
    final cycle = FakeCycle()..failWrites = true;
    await _pump(tester, cycle);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Your choice was not saved. Check the connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Which fits you best?'), findsNothing);
  });

  testWidgets('it fits large text', (tester) async {
    await _pump(tester, FakeCycle(), textScale: 2);
    await _yesAndAgree(tester);
    await tester.tap(find.text('Regular periods'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
