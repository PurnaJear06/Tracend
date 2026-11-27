import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/cycle/widgets/period_today_control.dart';
import 'package:tracend/features/today/check_in_sheet.dart';

import 'cycle_fakes.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

final _day = DateTime(2026, 11, 27);

class _Sent {
  final payloads = <Map<String, dynamic>>[];

  Future<bool> send(
    String localDate,
    String timezone,
    String key,
    Map<String, dynamic> payload,
  ) async {
    payloads.add(payload);
    return true;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Sent sent, {
  CheckInPeriod? period,
  void Function(CheckInSaved?)? onSaved,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                final saved = await showCheckInSheet(
                  context,
                  _environment,
                  sender: sent.send,
                  localDate: '2026-11-27',
                  period: period,
                );
                onSaved?.call(saved);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final option = find.bySemanticsLabel(label);
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

CheckInPeriod _period(
  FakeCycle cycle, {
  void Function(CycleAnswer)? onChanged,
}) => CheckInPeriod(
  repository: cycle,
  answer: cycle.answer,
  onChanged: onChanged,
);

void main() {
  test('only an athlete with periods to log is asked', () {
    expect(asksAboutPeriod(CycleAnswer.off), isFalse);
    expect(asksAboutPeriod(trackingAnswer()), isTrue);
    expect(
      asksAboutPeriod(trackingAnswer(status: CycleStatus.irregular)),
      isTrue,
    );
    expect(
      asksAboutPeriod(
        trackingAnswer(status: CycleStatus.hormonalContraception),
      ),
      isTrue,
    );
    expect(
      asksAboutPeriod(trackingAnswer(status: CycleStatus.noPeriods)),
      isFalse,
    );
    expect(
      asksAboutPeriod(const CycleAnswer(status: CycleStatus.regular)),
      isFalse,
    );
  });

  testWidgets('without a period control the check-in is as it was', (
    tester,
  ) async {
    await _open(tester, _Sent());
    expect(find.text('Period today?'), findsNothing);
    expect(find.text('For period cramps, use Period below.'), findsNothing);
  });

  testWidgets('with one, the pain question points to it', (tester) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    await _open(tester, _Sent(), period: _period(cycle));
    expect(find.text('Period today?'), findsOneWidget);
    expect(find.text('For period cramps, use Period below.'), findsOneWidget);
  });

  testWidgets('"No" is saved on tap as a day with no bleeding', (tester) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    final changes = <CycleAnswer>[];
    await _open(
      tester,
      _Sent(),
      period: _period(cycle, onChanged: changes.add),
    );
    await _tap(tester, 'Period today?: No');
    final logged = cycle.days.single;
    expect(logged.date, _day);
    expect(logged.flow, isNull);
    expect(logged.cramps, isNull);
    expect(find.text('Saved'), findsOneWidget);
    expect(changes, hasLength(1));
  });

  testWidgets('"Yes" saves when the flow is chosen, and again for cramps', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    await _open(tester, _Sent(), period: _period(cycle));
    await _tap(tester, 'Period today?: Yes');
    expect(cycle.days, isEmpty);
    expect(find.text('Choose how heavy it is to save it.'), findsOneWidget);
    expect(find.text('Cramps'), findsNothing);

    await _tap(tester, 'Flow: Medium');
    expect(cycle.days.single.flow, PeriodFlow.medium);
    expect(cycle.days.single.cramps, isNull);
    expect(find.text('Saved'), findsOneWidget);

    await _tap(tester, 'Cramps: Strong');
    expect(cycle.days.last.flow, PeriodFlow.medium);
    expect(cycle.days.last.cramps, CycleCramps.strong);
    // The flow choices are the four the spec names; "unspecified" is not one.
    expect(find.bySemanticsLabel('Flow: Spotting'), findsOneWidget);
    expect(find.bySemanticsLabel('Flow: Light'), findsOneWidget);
    expect(find.bySemanticsLabel('Flow: Heavy'), findsOneWidget);
  });

  testWidgets("today's stored day fills the control", (tester) async {
    final cycle = FakeCycle(
      answer: trackingAnswer(
        recentDays: [
          CycleDay(
            date: _day,
            flow: PeriodFlow.heavy,
            cramps: CycleCramps.mild,
            isStart: true,
            source: CycleSource.manual,
          ),
        ],
      ),
    );
    await _open(tester, _Sent(), period: _period(cycle));
    expect(find.text('Cramps'), findsOneWidget);
    // A day she logged as a start stays a start when its flow is changed.
    await _tap(tester, 'Flow: Light');
    expect(cycle.days.single.isStart, isTrue);
    expect(cycle.days.single.cramps, CycleCramps.mild);
  });

  testWidgets('a tap that did not save says so and shows what is stored', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer())..failWrites = true;
    await _open(tester, _Sent(), period: _period(cycle));
    await _tap(tester, 'Period today?: No');
    expect(find.text('Not saved. Try again.'), findsOneWidget);
    expect(find.bySemanticsLabel('Period today?: No'), findsOneWidget);
    cycle.failWrites = false;
    await _tap(tester, 'Period today?: No');
    expect(find.text('Saved'), findsOneWidget);
    expect(cycle.days, hasLength(1));
  });

  testWidgets('the period is not part of the check-in payload or its guard', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    final sent = _Sent();
    CheckInSaved? result;
    await _open(
      tester,
      sent,
      period: _period(cycle),
      onSaved: (saved) => result = saved,
    );
    await _tap(tester, 'Period today?: Yes');
    await _tap(tester, 'Flow: Light');
    expect(cycle.days, hasLength(1));

    // Closing the sheet after only the period answer asks nothing: it was
    // saved on its own and the check-in has no unsaved input.
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save check-in'));
    await tester.pumpAndSettle();
    expect(sent.payloads, hasLength(1));
    final keys = sent.payloads.single.keys.join(',');
    expect(keys, isNot(contains('period')));
    expect(keys, isNot(contains('flow')));
    expect(keys, isNot(contains('cramp')));
    expect(keys, isNot(contains('cycle')));
    expect(result?.delivered, isTrue);
    expect(cycle.days, hasLength(1));
  });

  testWidgets('a save that finishes after the sheet closed is still kept', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    final changes = <CycleAnswer>[];
    await _open(
      tester,
      _Sent(),
      period: _period(cycle, onChanged: changes.add),
    );
    await _tap(tester, 'Period today?: No');
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
