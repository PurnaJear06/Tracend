import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/trajectory_lens.dart';

Widget _wrap(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('TrajectoryLens', () {
    testWidgets('draws the bezier with labels for >= 2 points', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TrajectoryLens(
            points: [
              TrajectoryPoint(label: 'SLEEP', value: 80),
              TrajectoryPoint(label: 'TRAIN', value: 72),
              TrajectoryPoint(label: 'NOW', value: 72),
            ],
            decision: 'Push day is on.',
          ),
        ),
      );
      // Bounded pumps: the NOW-dot pulse is an intentional infinite loop.
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('SLEEP'), findsOneWidget);
      expect(find.text('TRAIN'), findsOneWidget);
      expect(find.text('NOW'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('falls back to chip rail with fewer than 2 points', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TrajectoryLens(
            points: [TrajectoryPoint(label: 'SLEEP', value: 80)],
            decision: 'Maintain plan',
            evidence: ['Sleep stable', 'Training on plan'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sleep stable'), findsOneWidget);
      expect(find.text('Training on plan'), findsOneWidget);
      expect(find.text('SLEEP'), findsNothing);
    });

    testWidgets('falls back to chip rail with zero points', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TrajectoryLens(
            decision: 'Maintain plan',
            evidence: ['Approved plan'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Approved plan'), findsOneWidget);
      expect(find.text('SLEEP'), findsNothing);
    });

    testWidgets('renders statically under Reduce Motion', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TrajectoryLens(
            points: [
              TrajectoryPoint(label: 'SLEEP', value: 80),
              TrajectoryPoint(label: 'NOW', value: 72),
            ],
            decision: 'Push day is on.',
          ),
          reduceMotion: true,
        ),
      );
      await tester.pump();

      expect(find.text('SLEEP'), findsOneWidget);
      expect(find.text('NOW'), findsOneWidget);
    });

    testWidgets('exposes a semantics label describing the values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TrajectoryLens(
            points: [
              TrajectoryPoint(label: 'SLEEP', value: 80),
              TrajectoryPoint(label: 'NOW', value: 72),
            ],
            decision: 'Push day is on.',
          ),
        ),
      );
      // Bounded pumps: the NOW-dot pulse is an intentional infinite loop.
      await tester.pump(const Duration(seconds: 2));

      final semantics = find.bySemanticsLabel(
        RegExp('Trajectory of today’s signals'),
      );
      expect(semantics, findsOneWidget);
    });
  });
}
