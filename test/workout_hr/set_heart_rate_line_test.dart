import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/workout_detail_screen.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_line.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

SetHeartRateSummary _set(
  int exercise,
  int number, {
  int? peak,
  double coverage = 1,
}) => SetHeartRateSummary(
  exerciseOrder: exercise,
  setNumber: number,
  peakBpm: peak,
  coverage: coverage,
  sampleCount: 10,
  source: HeartRateSource.watchWorkout,
);

void main() {
  group('setHeartRateLine', () {
    test('lists each set peak in set order with the share tracked', () {
      final report = SetHeartRateReport([
        _set(1, 2, peak: 152, coverage: 0.9),
        _set(1, 1, peak: 148, coverage: 0.8),
        _set(2, 1, peak: 120),
      ]);

      expect(
        setHeartRateLine(report, 1, completedSets: 2),
        'Heart rate peaks 148 · 152 bpm · 85% tracked',
      );
      expect(
        setHeartRateLine(report, 2, completedSets: 1),
        'Heart rate peaks 120 bpm · 100% tracked',
      );
    });

    test('a set without a peak is left out and still lowers the share', () {
      final report = SetHeartRateReport([
        _set(1, 1, peak: 140),
        _set(1, 2, coverage: 0.2),
      ]);

      expect(
        setHeartRateLine(report, 1, completedSets: 2),
        'Heart rate peaks 140 bpm · 60% tracked',
      );
    });

    test('untracked sets count as zero: 1 of 4 sets reads 25%, not 100%', () {
      final report = SetHeartRateReport([_set(1, 2, peak: 150)]);

      expect(
        setHeartRateLine(report, 1, completedSets: 4),
        'Heart rate peaks 150 bpm · 25% tracked',
      );
    });

    test('the share never exceeds what the report holds', () {
      final report = SetHeartRateReport([_set(1, 1, peak: 150)]);

      expect(
        setHeartRateLine(report, 1, completedSets: 0),
        'Heart rate peaks 150 bpm · 100% tracked',
      );
    });

    test('an exercise with no heart rate has no line', () {
      final report = SetHeartRateReport([_set(1, 1, coverage: 0.1)]);

      expect(setHeartRateLine(report, 1, completedSets: 1), isNull);
      expect(setHeartRateLine(report, 3, completedSets: 2), isNull);
    });
  });

  group('workout summary', () {
    Map<String, dynamic> session() => {
      'session_id': 'session-1',
      'state': 'completed',
      'duration_seconds': 1800,
      'exercises': [
        {
          'order': 1,
          'performed_name': 'Incline dumbbell press',
          'status': 'performed',
          'sets': [
            {'number': 1, 'repetitions': 8, 'load_kg': 30, 'completed': true},
            {'number': 2, 'repetitions': 8, 'load_kg': 30, 'completed': true},
          ],
        },
        {
          'order': 2,
          'performed_name': 'Cable fly',
          'status': 'performed',
          'sets': [
            {'number': 1, 'repetitions': 12, 'load_kg': 15, 'completed': true},
          ],
        },
      ],
    };

    Future<void> pump(
      WidgetTester tester, {
      Future<SetHeartRateReport> Function(String sessionId)? heartRate,
      Map<String, dynamic>? logged,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkoutSummaryBody(
              workout: PlannedWorkout.fixture,
              session: Future.value(logged ?? session()),
              heartRate: heartRate,
            ),
          ),
        ),
      ),
    );

    testWidgets('shows the heart-rate line under the exercise it belongs to', (
      tester,
    ) async {
      String? asked;
      await pump(
        tester,
        heartRate: (sessionId) async {
          asked = sessionId;
          return SetHeartRateReport([
            _set(1, 1, peak: 148, coverage: 0.9),
            _set(1, 2, peak: 152, coverage: 0.9),
          ]);
        },
      );
      await tester.pumpAndSettle();

      expect(asked, 'session-1');
      expect(
        find.textContaining('Heart rate peaks 148 · 152 bpm'),
        findsOneWidget,
      );
      expect(find.textContaining('Heart rate peaks'), findsOneWidget);
    });

    testWidgets('counts every completed set: 1 tracked of 4 shows 25%', (
      tester,
    ) async {
      final full = session();
      final first = (full['exercises'] as List).first as Map<String, dynamic>;
      first['sets'] = [
        for (var n = 1; n <= 4; n++)
          {'number': n, 'repetitions': 8, 'load_kg': 30, 'completed': true},
      ];
      await pump(
        tester,
        logged: full,
        heartRate: (_) async => SetHeartRateReport([_set(1, 3, peak: 150)]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('25% tracked'), findsOneWidget);
      expect(find.textContaining('100% tracked'), findsNothing);
    });

    testWidgets('shows nothing extra without a loader or when it fails', (
      tester,
    ) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Heart rate'), findsNothing);

      await pump(tester, heartRate: (_) async => throw StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Heart rate'), findsNothing);
      expect(find.text('Incline dumbbell press'), findsOneWidget);
    });
  });
}
