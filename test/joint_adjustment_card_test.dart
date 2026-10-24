import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_card.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/readiness_copy.dart';
import 'package:tracend/features/readiness/safety_copy.dart';
import 'package:tracend/features/readiness/safety_referral_sheet.dart';
import 'package:tracend/features/train/workout_repository.dart';

import 'day_adjustment_fixtures.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
      as Map,
);

final _day = DateTime(2026, 10, 24);

Future<FakeDayAdjustmentRepository> _pump(
  WidgetTester tester,
  Map<String, dynamic> json,
) async {
  final repository = FakeDayAdjustmentRepository(json);
  final controller = DayAdjustmentController(
    repository: repository,
    serverToday: () async => _day,
    clock: () => DateTime(2026, 10, 24, 9),
  );
  addTearDown(controller.dispose);
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DayAdjustmentCard(
            controller: controller,
            onTalkToCoach: (_) {},
            onCheckIn: () {},
          ),
        ),
      ),
    ),
  );
  await controller.load();
  await tester.pumpAndSettle();
  return repository;
}

Finder _text(String text) => find.descendant(
  of: find.byType(DayAdjustmentCard),
  matching: find.text(text),
);

Map<String, dynamic> _swap(Map<String, dynamic> json) {
  final change =
      Map<String, dynamic>.from((json['changes'] as List).single as Map)
        ..addAll({
          'joint': 'shoulder',
          'joint_action': 'swap',
          'swap_to_slug': 'machine-chest-press',
          'swap_to_name': 'Machine chest press',
          'range_note_code': null,
          'range_note_codes': null,
        });
  return {
    ...json,
    'changes': [change],
  };
}

Map<String, dynamic> _held({
  String hold = 'clinician',
  bool persistent = false,
  String explanation = 'Your check-in looks fine. Train as planned.',
}) => {
  ...adjustmentJson(
    kind: 'none',
    status: 'none',
    band: 'green',
    triggers: const [],
    explanation: explanation,
    confidence: 'high',
    missing: const [],
  ),
  'schema_version': '1.1',
  'local_date': '2026-10-24',
  'joint_states': <Object?>[
    {
      'area': 'knee',
      'state': 'held',
      'since': '2026-10-20',
      'severity': 5,
      'persistent': persistent,
      'hold_outcome': hold,
    },
  ],
  'exercise_joint_options': <Object>[],
};

void main() {
  group('a joint adjustment is one tap and one Undo', () {
    testWidgets('it is proposed with the range cue of the limited exercise', (
      tester,
    ) async {
      final repository = await _pump(
        tester,
        _fixture('day_adjustment_v1_1_joint'),
      );
      expect(_text('Easier on your joints today'), findsOneWidget);
      expect(
        _text(
          'Your shoulder is on watch. 1 exercise kept in a pain-free range.',
        ),
        findsOneWidget,
      );
      expect(
        _text('Barbell bench press: Lower only as far as stays pain-free.'),
        findsOneWidget,
      );
      expect(_text('Use these changes'), findsOneWidget);
      expect(_text('Train as planned'), findsOneWidget);
      expect(repository.responses, isEmpty);
    });

    testWidgets('accepting stores the answer and Undo takes it back', (
      tester,
    ) async {
      final repository = await _pump(
        tester,
        _fixture('day_adjustment_v1_1_joint'),
      );
      await tester.tap(_text('Use these changes'));
      await tester.pumpAndSettle();
      expect(repository.responses.single.accept, isTrue);
      expect(repository.responses.single.chosen, isNull);
      expect(_text('Joint changes set for today.'), findsWidgets);
      expect(_text(undoLabel), findsOneWidget);
      // The change is still said after the answer.
      expect(
        _text('Barbell bench press: Lower only as far as stays pain-free.'),
        findsOneWidget,
      );

      await tester.tap(_text(undoLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(repository.responses.last.accept, isFalse);
      expect(_text(declinedTitle), findsOneWidget);
    });

    testWidgets('a swap names the gentler exercise and the empty weight', (
      tester,
    ) async {
      await _pump(tester, _swap(_fixture('day_adjustment_v1_1_joint')));
      expect(
        _text('Barbell bench press: use Machine chest press instead.'),
        findsOneWidget,
      );
      expect(_text(swapLoadLine), findsOneWidget);
    });

    testWidgets('an exercise left out is said so', (tester) async {
      final json = _fixture('day_adjustment_v1_1_joint');
      final change = Map<String, dynamic>.from(
        (json['changes'] as List).single as Map,
      )..addAll({'joint_action': 'drop', 'sets_to': 0});
      await _pump(tester, {
        ...json,
        'changes': [change],
      });
      expect(_text('Barbell bench press is left out today.'), findsOneWidget);
    });

    testWidgets('the joint changes ride on a readiness kind too', (
      tester,
    ) async {
      final json = _swap(_fixture('day_adjustment_v1_1_joint'));
      final option = (json['options'] as List).firstWhere(
        (o) => (o as Map)['kind'] == 'reduce_sets',
      );
      await _pump(tester, {
        ...json,
        'kind': 'reduce_sets',
        'changes': (option as Map)['changes'],
        'explanation': option['explanation'],
      });
      expect(_text('One set fewer today'), findsOneWidget);
      expect(
        _text('Barbell bench press: use Machine chest press instead.'),
        findsNothing,
        reason: 'the option\'s own change here is a limit, not a swap',
      );
      expect(
        _text('Barbell bench press: Lower only as far as stays pain-free.'),
        findsOneWidget,
      );
    });
  });

  group('a held area is not forgotten', () {
    testWidgets('a hold that says see a doctor shows its reminder on a day '
        'with no change', (tester) async {
      await _pump(tester, _held());
      expect(
        _text("Your knee is on hold until you've had it checked."),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a reminder the server\'s sentence already has is said once', (
      tester,
    ) async {
      await _pump(
        tester,
        _held(
          explanation:
              'Your check-in looks fine. Train as planned. Your knee is on '
              "hold until you've had it checked.",
        ),
      );
      expect(
        find.textContaining(
          "Your knee is on hold until you've had it checked.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('pain that has lasted two weeks says so with a referral', (
      tester,
    ) async {
      await _pump(tester, _held(persistent: true));
      expect(
        _text(
          'Your knee pain has lasted two weeks. Please see a physio or doctor.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an area on watch is said even when nothing in the session '
        'changes', (tester) async {
      final json = _held();
      (json['joint_states'] as List)[0] = {
        'area': 'shoulder',
        'state': 'watch',
        'since': '2026-10-23',
        'severity': 2,
        'persistent': false,
        'hold_outcome': null,
      };
      json['explanation'] = 'Your check-in looks fine. Train as planned.';
      json['band'] = 'green';
      await _pump(tester, json);
      expect(_text('Your shoulder is on watch.'), findsOneWidget);
    });

    testWidgets('a hold on a clinician outcome on a rest day still reminds', (
      tester,
    ) async {
      final json = _held()
        ..['available'] = false
        ..['unavailable_reason'] = 'rest_day'
        ..['explanation'] =
            'No session is planned today. Nothing in your plan changes.';
      await _pump(tester, json);
      expect(
        _text("Your knee is on hold until you've had it checked."),
        findsOneWidget,
      );
    });

    testWidgets('a state this build does not know is not shown or acted on', (
      tester,
    ) async {
      final json = _held();
      (json['joint_states'] as List)[0] = {
        'area': 'knee',
        'state': 'a_state_from_the_future',
        'severity': 5,
        'persistent': false,
      };
      await _pump(tester, json);
      expect(find.byType(DayAdjustmentCard), findsOneWidget);
      expect(find.textContaining('knee'), findsNothing);
    });
  });

  group('a red-flag route shows its referral', () {
    for (final (route, title) in [
      ('urgent', 'Get medical help now'),
      ('clinician_today', 'Get this checked today'),
      ('clinician', 'See a doctor or physio'),
      ('pain_referral', "Don't train through this pain"),
    ]) {
      testWidgets(route, (tester) async {
        final json = _fixture('day_adjustment_v1_1_red_flag')
          ..['safety_route'] = route;
        await _pump(tester, json);
        expect(_text(title), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        expect(_text('Train as planned'), findsNothing);
      });
    }

    testWidgets('the two-week line goes with the referral', (tester) async {
      final json = _fixture('day_adjustment_v1_1_red_flag');
      ((json['joint_states'] as List)[0] as Map)['persistent'] = true;
      await _pump(tester, json);
      expect(_text('Get this checked today'), findsOneWidget);
      expect(
        _text(
          'Your knee pain has lasted two weeks. Please see a physio or doctor.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a kind from the future without a route offers nothing to '
        'apply', (tester) async {
      final json = _fixture('day_adjustment_v1_1_joint')
        ..['kind'] = 'a_kind_from_the_future';
      final repository = await _pump(tester, json);
      expect(find.byType(FilledButton), findsNothing);
      expect(repository.responses, isEmpty);
    });
  });

  group('the referral sheet', () {
    Future<void> open(WidgetTester tester, String route) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSafetyReferralSheet(
                  context,
                  route,
                  extraLines: const ['An extra line.'],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    for (final route in [
      'urgent',
      'clinician_today',
      'a_route_from_the_future',
    ]) {
      testWidgets('$route cannot be closed without Got it', (tester) async {
        await open(tester, route);
        expect(find.text(gotItLabel), findsOneWidget);
        expect(find.text('An extra line.'), findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);
        // Tapping the scrim, swiping down and going back do nothing.
        await tester.tapAt(const Offset(195, 40));
        await tester.pumpAndSettle();
        expect(find.text(gotItLabel), findsOneWidget);
        await tester.drag(find.text(gotItLabel), const Offset(0, 700));
        await tester.pumpAndSettle();
        expect(find.text(gotItLabel), findsOneWidget);
        await tester.tap(find.text(gotItLabel));
        await tester.pumpAndSettle();
        expect(find.text(gotItLabel), findsNothing);
      });
    }

    for (final route in ['pain_referral', 'clinician']) {
      testWidgets('$route can be closed with the scrim too', (tester) async {
        await open(tester, route);
        await tester.tapAt(const Offset(195, 40));
        await tester.pumpAndSettle();
        expect(find.text(gotItLabel), findsNothing);
      });
    }

    testWidgets('no sheet offers a training choice', (tester) async {
      await open(tester, 'urgent');
      expect(find.text('Train as planned'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('Get medical help now'), findsOneWidget);
      expect(find.textContaining('emergency number'), findsOneWidget);
    });
  });

  group('what the standing answer does to the session', () {
    PlannedWorkout workout() => const PlannedWorkout(
      id: 'b4200000-0000-4000-8000-000000000001',
      name: 'Lower A',
      objective: '',
      estimatedMinutes: 50,
      exercises: [
        PlannedExercise(
          order: 1,
          name: 'Barbell bench press',
          setCount: 4,
          repMin: 6,
          repMax: 8,
          targetRpe: 8,
          targetLoadKg: 80,
          exerciseSlug: 'barbell-bench-press',
        ),
        PlannedExercise(
          order: 2,
          name: 'Leg extension',
          setCount: 3,
          repMin: 10,
          repMax: 12,
          targetRpe: 8,
        ),
      ],
    );

    DayAdjustment accepted(Map<String, dynamic> json) =>
        DayAdjustment.tryParse({...json, 'status': 'accepted'})!;

    test('a limited exercise carries its cue and a lower effort', () {
      final adjustment = accepted(_fixture('day_adjustment_v1_1_joint'));
      final shown = adjustment.applyTo(workout());
      final bench = shown.exercises.first;
      expect(bench.rangeNoteCodes, ['shoulder_press_depth']);
      expect(bench.targetRpe, 7);
      expect(bench.setCount, 4);
      expect(bench.name, 'Barbell bench press');
      expect(shown.exercises.last.rangeNoteCodes, isEmpty);
    });

    test('a swap is the gentler exercise with no starting weight', () {
      final adjustment = accepted(_swap(_fixture('day_adjustment_v1_1_joint')));
      final bench = adjustment.applyTo(workout(), sets: false).exercises.first;
      expect(bench.name, 'Machine chest press');
      expect(bench.exerciseSlug, 'machine-chest-press');
      expect(bench.targetLoadKg, isNull);
      expect(bench.nextTarget, isNull);
      expect(bench.swappedFrom!.name, 'Barbell bench press');
      expect(bench.asPlanned.exerciseSlug, 'barbell-bench-press');
    });

    test('an exercise left out has no sets, in either view', () {
      final json = _fixture('day_adjustment_v1_1_joint');
      final change = Map<String, dynamic>.from(
        (json['changes'] as List).single as Map,
      )..addAll({'joint_action': 'drop', 'sets_to': 0});
      final adjustment = accepted({
        ...json,
        'changes': [change],
      });
      for (final sets in [true, false]) {
        final bench = adjustment.applyTo(workout(), sets: sets).exercises.first;
        expect(bench.leftOut, isTrue, reason: 'sets: $sets');
        expect(bench.setCount, 0);
        expect(bench.plannedSetCount, 4);
      }
    });

    test('a day that is only proposed, or has a route, changes nothing', () {
      final proposed = DayAdjustment.tryParse(
        _fixture('day_adjustment_v1_1_joint'),
      )!;
      expect(
        proposed.applyTo(workout()).exercises.first.rangeNoteCodes,
        isEmpty,
      );
      final routed = DayAdjustment.tryParse({
        ..._fixture('day_adjustment_v1_1_joint'),
        'status': 'accepted',
        'safety_route': 'clinician_today',
      })!;
      expect(routed.applyTo(workout()).exercises.first.rangeNoteCodes, isEmpty);
    });

    test('a swap without its replacement is not a swap', () {
      final json = _swap(_fixture('day_adjustment_v1_1_joint'));
      ((json['changes'] as List)[0] as Map)['swap_to_name'] = null;
      final change = DayAdjustment.tryParse(json)!.changes.single;
      expect(change.jointAction, isNull);
    });

    test('the joint of an exercise is told only when it can be', () {
      final adjustment = DayAdjustment.tryParse(
        _fixture('day_adjustment_v1_1_joint'),
      )!;
      // Only a standing accepted answer knows; a proposal does not guess.
      expect(adjustment.likelyJoint(1), PainArea.shoulder);
      expect(adjustment.likelyJoint(5), PainArea.back);
      expect(adjustment.likelyJoint(2), isNull);
      expect(adjustment.likelyJoint(99), isNull);
    });

    test('the lines under an exercise carry its cues', () {
      final bench = accepted(
        _fixture('day_adjustment_v1_1_joint'),
      ).applyTo(workout()).exercises.first;
      expect(rangeNoteLines(bench.rangeNoteCodes), [
        'Lower only as far as stays pain-free.',
      ]);
      expect(rangeNoteLines(['nothing_known_of_this']), [genericRangeNote]);
    });
  });
}
