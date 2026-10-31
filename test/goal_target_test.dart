import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/goals/goal_target.dart';
import 'package:tracend/features/goals/goal_target_repository.dart';
import 'package:tracend/features/goals/widgets/goal_target_section.dart';

class _Repository implements GoalTargetRepository {
  _Repository(this.state, {this.refusal, this.loadFails = false});

  GoalTargetState state;
  final String? refusal;
  final bool loadFails;
  final saved = <GoalTarget>[];

  @override
  Future<GoalTargetState> load() async {
    if (loadFails) throw StateError('offline');
    return state;
  }

  @override
  Future<GoalTargetState> save(GoalTarget target) async {
    final message = refusal;
    if (message != null) throw GoalTargetException(message);
    saved.add(target);
    state = GoalTargetState(
      hasGoal: true,
      goalType: 'fat_loss',
      target: target,
      minTargetWeightKg: state.minTargetWeightKg,
    );
    return state;
  }
}

const _noTarget = GoalTargetState(
  hasGoal: true,
  goalType: 'fat_loss',
  target: GoalTarget(),
  minTargetWeightKg: 59.9,
  minTargetBodyFatPct: 12,
);

Widget _app(GoalTargetRepository repository) => MaterialApp(
  theme: TracendTheme.dark,
  home: Scaffold(body: GoalTargetSection(repository: repository)),
);

void main() {
  testWidgets('a goal without a target shows the Set your target card', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Repository(_noTarget)));
    await tester.pumpAndSettle();
    expect(find.text('Set your target'), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-target-set')), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-target-edit')), findsNothing);
  });

  testWidgets('nothing shows without a goal or when the read fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _Repository(
          const GoalTargetState(hasGoal: false, target: GoalTarget()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-target-card')), findsNothing);

    await tester.pumpWidget(_app(_Repository(_noTarget, loadFails: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-target-card')), findsNothing);
  });

  testWidgets('a weight below the healthy floor is stopped on the form', (
    tester,
  ) async {
    final repository = _Repository(_noTarget);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-set')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-weight')),
      '55',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Lowest healthy target for your height is 59.9 kg'),
      findsOneWidget,
    );
    expect(repository.saved, isEmpty);
  });

  testWidgets('a body-fat target below the floor is stopped on the form', (
    tester,
  ) async {
    final repository = _Repository(_noTarget);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body fat'));
    await tester.pumpAndSettle();
    expect(find.text('Lowest healthy target for you: 12%'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-min')),
      '8',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-max')),
      '14',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(find.text('Lowest healthy target for you is 12%'), findsOneWidget);
    expect(repository.saved, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-min')),
      '12',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(repository.saved.single.bodyFatMinPct, 12);
    expect(repository.saved.single.bodyFatMaxPct, 14);
  });

  testWidgets('a lower floor for a man is respected as the server sends it', (
    tester,
  ) async {
    final repository = _Repository(
      const GoalTargetState(
        hasGoal: true,
        goalType: 'fat_loss',
        target: GoalTarget(),
        minTargetBodyFatPct: 5,
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body fat'));
    await tester.pumpAndSettle();
    expect(find.text('Lowest healthy target for you: 5%'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-min')),
      '4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-max')),
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(find.text('Lowest healthy target for you is 5%'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-min')),
      '6',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(repository.saved.single.bodyFatMinPct, 6);
  });

  testWidgets('an older server without a floor still checks the range', (
    tester,
  ) async {
    final repository = _Repository(
      const GoalTargetState(
        hasGoal: true,
        goalType: 'fat_loss',
        target: GoalTarget(),
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body fat'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Lowest healthy target for you'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-min')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-fat-max')),
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(find.text('Between 3 and 60'), findsOneWidget);
  });

  testWidgets('saving a weight target replaces the card with the target', (
    tester,
  ) async {
    final repository = _Repository(_noTarget);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-set')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-weight')),
      '72',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(repository.saved.single.weightKg, 72);
    expect(find.text('Your target'), findsOneWidget);
    expect(find.text('72 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-target-edit')), findsOneWidget);
  });

  testWidgets('a physique goal needs a choice, then saves with its note', (
    tester,
  ) async {
    final repository = _Repository(_noTarget);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-set')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(find.text('Choose the look you are aiming for.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-physique-visible_abs')));
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-note')),
      'for summer',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(repository.saved.single.physique, 'visible_abs');
    expect(repository.saved.single.physiqueNote, 'for summer');
    expect(find.text('Visible abs (for summer)'), findsOneWidget);
  });

  testWidgets('a refusal from the server stays beside the Save button', (
    tester,
  ) async {
    final repository = _Repository(
      _noTarget,
      refusal: 'Target date must be within the next three years.',
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goal-target-set')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goal-target-weight')),
      '72',
    );
    await tester.tap(find.byKey(const ValueKey('goal-target-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-target-problem')), findsOneWidget);
    expect(
      find.text('Target date must be within the next three years.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('goal-target-save')), findsOneWidget);
  });

  test('a refusal is explained in plain words', () {
    expect(
      goalTargetErrorMessage(
        const PostgrestException(
          message: 'target weight is below the healthy range for this height',
          code: '22023',
        ),
      ),
      'Target weight is below the healthy range for this height.',
    );
    expect(
      goalTargetErrorMessage(
        const PostgrestException(
          message: 'there is no active goal',
          code: '55000',
        ),
      ),
      contains('no active goal'),
    );
    expect(
      goalTargetErrorMessage(const PostgrestException(message: 'x')),
      contains('Check your connection'),
    );
  });
}
