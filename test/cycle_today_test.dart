import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';
import 'package:tracend/features/progress/progress_repository.dart';
import 'package:tracend/features/progress/progress_screen.dart';
import 'package:tracend/features/progress/widgets/weight_trend_card.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/today/computed_metrics.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/features/today/widgets/recovery_readout_card.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/local_health_store.dart';
import 'package:tracend/shared/plan_changes.dart';

import 'cycle_fakes.dart';

const _offline = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

final _clock = DateTime(2026, 11, 27, 9);

class _HeldBrief implements DailyBriefRepository {
  final request = Completer<void>();

  @override
  Future<DailyBrief> load(DateTime date) async {
    await request.future;
    return DailyBrief(localDate: '2026-11-27');
  }
}

CycleAnswer _secondHalf() => trackingAnswer(
  state: CycleState(
    cycleDay: 18,
    phase: CyclePhase.secondHalf,
    confidence: CycleConfidence.medium,
    expectedFrom: DateTime(2026, 12, 8),
    expectedTo: DateTime(2026, 12, 12),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  CycleRepository cycle = const FixtureCycleRepository(),
  DailyBriefRepository brief = const FixtureDailyBriefRepository(),
  CycleChanges? changes,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: TodayScreen(
        environment: _offline,
        brief: brief,
        cycle: cycle,
        cycleChanges: changes,
        queueFactory: () => CheckInQueue(const LocalHealthStore()),
        clock: () => _clock,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Progress extends FixtureProgressRepository {
  @override
  Future<List<BodyMeasurement>> loadMeasurements() async => [
    BodyMeasurement(date: DateTime(2026, 11, 1), weightKg: 62),
    BodyMeasurement(date: DateTime(2026, 11, 20), weightKg: 62.6),
  ];
}

void main() {
  setUp(() {
    resetLoadFailures();
    addTearDown(resetLoadFailures);
  });

  group('Today', () {
    testWidgets('with tracking off Today shows no cycle line', (tester) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('cycle-line')), findsNothing);
      expect(find.textContaining('Cycle day'), findsNothing);
      expect(find.byKey(const ValueKey('cycle-long-gap')), findsNothing);
    });

    testWidgets('shows the cycle day and the expected range', (tester) async {
      await _pump(tester, cycle: FakeCycle(answer: _secondHalf()));
      expect(
        find.text('Cycle day 18 · period expected 8–12 Dec'),
        findsOneWidget,
      );
    });

    testWidgets('a cycle that cannot be read hides the line and reports no '
        'failure', (tester) async {
      final cycle = FakeCycle(answer: _secondHalf())..failLoads = true;
      await _pump(tester, cycle: cycle);
      expect(find.textContaining('Cycle day'), findsNothing);
      expect(loadFailuresInARow('Today: daily brief'), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cycle is read after the brief, not with it', (
      tester,
    ) async {
      final brief = _HeldBrief();
      final cycle = FakeCycle(answer: _secondHalf());
      await _pump(tester, cycle: cycle, brief: brief);
      // The skeleton shows; the cycle has not been asked for.
      expect(cycle.loads, 0);
      brief.request.complete();
      await tester.pumpAndSettle();
      expect(cycle.loads, 1);
      expect(find.textContaining('Cycle day 18'), findsOneWidget);
    });

    testWidgets('a change announced from Account is read again', (
      tester,
    ) async {
      final cycle = FakeCycle(answer: _secondHalf());
      final changes = CycleChanges();
      await _pump(tester, cycle: cycle, changes: changes);
      cycle.answer = trackingAnswer(state: const CycleState(periodDay: 2));
      changes.announce();
      await tester.pumpAndSettle();
      expect(find.text('Period day 2'), findsOneWidget);
      expect(find.textContaining('Cycle day'), findsNothing);
    });

    testWidgets('turning tracking off hides the line', (tester) async {
      final cycle = FakeCycle(answer: _secondHalf());
      final changes = CycleChanges();
      await _pump(tester, cycle: cycle, changes: changes);
      cycle.answer = CycleAnswer.off;
      changes.announce();
      await tester.pumpAndSettle();
      expect(find.textContaining('Cycle day'), findsNothing);
    });

    testWidgets('a long gap shows the card, and "Log a period" logs a start', (
      tester,
    ) async {
      final cycle = FakeCycle(
        answer: trackingAnswer(state: const CycleState(noPeriodLong: true)),
      );
      await _pump(tester, cycle: cycle);
      expect(
        find.text(
          "No period logged for 3 months. If that's not expected for you, "
          "it's worth talking to a doctor.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Log a period'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final logged = cycle.days.single;
      expect(logged.date, DateTime(2026, 11, 27));
      expect(logged.flow, PeriodFlow.unspecified);
      expect(logged.isStart, isTrue);
    });

    testWidgets('"Update my cycle status" saves the new status', (
      tester,
    ) async {
      final cycle = FakeCycle(
        answer: trackingAnswer(state: const CycleState(noPeriodLong: true)),
      );
      await _pump(tester, cycle: cycle);
      await tester.tap(find.text('Update my cycle status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No periods at the moment'));
      await tester.pumpAndSettle();
      final saved = cycle.settings.single;
      expect(saved.status, CycleStatus.noPeriods);
      expect(saved.tracking, isTrue);
      expect(saved.typical, 28);
    });

    testWidgets('the check-in asks "Period today?" only when she tracks', (
      tester,
    ) async {
      await _pump(tester, cycle: FakeCycle(answer: _secondHalf()));
      await tester.tap(find.text('Checked in'));
      await tester.pumpAndSettle();
      expect(find.text('Period today?'), findsOneWidget);
    });

    testWidgets('a period saved in the check-in updates the line at once', (
      tester,
    ) async {
      final cycle = FakeCycle(answer: _secondHalf());
      await _pump(tester, cycle: cycle);
      await tester.tap(find.text('Checked in'));
      await tester.pumpAndSettle();
      for (final label in ['Period today?: Yes', 'Flow: Light']) {
        final option = find.bySemanticsLabel(label);
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        await tester.tap(option);
        await tester.pumpAndSettle();
      }
      expect(cycle.days.single.flow, PeriodFlow.light);
    });

    testWidgets('the check-in does not ask when she does not track', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Checked in'));
      await tester.pumpAndSettle();
      expect(find.text('Period today?'), findsNothing);
      expect(find.text('Daily check-in'), findsOneWidget);
    });

    testWidgets('the long-gap card is not shown for someone not tracking', (
      tester,
    ) async {
      await _pump(
        tester,
        cycle: FakeCycle(
          answer: const CycleAnswer(
            state: CycleState(noPeriodLong: true),
            status: CycleStatus.regular,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('cycle-long-gap')), findsNothing);
    });
  });

  group('the recovery drivers card', () {
    ComputedMetrics metrics() => const ComputedMetrics(
      scores: ComputedScores(
        recovery: 72,
        recoveryBreakdown: RecoveryBreakdown(
          hrvZ: -1.2,
          rhrZ: -1.1,
          sleepZ: 0.8,
          respRateZ: 0.1,
          prevStrainZ: -0.3,
        ),
      ),
      baselines: ComputedBaselines(),
      dataConfidence: 'medium',
    );

    Future<void> show(WidgetTester tester, {String? note}) => tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecoveryReadoutCard(computed: metrics(), note: note),
          ),
        ),
      ),
    );

    testWidgets('says the shift is expected, and changes no driver', (
      tester,
    ) async {
      await show(tester, note: 'A note about the cycle.');
      expect(find.text('A note about the cycle.'), findsOneWidget);
      expect(find.textContaining('Heart rate variability'), findsOneWidget);
    });

    testWidgets('without a note it is as it was', (tester) async {
      await show(tester);
      expect(find.byKey(const ValueKey('cycle-recovery-note')), findsNothing);
    });
  });

  group('the weight trend', () {
    final weighIns = [
      BodyMeasurement(date: DateTime(2026, 11, 1), weightKg: 62),
      BodyMeasurement(date: DateTime(2026, 11, 20), weightKg: 62.6),
    ];

    testWidgets('the card carries the water note when given one', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeightHeroCard(
                measurements: weighIns,
                periodMeasurements: weighIns,
                onRecord: () {},
                now: DateTime(2026, 11, 27),
                cycleNote: 'Weight often runs higher around a period (water).',
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('cycle-weight-note')), findsOneWidget);
      expect(find.text('62.6 kg'), findsWidgets);
    });

    Future<void> progress(WidgetTester tester, CycleRepository cycle) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: ProgressScreen(
              repository: _Progress(),
              cycle: cycle,
              now: () => DateTime(2026, 11, 27),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Progress shows the note in the water window', (tester) async {
      await progress(
        tester,
        FakeCycle(
          answer: trackingAnswer(
            state: const CycleState(weightWaterWindow: true),
          ),
        ),
      );
      expect(
        find.text(
          'Weight often runs higher around a period (water). Compare with the '
          'same point last cycle.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('outside the window, with tracking off, or when the cycle '
        'cannot be read there is no note', (tester) async {
      for (final cycle in <CycleRepository>[
        FakeCycle(answer: trackingAnswer()),
        const FixtureCycleRepository(),
        FakeCycle(
          answer: trackingAnswer(
            state: const CycleState(weightWaterWindow: true),
          ),
        )..failLoads = true,
      ]) {
        await progress(tester, cycle);
        expect(find.byKey(const ValueKey('cycle-weight-note')), findsNothing);
        expect(find.text('62.6 kg'), findsWidgets);
      }
    });
  });
}
