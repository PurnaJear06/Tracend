import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/widgets/cycle_settings.dart';
import 'package:tracend/features/cycle/cycle_health.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/shared/plan_changes.dart';

import 'cycle_fakes.dart';

final _today = DateTime(2026, 11, 27, 9);

Future<void> _pump(
  WidgetTester tester,
  FakeCycle cycle, {
  CycleHealthSync? health,
  CycleChanges? changes,
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
      home: CycleSettingsScreen(
        repository: cycle,
        health: health,
        changes: changes,
        now: () => _today,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Switch _switch(WidgetTester tester, int index) =>
    tester.widget<Switch>(find.byType(Switch).at(index));

void main() {
  testWidgets('with tracking off there is one switch and nothing else', (
    tester,
  ) async {
    await _pump(tester, FakeCycle());
    expect(find.text('Track my cycle'), findsOneWidget);
    expect(_switch(tester, 0).value, isFalse);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Recent cycles'), findsNothing);
    expect(find.text('Delete my cycle data'), findsNothing);
  });

  testWidgets('turning it on asks for agreement, then how her cycle works, '
      'then saves', (tester) async {
    final cycle = FakeCycle();
    final changes = CycleChanges();
    var announced = 0;
    changes.addListener(() => announced++);
    await _pump(tester, cycle, changes: changes);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Cycle data'), findsOneWidget);
    expect(
      find.textContaining('Tracend stores your cycle answers'),
      findsOneWidget,
    );
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    expect(cycle.consentGrants, 1);

    expect(find.text('Which fits you best?'), findsOneWidget);
    await tester.tap(find.text('Regular periods'));
    await tester.pumpAndSettle();

    expect(cycle.settings.single.tracking, isTrue);
    expect(cycle.settings.single.status, CycleStatus.regular);
    expect(cycle.settings.single.apple, isFalse);
    expect(_switch(tester, 0).value, isTrue);
    expect(announced, 1);
  });

  testWidgets('a double tap opens one agreement sheet', (tester) async {
    await _pump(tester, FakeCycle());
    await tester.tap(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Cycle data'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Cycle data'), findsNothing);
  });

  testWidgets('an off answer that kept her status asks for the agreement '
      'again', (tester) async {
    final cycle = FakeCycle(answer: fixtureAnswer('my_cycle_v1_0_off.json'));
    cycle.answer = const CycleAnswer(
      status: CycleStatus.regular,
      typicalCycleDays: 28,
    );
    await _pump(tester, cycle);
    expect(_switch(tester, 0).value, isFalse);
    expect(find.text('Typical cycle length'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Cycle data'), findsOneWidget);
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    expect(cycle.consentGrants, 1);
    expect(cycle.settings.single.status, CycleStatus.regular);
    expect(cycle.settings.single.tracking, isTrue);
  });

  testWidgets('"Not now" on the agreement turns nothing on', (tester) async {
    final cycle = FakeCycle();
    await _pump(tester, cycle);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(cycle.consentGrants, 0);
    expect(cycle.settings, isEmpty);
    expect(_switch(tester, 0).value, isFalse);
  });

  testWidgets('an agreement already given is not asked for again', (
    tester,
  ) async {
    final cycle = FakeCycle(consent: true);
    await _pump(tester, cycle);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Cycle data'), findsNothing);
    expect(find.text('Which fits you best?'), findsOneWidget);
  });

  testWidgets('a status saved earlier is reused when tracking is turned on '
      'again', (tester) async {
    final cycle = FakeCycle(
      consent: true,
      answer: const CycleAnswer(status: CycleStatus.irregular),
    );
    await _pump(tester, cycle);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Which fits you best?'), findsNothing);
    expect(cycle.settings.single.status, CycleStatus.irregular);
    expect(cycle.settings.single.tracking, isTrue);
  });

  testWidgets('turning it off keeps the logs and switches Apple Health off', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer(apple: true));
    await _pump(tester, cycle);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    final saved = cycle.settings.single;
    expect(saved.tracking, isFalse);
    expect(saved.apple, isFalse);
    expect(saved.status, CycleStatus.regular);
    expect(cycle.deletions, 0);
  });

  testWidgets('tracking on shows its rows, and the length can be changed', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    await _pump(tester, cycle);
    expect(find.text('Regular periods'), findsOneWidget);
    expect(find.text('28 days'), findsOneWidget);

    await tester.tap(find.text('Typical cycle length'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Longer cycle'));
    await tester.pump();
    await tester.tap(find.byTooltip('Longer cycle'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(cycle.settings.single.typical, 30);
    expect(find.text('30 days'), findsOneWidget);

    await tester.tap(find.text('Typical cycle length'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not sure'));
    await tester.pumpAndSettle();
    expect(cycle.settings.last.typical, isNull);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('no periods and contraception have no cycle length', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeCycle(answer: trackingAnswer(status: CycleStatus.noPeriods)),
    );
    expect(find.text('Typical cycle length'), findsNothing);
  });

  testWidgets('the cycle type can be changed', (tester) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    await _pump(tester, cycle);
    await tester.tap(find.text('Cycle'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Hormonal contraception'));
    await tester.pumpAndSettle();
    expect(cycle.settings.single.status, CycleStatus.hormonalContraception);
    expect(cycle.settings.single.tracking, isTrue);
  });

  testWidgets('recent cycles list the starts, and a start can be changed', (
    tester,
  ) async {
    final cycle = FakeCycle(
      answer: trackingAnswer(
        recentDays: [
          CycleDay(
            date: DateTime(2026, 11, 10),
            flow: PeriodFlow.medium,
            cramps: CycleCramps.mild,
            isStart: true,
            source: CycleSource.manual,
          ),
        ],
        cycles: [
          CycleRecord(
            startDate: DateTime(2026, 10, 13),
            lengthDays: 28,
            used: true,
          ),
          CycleRecord(
            startDate: DateTime(2026, 11, 10),
            lengthDays: null,
            used: false,
          ),
        ],
      ),
    );
    await _pump(tester, cycle);
    expect(find.text('Recent cycles'), findsOneWidget);
    expect(find.text('Started 13 Oct'), findsOneWidget);
    expect(find.text('Current cycle'), findsOneWidget);

    await tester.tap(find.text('Started 10 Nov'));
    await tester.pumpAndSettle();
    // The stored day fills the sheet; "No period" removes the day.
    await tester.tap(find.text('No period'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final logged = cycle.days.single;
    expect(logged.date, DateTime(2026, 11, 10));
    expect(logged.flow, isNull);
    expect(logged.cramps, isNull);
    expect(logged.isStart, isFalse);
  });

  testWidgets('an older cycle opens without changing the day it never read', (
    tester,
  ) async {
    final cycle = FakeCycle(
      answer: trackingAnswer(
        cycles: [
          CycleRecord(
            startDate: DateTime(2026, 5, 4),
            lengthDays: 28,
            used: true,
          ),
        ],
      ),
    );
    await _pump(tester, cycle);
    await tester.tap(find.text('Started 4 May'));
    await tester.pumpAndSettle();
    expect(find.textContaining('older than the days shown here'), findsOne);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(cycle.days, isEmpty);
  });

  group('Apple Health', () {
    testWidgets('is not offered without a reader', (tester) async {
      await _pump(tester, FakeCycle(answer: trackingAnswer()));
      expect(find.text('Read periods from Apple Health'), findsNothing);
    });

    testWidgets(
      'turning it on asks Apple, switches it on, then reads 180 days',
      (tester) async {
        final cycle = FakeCycle(answer: trackingAnswer());
        final reader = FakeCycleHealthReader();
        await _pump(
          tester,
          cycle,
          health: CycleHealthSync(
            repository: cycle,
            reader: reader,
            now: () => _today,
          ),
        );
        await tester.tap(find.byType(Switch).at(1));
        await tester.pumpAndSettle();
        expect(reader.requests, 1);
        expect(cycle.settings.single.apple, isTrue);
        expect(cycle.imports, hasLength(1));
        expect(_switch(tester, 1).value, isTrue);
      },
    );

    testWidgets('the switch is saved before iOS is asked', (tester) async {
      final cycle = FakeCycle(answer: trackingAnswer());
      final reader = _OrderReader(cycle);
      await _pump(
        tester,
        cycle,
        health: CycleHealthSync(repository: cycle, reader: reader),
      );
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(reader.savedWhenAsked, [true]);
    });

    testWidgets('a refused save never shows the permission sheet', (
      tester,
    ) async {
      final cycle = FakeCycle(answer: trackingAnswer())..failWrites = true;
      final reader = FakeCycleHealthReader();
      await _pump(
        tester,
        cycle,
        health: CycleHealthSync(repository: cycle, reader: reader),
      );
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(reader.requests, 0);
      expect(reader.reads, isEmpty);
      expect(_switch(tester, 1).value, isFalse);
      expect(
        find.text('Periods could not be read from Apple Health. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('Apple Health that cannot be asked leaves it off', (
      tester,
    ) async {
      final cycle = FakeCycle(answer: trackingAnswer());
      await _pump(
        tester,
        cycle,
        health: CycleHealthSync(
          repository: cycle,
          reader: FakeCycleHealthReader(canAsk: false),
        ),
      );
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(cycle.settings.map((s) => s.apple), [true, false]);
      expect(cycle.imports, isEmpty);
      expect(find.text('Apple Health could not be opened.'), findsOneWidget);
      expect(_switch(tester, 1).value, isFalse);
    });

    testWidgets('a failed first read turns the switch back off', (
      tester,
    ) async {
      final cycle = FakeCycle(answer: trackingAnswer());
      final reader = FakeCycleHealthReader()..failReads = true;
      await _pump(
        tester,
        cycle,
        health: CycleHealthSync(repository: cycle, reader: reader),
      );
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(cycle.settings.map((s) => s.apple), [true, false]);
      expect(_switch(tester, 1).value, isFalse);
      expect(
        find.text('Periods could not be read from Apple Health. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('turning it off saves it off', (tester) async {
      final cycle = FakeCycle(answer: trackingAnswer(apple: true));
      await _pump(
        tester,
        cycle,
        health: CycleHealthSync(
          repository: cycle,
          reader: FakeCycleHealthReader(),
        ),
      );
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(cycle.settings.single.apple, isFalse);
      expect(cycle.imports, isEmpty);
    });
  });

  testWidgets('deleting asks first, then clears everything', (tester) async {
    final cycle = FakeCycle(answer: trackingAnswer());
    final changes = CycleChanges();
    var announced = 0;
    changes.addListener(() => announced++);
    await _pump(tester, cycle, changes: changes);

    await tester.scrollUntilVisible(
      find.text('Delete my cycle data'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete my cycle data'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "This removes every period day and cycle answer. It can't be undone.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cycle.deletions, 0);

    await tester.tap(find.text('Delete my cycle data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(cycle.deletions, 1);
    expect(announced, 1);
    expect(_switch(tester, 0).value, isFalse);
    expect(find.text('Delete my cycle data'), findsNothing);
  });

  testWidgets('a failed change says so and leaves the screen as it was', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer())..failWrites = true;
    await _pump(tester, cycle);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Not saved. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(_switch(tester, 0).value, isTrue);
  });

  testWidgets('a refusal is worded and its code is never shown', (
    tester,
  ) async {
    final cycle = FakeCycle(answer: trackingAnswer())
      ..failWrites = true
      ..writeError = const CycleRefused(CycleRefusal.trackingOff);
    await _pump(tester, cycle);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Cycle tracking is off. Turn it on in Account to log periods.'),
      findsOneWidget,
    );
    expect(find.textContaining('cycle_tracking_off'), findsNothing);
  });

  testWidgets('an answer that cannot be read offers a retry', (tester) async {
    final cycle = FakeCycle()..failLoads = true;
    await _pump(tester, cycle);
    expect(find.text('Your cycle settings could not load'), findsOneWidget);
    cycle.failLoads = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Track my cycle'), findsOneWidget);
  });

  testWidgets('it fits large text on a narrow phone', (tester) async {
    await _pump(tester, FakeCycle(answer: trackingAnswer()), textScale: 2);
    expect(tester.takeException(), isNull);
  });

  group('the Account row', () {
    Future<void> openAccount(WidgetTester tester, CycleRepository cycle) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: AccountScreen(
            environment: const AppEnvironment(
              name: 'test',
              supabaseUrl: '',
              supabasePublishableKey: '',
            ),
            cycle: cycle,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Cycle tracking'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is there for everyone and says it is off', (tester) async {
      await openAccount(tester, const FixtureCycleRepository());
      expect(find.text('Cycle tracking'), findsOneWidget);
      expect(
        find.text('Off · optional, for periods and your cycle'),
        findsOneWidget,
      );
    });

    testWidgets('says what is on, and opens the screen', (tester) async {
      await openAccount(tester, FakeCycle(answer: trackingAnswer()));
      expect(find.text('On · Regular periods'), findsOneWidget);
      await tester.tap(find.text('Cycle tracking'));
      await tester.pumpAndSettle();
      expect(find.text('Track my cycle'), findsOneWidget);
    });

    testWidgets('an unreadable answer is said, not hidden', (tester) async {
      await openAccount(tester, FakeCycle()..failLoads = true);
      expect(
        find.text('Could not be read · open to try again'),
        findsOneWidget,
      );
    });
  });
}

/// Records whether the cycle switch was already saved when iOS was asked.
class _OrderReader extends FakeCycleHealthReader {
  _OrderReader(this.cycle);

  final FakeCycle cycle;
  final savedWhenAsked = <bool>[];

  @override
  Future<bool> requestAccess() {
    savedWhenAsked.add(cycle.settings.isNotEmpty && cycle.settings.last.apple);
    return super.requestAccess();
  }
}
