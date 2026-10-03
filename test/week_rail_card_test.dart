import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/widgets/week_rail_card.dart';

import 'widgets/haptics_recorder.dart';
import 'widgets/widget_host.dart';

void main() {
  final monday = DateTime(2026, 9, 28);
  final today = DateTime(2026, 10, 2);

  DayBoxStatus status(DateTime date) => switch (date.day) {
    29 || 30 => DayBoxStatus.done,
    2 || 4 => DayBoxStatus.planned,
    _ => DayBoxStatus.rest,
  };

  Widget strip({
    DateTime? selected,
    ValueChanged<DateTime>? onSelected,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
  }) => widgetHost(
    DayBoxesStrip(
      weekStart: monday,
      selectedDate: selected ?? today,
      today: today,
      statusFor: status,
      workoutNameFor: (date) =>
          status(date) == DayBoxStatus.rest ? null : 'Upper body A',
      onSelected: onSelected ?? (_) {},
      onPreviousWeek: onPrevious,
      onNextWeek: onNext,
    ),
  );

  group('DayBoxesStrip', () {
    testWidgets('shows seven days of the week with their numbers', (
      tester,
    ) async {
      await tester.pumpWidget(strip());
      for (var day = 28; day <= 30; day++) {
        expect(find.byKey(ValueKey('day-box-2026-09-$day')), findsOneWidget);
      }
      for (var day = 1; day <= 4; day++) {
        expect(find.byKey(ValueKey('day-box-2026-10-0$day')), findsOneWidget);
      }
      expect(find.text('M'), findsOneWidget);
      expect(find.text('S'), findsNWidgets(2));
    });

    testWidgets('a tap selects the day with the selection haptic', (
      tester,
    ) async {
      final haptics = recordHaptics(tester);
      DateTime? picked;
      await tester.pumpWidget(strip(onSelected: (date) => picked = date));
      await tester.tap(find.byKey(const ValueKey('day-box-2026-09-30')));
      expect(picked, DateTime(2026, 9, 30));
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('tapping the selected day does nothing', (tester) async {
      final haptics = recordHaptics(tester);
      DateTime? picked;
      await tester.pumpWidget(strip(onSelected: (date) => picked = date));
      await tester.tap(find.byKey(const ValueKey('day-box-2026-10-02')));
      expect(picked, isNull);
      expect(haptics, isEmpty);
    });

    testWidgets('VoiceOver hears the day, the workout, its state and today', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(strip());
      expect(
        find.bySemanticsLabel('Friday 2 October, Upper body A, planned, today'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Tuesday 29 September, Upper body A, done'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Thursday 1 October, rest day'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a swipe pages the week only where a callback exists', (
      tester,
    ) async {
      var previous = 0;
      var next = 0;
      await tester.pumpWidget(
        strip(onPrevious: () => previous++, onNext: () => next++),
      );
      await tester.fling(
        find.byType(DayBoxesStrip),
        const Offset(300, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(previous, 1);
      await tester.fling(
        find.byType(DayBoxesStrip),
        const Offset(-300, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(next, 1);
    });

    testWidgets('week paging is offered to VoiceOver as custom actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(strip(onPrevious: () {}));
      final labels = <String?>[];
      void collect(SemanticsNode node) {
        for (final id
            in node.getSemanticsData().customSemanticsActionIds ?? <int>[]) {
          labels.add(CustomSemanticsAction.getAction(id)?.label);
        }
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      expect(labels, contains('Previous week'));
      expect(labels, isNot(contains('Next week')));
      handle.dispose();
    });

    testWidgets('text stops growing at 1.3 so seven boxes fit 320pt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(strip());
      expect(tester.takeException(), isNull);
    });
  });
}
