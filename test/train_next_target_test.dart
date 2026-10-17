import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/widgets/exercise_detail_sheet.dart';
import 'package:tracend/features/train/widgets/exercise_list_card.dart';
import 'package:tracend/features/train/workout_repository.dart';

PlannedExercise _exercise(
  int order,
  String name,
  String? slug,
  NextTarget? target,
) => PlannedExercise(
  order: order,
  name: name,
  setCount: 3,
  repMin: 6,
  repMax: 8,
  targetRpe: 8,
  exerciseSlug: slug,
  nextTarget: target,
);

NextTarget _target(num? load, {String reason = 'top_of_range', int reps = 6}) =>
    NextTarget(
      action: NextTargetAction.addLoad,
      reason: reason,
      loadKg: load,
      reps: reps,
      sets: 3,
    );

final _workout = PlannedWorkout(
  id: 'w',
  name: 'Pull',
  objective: 'Pull',
  estimatedMinutes: 40,
  exercises: [
    _exercise(1, 'Barbell row', 'barbell-row', _target(62.5)),
    _exercise(2, 'Assisted pull-up', 'assisted-pull-up', _target(15)),
    _exercise(3, 'Assisted chin-up', null, _target(0, reps: 8)),
    _exercise(4, 'Push-up', 'push-up', _target(null, reps: 12)),
  ],
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: TracendTheme.dark,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('Train list: next target lines', () {
    testWidgets('a load reads in kg, machine help reads as help', (
      tester,
    ) async {
      await _pump(
        tester,
        ExerciseListCard(workout: _workout, onExerciseTap: (_) {}),
      );
      expect(find.text('3 × 6 to 8 · next 62.5 kg × 6'), findsOneWidget);
      expect(find.text('3 × 6 to 8 · next 15 kg help × 6'), findsOneWidget);
      expect(find.text('3 × 6 to 8 · next Unassisted × 8'), findsOneWidget);
      expect(find.text('3 × 6 to 8 · next 12 reps'), findsOneWidget);
    });

    testWidgets('VoiceOver announces help, not weight', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        ExerciseListCard(workout: _workout, onExerciseTap: (_) {}),
      );
      expect(
        find.bySemanticsLabel(
          'Assisted pull-up, 3 sets of 6 to 8 reps, next target 15 kilograms '
          'of help for 6 reps. Opens details.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Assisted chin-up, 3 sets of 6 to 8 reps, next target unassisted '
          'for 8 reps. Opens details.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Barbell row, 3 sets of 6 to 8 reps, next target 62.5 kilograms for '
          '6 reps. Opens details.',
        ),
        findsOneWidget,
      );
      expect(
        exerciseSpeech(_workout.exercises[3]),
        '3 sets of 6 to 8 reps, next target 12 reps',
      );
      handle.dispose();
    });
  });

  group('Exercise sheet: next target', () {
    Future<void> open(WidgetTester tester, PlannedExercise exercise) => _pump(
      tester,
      ExerciseDetailBody(
        exercise: exercise,
        history: Future.value(
          const ExerciseHistoryResult(exercises: {}, fromCache: true),
        ),
      ),
    );

    testWidgets('an assisted exercise shows help and says why in help', (
      tester,
    ) async {
      await open(tester, _workout.exercises[1]);
      await tester.pump();
      expect(find.text('Next target'), findsOneWidget);
      expect(find.text('15 kg help × 6'), findsOneWidget);
      expect(
        find.text(
          'Every set reached the top of the range last time. Use less help '
          'and start the reps again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('an unassisted target reads Unassisted', (tester) async {
      await open(tester, _workout.exercises[2]);
      await tester.pump();
      expect(find.text('Unassisted × 8'), findsOneWidget);
    });

    testWidgets('a weighted exercise keeps weight wording', (tester) async {
      await open(tester, _workout.exercises[0]);
      await tester.pump();
      expect(find.text('62.5 kg × 6'), findsOneWidget);
      expect(
        find.text(
          'Every set reached the top of the range last time. Add weight and '
          'start the reps again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('without a target the sheet shows the plan load', (
      tester,
    ) async {
      await open(
        tester,
        const PlannedExercise(
          order: 1,
          name: 'Barbell row',
          setCount: 3,
          repMin: 6,
          repMax: 8,
          targetRpe: 8,
          targetLoadKg: 60,
        ),
      );
      await tester.pump();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Next target'), findsNothing);
    });
  });
}
