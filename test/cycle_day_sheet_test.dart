import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/cycle/widgets/cycle_day_sheet.dart';

import 'cycle_fakes.dart';

final _today = DateTime(2026, 11, 27, 9);

CycleDay _day(
  DateTime date, {
  PeriodFlow? flow = PeriodFlow.medium,
  CycleCramps? cramps,
  bool isStart = false,
}) => CycleDay(
  date: date,
  flow: flow,
  cramps: cramps,
  isStart: isStart,
  source: CycleSource.manual,
);

CycleRecord _cycle(DateTime start, {int? length}) =>
    CycleRecord(startDate: start, lengthDays: length, used: length != null);

Future<void> _open(
  WidgetTester tester,
  FakeCycle cycle, {
  required DateTime date,
  bool startsPeriod = false,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCycleDaySheet(
              context,
              repository: cycle,
              date: date,
              answer: cycle.answer,
              startsPeriod: startsPeriod,
              canChangeDate: true,
              now: () => _today,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, String label) =>
    tester
        .getSemantics(find.bySemanticsLabel(label))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

bool _canSave(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
        .onPressed !=
    null;

const _notRead =
    'This day is older than the days shown here, so nothing is filled in. '
    'You are choosing what happened that day.';

Future<void> _pickDate(
  WidgetTester tester, {
  required int monthsBack, // negative goes forward
  required String day,
}) async {
  await tester.tap(find.byType(OutlinedButton));
  await tester.pumpAndSettle();
  for (var i = 0; i < monthsBack.abs(); i++) {
    await tester.tap(
      find.byTooltip(monthsBack > 0 ? 'Previous month' : 'Next month'),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(day).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  group('a day older than the answer lists', () {
    final start = DateTime(2026, 5, 4);

    FakeCycle answerWithOldCycle() => FakeCycle(
      answer: trackingAnswer(
        recentDays: [_day(DateTime(2026, 11, 10), isStart: true)],
        cycles: [_cycle(start, length: 28), _cycle(DateTime(2026, 11, 10))],
      ),
    );

    testWidgets('opens with nothing chosen and Save closed', (tester) async {
      final cycle = answerWithOldCycle();
      await _open(tester, cycle, date: start);
      expect(find.text(_notRead), findsOneWidget);
      for (final label in [
        'Bleeding: No period',
        'Bleeding: Spotting',
        'Bleeding: Light',
        'Bleeding: Medium',
        'Bleeding: Heavy',
        'Bleeding: Period, flow not noted',
      ]) {
        expect(_selected(tester, label), isFalse, reason: label);
      }
      expect(find.text('Cramps'), findsNothing);
      expect(_canSave(tester), isFalse);
      expect(cycle.days, isEmpty);
    });

    testWidgets('a start of a cycle presets the first-day switch once a '
        'flow is chosen', (tester) async {
      final cycle = answerWithOldCycle();
      await _open(tester, cycle, date: start);
      await tester.tap(find.bySemanticsLabel('Bleeding: Medium'));
      await tester.pumpAndSettle();
      expect(_canSave(tester), isTrue);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final logged = cycle.days.single;
      expect(logged.date, start);
      expect(logged.flow, PeriodFlow.medium);
      expect(logged.isStart, isTrue);
    });

    testWidgets('a date that is not a cycle start does not preset it', (
      tester,
    ) async {
      final cycle = answerWithOldCycle();
      await _open(tester, cycle, date: DateTime(2026, 5, 6));
      await tester.tap(find.bySemanticsLabel('Bleeding: Light'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    });

    testWidgets('"No period" can be chosen on purpose, and is then saved', (
      tester,
    ) async {
      final cycle = answerWithOldCycle();
      await _open(tester, cycle, date: start);
      await tester.tap(find.bySemanticsLabel('Bleeding: No period'));
      await tester.pumpAndSettle();
      expect(_canSave(tester), isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(cycle.days.single.flow, isNull);
      expect(cycle.days.single.isStart, isFalse);
    });

    testWidgets('a log-a-period sheet on an old date also waits for a choice', (
      tester,
    ) async {
      await _open(
        tester,
        answerWithOldCycle(),
        date: DateTime(2026, 4, 1),
        startsPeriod: true,
      );
      expect(_canSave(tester), isFalse);
    });
  });

  group('a first day needs a real level', () {
    // Never sent: a first day with no level is a guess the engine drops.
    void expectNeverUnspecifiedStart(FakeCycle cycle) {
      for (final day in cycle.days) {
        expect(
          day.flow == PeriodFlow.unspecified && day.isStart,
          isFalse,
          reason: '${day.flow} ${day.isStart}',
        );
      }
    }

    testWidgets('Log a period opens with Save closed until a level is chosen', (
      tester,
    ) async {
      final cycle = FakeCycle(answer: trackingAnswer());
      await _open(tester, cycle, date: _today, startsPeriod: true);
      // The switch shows once a bleeding level is chosen.
      expect(find.byType(SwitchListTile), findsNothing);
      expect(_canSave(tester), isFalse);

      await tester.tap(
        find.bySemanticsLabel('Bleeding: Period, flow not noted'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(_canSave(tester), isFalse);
      expect(
        find.text(
          'Choose Light, Medium or Heavy to mark the first day of a period.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsLabel('Bleeding: Light'));
      await tester.pumpAndSettle();
      expect(_canSave(tester), isTrue);
      expect(
        find.textContaining('Choose Light, Medium or Heavy'),
        findsNothing,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(cycle.days.single.flow, PeriodFlow.light);
      expect(cycle.days.single.isStart, isTrue);
      expectNeverUnspecifiedStart(cycle);
    });

    testWidgets('a level with no first day can be saved', (tester) async {
      final cycle = FakeCycle(answer: trackingAnswer());
      await _open(tester, cycle, date: _today, startsPeriod: true);
      await tester.tap(
        find.bySemanticsLabel('Bleeding: Period, flow not noted'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(_canSave(tester), isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(cycle.days.single.flow, PeriodFlow.unspecified);
      expect(cycle.days.single.isStart, isFalse);
    });

    testWidgets('spotting is never a start', (tester) async {
      final cycle = FakeCycle(answer: trackingAnswer());
      await _open(tester, cycle, date: _today, startsPeriod: true);
      await tester.tap(find.bySemanticsLabel('Bleeding: Spotting'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(cycle.days.single.flow, PeriodFlow.spotting);
      expect(cycle.days.single.isStart, isFalse);
    });

    testWidgets('the onboarding guess opens closed until she picks a level '
        'or turns the start off', (tester) async {
      final cycle = FakeCycle(
        answer: trackingAnswer(
          recentDays: [
            _day(
              DateTime(2026, 11, 20),
              flow: PeriodFlow.unspecified,
              isStart: true,
            ),
          ],
        ),
      );
      await _open(tester, cycle, date: DateTime(2026, 11, 20));
      expect(_canSave(tester), isFalse);
      await tester.tap(find.bySemanticsLabel('Bleeding: Medium'));
      await tester.pumpAndSettle();
      expect(_canSave(tester), isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(cycle.days.single.flow, PeriodFlow.medium);
      expect(cycle.days.single.isStart, isTrue);
      expectNeverUnspecifiedStart(cycle);
    });
  });

  group('a day inside the days the answer lists', () {
    testWidgets('opens with what is stored', (tester) async {
      final cycle = FakeCycle(
        answer: trackingAnswer(
          recentDays: [
            _day(
              DateTime(2026, 11, 20),
              flow: PeriodFlow.heavy,
              cramps: CycleCramps.strong,
              isStart: true,
            ),
          ],
        ),
      );
      await _open(tester, cycle, date: DateTime(2026, 11, 20));
      expect(find.text(_notRead), findsNothing);
      expect(_selected(tester, 'Bleeding: Heavy'), isTrue);
      expect(_selected(tester, 'Cramps: Strong'), isTrue);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(_canSave(tester), isTrue);
    });

    testWidgets('a start of a cycle the day was not flagged as is a start', (
      tester,
    ) async {
      final cycle = FakeCycle(
        answer: trackingAnswer(
          recentDays: [_day(DateTime(2026, 11, 10))],
          cycles: [_cycle(DateTime(2026, 11, 10))],
        ),
      );
      await _open(tester, cycle, date: DateTime(2026, 11, 10));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });

    testWidgets('a day with nothing logged opens as no period', (tester) async {
      await _open(
        tester,
        FakeCycle(answer: trackingAnswer()),
        date: DateTime(2026, 11, 20),
      );
      expect(find.text(_notRead), findsNothing);
      expect(_selected(tester, 'Bleeding: No period'), isTrue);
      expect(_canSave(tester), isTrue);
    });
  });

  testWidgets('changing the date reloads the fields and never carries the '
      'old day over', (tester) async {
    final stored = DateTime(2026, 11, 27);
    final cycle = FakeCycle(
      answer: trackingAnswer(
        recentDays: [
          _day(
            stored,
            flow: PeriodFlow.heavy,
            cramps: CycleCramps.strong,
            isStart: true,
          ),
        ],
      ),
    );
    await _open(tester, cycle, date: stored);
    expect(_selected(tester, 'Bleeding: Heavy'), isTrue);
    expect(_selected(tester, 'Cramps: Strong'), isTrue);

    // A day inside the listed days with nothing logged: no period, no cramps,
    // no start.
    await _pickDate(tester, monthsBack: 0, day: '20');
    expect(_selected(tester, 'Bleeding: Heavy'), isFalse);
    expect(_selected(tester, 'Bleeding: No period'), isTrue);
    expect(find.text('Cramps'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    // A day older than the listed days: nothing chosen, Save closed.
    await _pickDate(tester, monthsBack: 3, day: '15');
    expect(find.text(_notRead), findsOneWidget);
    expect(_selected(tester, 'Bleeding: No period'), isFalse);
    expect(_selected(tester, 'Bleeding: Heavy'), isFalse);
    expect(_canSave(tester), isFalse);

    // Back to the stored day: what is stored is read again.
    await _pickDate(tester, monthsBack: -3, day: '27');
    expect(find.text(_notRead), findsNothing);
    expect(_selected(tester, 'Bleeding: Heavy'), isTrue);
    expect(_selected(tester, 'Cramps: Strong'), isTrue);
    expect(_canSave(tester), isTrue);
  });
}
