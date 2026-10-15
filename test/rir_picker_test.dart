import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/widgets/rir_picker.dart';
import 'package:tracend/features/train/widgets/set_row.dart';

import 'widgets/widget_host.dart';

void main() {
  group('rirLabel and rirHint', () {
    test('0 to 4 as numbers, 5 as five or more', () {
      expect(
        [for (var n = 0; n <= 5; n++) rirLabel(n)],
        ['0', '1', '2', '3', '4', '5+'],
      );
      expect(rirHint(0), 'Nothing left');
      expect(rirHint(1), '1 rep left');
      expect(rirHint(3), '3 reps left');
      expect(rirHint(5), '5 or more reps left');
    });
  });

  group('RirPicker', () {
    Future<List<Object?>> pump(
      WidgetTester tester, {
      int? value,
      bool clearable = true,
    }) async {
      final calls = <Object?>[];
      await tester.pumpWidget(
        widgetHost(
          Padding(
            padding: const EdgeInsets.all(16),
            child: RirPicker(
              title: 'Reps left on set 2',
              value: value,
              onSelected: calls.add,
              onClear: clearable ? () => calls.add('clear') : null,
              dismissLabel: 'Not now',
              onDismiss: () => calls.add('dismiss'),
            ),
          ),
        ),
      );
      return calls;
    }

    testWidgets('offers 0 to 5+ and reports the choice', (tester) async {
      final calls = await pump(tester);
      for (final label in ['0', '1', '2', '3', '4', '5+']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Reps left on set 2'), findsOneWidget);
      expect(find.text('How many more reps could you do?'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);

      await tester.tap(find.text('5+'));
      await tester.tap(find.bySemanticsLabel('Nothing left'));
      await tester.tap(find.text('Not now'));
      expect(calls, [5, 0, 'dismiss']);
    });

    testWidgets('marks the chosen value and can clear it', (tester) async {
      final calls = await pump(tester, value: 2);
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 reps left')),
        matchesSemantics(
          label: '2 reps left',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('3 reps left')),
        matchesSemantics(
          label: '3 reps left',
          isButton: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Clear'));
      expect(calls, ['clear']);
    });

    testWidgets('every cell is at least 44 pt tall', (tester) async {
      await pump(tester);
      for (final label in ['0', '5+']) {
        final cell = find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        );
        expect(tester.getSize(cell).height, greaterThanOrEqualTo(44));
      }
    });

    for (final brightness in [Brightness.dark, Brightness.light]) {
      testWidgets('fits 320 pt at 2× text (${brightness.name})', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          widgetHost(
            theme: brightness == Brightness.dark
                ? TracendTheme.dark
                : TracendTheme.light,
            SingleChildScrollView(
              child: RirPicker(
                title: 'Reps left on set 12',
                value: 5,
                onSelected: (_) {},
                onClear: () {},
                dismissLabel: 'Not now',
                onDismiss: () {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('LoggedSetRow', () {
    Future<void> row(WidgetTester tester, {int? rir, int? rpe}) =>
        tester.pumpWidget(
          widgetHost(
            LoggedSetRow(
              number: 1,
              description: '60 kg × 8',
              rir: rir,
              rpe: rpe,
              onEffort: () {},
              onUndo: () {},
            ),
          ),
        );

    testWidgets('shows reps left, an older effort, or asks', (tester) async {
      await row(tester, rir: 5, rpe: 5);
      expect(find.text('5+ left'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Reps left for set 1: 5 or more reps left, change',
        ),
        findsOneWidget,
      );

      await row(tester, rpe: 8);
      expect(find.text('RPE 8'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Effort for set 1: RPE 8, change'),
        findsOneWidget,
      );

      await row(tester);
      expect(find.text('Reps left'), findsOneWidget);
      expect(find.bySemanticsLabel('Add reps left for set 1'), findsOneWidget);
    });
  });
}
