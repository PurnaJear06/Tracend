import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/train/guidance/guidance_copy.dart';
import 'package:tracend/features/train/guidance/training_guidance.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
      as Map,
);

TrainingGuidance _read(String name) =>
    TrainingGuidance.tryParse(_fixture(name))!;

/// Flutter to RPC: the app parses every payload `get_my_training_guidance_v1`
/// can return (the fixtures the server's own tests pin), reads a later 1.x
/// without crashing, and sends the parameters the server takes.
void main() {
  group('the app reads every payload', () {
    for (final name in [
      'training_guidance_v1_0',
      'training_guidance_v1_1',
      'training_guidance_v1_1_withheld',
    ]) {
      test(name, () {
        final guidance = TrainingGuidance.tryParse(_fixture(name));
        expect(guidance, isNotNull);
        expect(guidance!.localDate, '2026-10-24');
        expect(guidance.deload, isNotNull);
      });
    }

    test('1.0: a running lighter week and no cardio', () {
      final guidance = _read('training_guidance_v1_0');
      expect(guidance.deload!.status, DeloadStatus.running);
      expect(
        guidance.deload!.proposalId,
        '00000000-0000-4000-8000-000000000001',
      );
      expect(guidance.cardioWeek, isNull);
      expect(guidance.cardioWithheld, isNull);
      expect(deloadCardState(guidance), DeloadCardState.running);
    });

    test('1.1: a suggestion with its reasons, and the cardio week', () {
      final guidance = _read('training_guidance_v1_1');
      expect(guidance.deload!.status, DeloadStatus.suggested);
      expect(guidance.deload!.reasons, [
        DeloadReason.performanceDrop,
        DeloadReason.runDown,
      ]);
      expect(guidance.deload!.proposalId, isNull);
      expect(guidance.safetyRoute, isNull);
      expect(deloadCardState(guidance), DeloadCardState.suggested);
      final cardio = guidance.cardioWeek!;
      expect(cardio.targetMin, 150);
      expect(cardio.stretchMax, 300);
      expect(cardio.doneMin, 85);
      expect(cardio.intensityKnown, isFalse);
      expect(cardio.vigorousAllowed, isTrue);
      expect(cardio.vigorousSessionsMax, 2);
      expect(cardio.vigorousCountsAs, 2);
      expect(cardio.liftSeparationHours, 3);
      expect(cardio.easyHrReserveMax, 60);
      expect(cardio.windowTo, DateTime(2026, 10, 24));
      expect(cardioRowValue(cardio), '85 of 150 min');
    });

    test('1.1 on a day with a safety route: no card, no cardio dose', () {
      final guidance = _read('training_guidance_v1_1_withheld');
      expect(guidance.safetyRoute, 'clinician_today');
      expect(guidance.deload!.status, DeloadStatus.notDue);
      expect(guidance.deload!.suppressedBy, 'safety_route');
      expect(guidance.cardioWithheld, CardioWithheld.safetyRoute);
      expect(guidance.cardioWeek, isNull);
      expect(deloadCardState(guidance), DeloadCardState.hidden);
    });
  });

  group('a later version is read, never trusted past what it says', () {
    test('a later 1.x with extra keys still reads', () {
      final json = _fixture('training_guidance_v1_1')
        ..['schema_version'] = '1.4'
        ..['something_new'] = {'a': 1};
      (json['deload'] as Map<String, dynamic>)['next_week'] = 'x';
      final guidance = TrainingGuidance.tryParse(json)!;
      expect(deloadCardState(guidance), DeloadCardState.suggested);
      expect(guidance.cardioWeek, isNotNull);
    });

    test('a major version it does not know is refused, not guessed', () {
      for (final version in ['2.0', '0.9', '', 1, null]) {
        final json = _fixture('training_guidance_v1_1')
          ..['schema_version'] = version;
        expect(TrainingGuidance.tryParse(json), isNull, reason: '$version');
      }
      expect(TrainingGuidance.tryParse(null), isNull);
      expect(TrainingGuidance.tryParse('text'), isNull);
      expect(TrainingGuidance.tryParse(<Object>[]), isNull);
    });

    test('a day it cannot read is refused', () {
      final json = _fixture('training_guidance_v1_1')..['local_date'] = 'today';
      expect(TrainingGuidance.tryParse(json), isNull);
    });

    test('an unknown status hides the card and leaves the cardio row', () {
      final json = _fixture('training_guidance_v1_1');
      (json['deload'] as Map<String, dynamic>)['status'] = 'snoozed';
      final guidance = TrainingGuidance.tryParse(json)!;
      expect(guidance.deload, isNull);
      expect(deloadCardState(guidance), DeloadCardState.hidden);
      expect(guidance.cardioWeek, isNotNull);
    });

    test(
      'an unknown reason is left out; only unknown reasons hide the card',
      () {
        final json = _fixture('training_guidance_v1_1');
        (json['deload'] as Map<String, dynamic>)['reasons'] = [
          'performance_drop',
          'a_reason_from_the_future',
        ];
        final some = TrainingGuidance.tryParse(json)!;
        expect(some.deload!.reasons, [DeloadReason.performanceDrop]);
        expect(some.deload!.hadUnreadReasons, isTrue);
        expect(deloadCardState(some), DeloadCardState.suggested);

        (json['deload'] as Map<String, dynamic>)['reasons'] = [
          'a_reason_from_the_future',
        ];
        final none = TrainingGuidance.tryParse(json)!;
        expect(none.deload!.reasons, isEmpty);
        expect(deloadCardState(none), DeloadCardState.hidden);
      },
    );

    test('an open proposal without an id has no card', () {
      for (final status in ['pending', 'running']) {
        final json = _fixture('training_guidance_v1_1');
        (json['deload'] as Map<String, dynamic>)
          ..['status'] = status
          ..['reasons'] = <Object>[]
          ..['proposal_id'] = null;
        expect(
          deloadCardState(TrainingGuidance.tryParse(json)),
          DeloadCardState.hidden,
          reason: status,
        );
      }
    });

    test('a pending lighter week with its id shows', () {
      final json = _fixture('training_guidance_v1_1');
      (json['deload'] as Map<String, dynamic>)
        ..['status'] = 'pending'
        ..['proposal_id'] = '00000000-0000-4000-8000-000000000002';
      expect(
        deloadCardState(TrainingGuidance.tryParse(json)),
        DeloadCardState.pending,
      );
    });

    test('a suggestion on a day with a safety route never shows, '
        'whatever the status says', () {
      for (final route in ['clinician', 'a_route_from_the_future']) {
        for (final status in ['suggested', 'pending']) {
          final json = _fixture('training_guidance_v1_1')
            ..['safety_route'] = route;
          (json['deload'] as Map<String, dynamic>)
            ..['status'] = status
            ..['proposal_id'] = '00000000-0000-4000-8000-000000000002';
          expect(
            deloadCardState(TrainingGuidance.tryParse(json)),
            DeloadCardState.hidden,
            reason: '$route $status',
          );
        }
      }
    });

    test('the cardio week keeps null as null and never reads it as 0', () {
      final json = _fixture('training_guidance_v1_1');
      (json['cardio_week'] as Map<String, dynamic>)['done_min'] = null;
      final cardio = TrainingGuidance.tryParse(json)!.cardioWeek!;
      expect(cardio.doneMin, isNull);
      expect(cardioRowValue(cardio), cardioNoDataValue);
      expect(cardioRowValue(cardio), isNot(contains('0')));
    });

    test('a cardio week missing its minutes, or with a wrong type, is not '
        'shown', () {
      void mutate(void Function(Map<String, dynamic> week) change) {
        final json = _fixture('training_guidance_v1_1');
        change(json['cardio_week'] as Map<String, dynamic>);
        final guidance = TrainingGuidance.tryParse(json)!;
        expect(guidance.cardioWeek, isNull);
        // The lighter-week part still reads.
        expect(deloadCardState(guidance), DeloadCardState.suggested);
      }

      mutate((week) => week.remove('done_min'));
      mutate((week) => week['done_min'] = '85');
      mutate((week) => week['done_min'] = -5);
      mutate((week) => week['target_min'] = 0);
      mutate((week) => week['target_min'] = null);
      mutate((week) => week['vigorous_allowed'] = 'yes');
      mutate((week) => week['intensity_known'] = null);
    });

    test(
      'a cardio reason this build does not know still withholds the dose',
      () {
        final json = _fixture('training_guidance_v1_1_withheld')
          ..['cardio_withheld'] = 'a_reason_from_the_future'
          ..['cardio_week'] = _fixture('training_guidance_v1_1')['cardio_week'];
        final guidance = TrainingGuidance.tryParse(json)!;
        expect(guidance.cardioWithheld, isNull);
        expect(guidance.cardioWeek, isNull);
      },
    );

    test('a stretch figure not above the target is left out', () {
      final json = _fixture('training_guidance_v1_1');
      (json['cardio_week'] as Map<String, dynamic>)['stretch_max'] = 100;
      expect(TrainingGuidance.tryParse(json)!.cardioWeek!.stretchMax, isNull);
    });
  });

  group('the parameters the app sends', () {
    late List<(String, Map<String, dynamic>)> rpcCalls;
    late List<(String, Map<String, dynamic>)> invokeCalls;
    late Object? Function() rpcAnswer;
    late Object? Function() invokeAnswer;

    SupabaseTrainingGuidanceRepository repository() =>
        SupabaseTrainingGuidanceRepository.withBackends(
          rpc: (function, params) async {
            rpcCalls.add((function, params));
            return rpcAnswer();
          },
          invoke: (function, body) async {
            invokeCalls.add((function, body));
            return invokeAnswer();
          },
        );

    setUp(() {
      rpcCalls = [];
      invokeCalls = [];
      rpcAnswer = () => _fixture('training_guidance_v1_1');
      invokeAnswer = () => {
        'schema_version': '1.0',
        'proposal_id': '00000000-0000-4000-8000-0000000000b1',
        'created': true,
      };
    });

    test('a read sends the day as given, as a plain date, and nothing '
        'else', () async {
      await repository().load(DateTime(2026, 10, 24));
      expect(rpcCalls.single.$1, 'get_my_training_guidance_v1');
      expect(rpcCalls.single.$2, {'local_date': '2026-10-24'});
    });

    test('preparing a lighter week sends the kind and the day, never a user '
        'id', () async {
      final id = await repository().prepareDeload(DateTime(2026, 10, 24));
      expect(id, '00000000-0000-4000-8000-0000000000b1');
      expect(invokeCalls.single.$1, 'training-proposals');
      expect(invokeCalls.single.$2, {
        'schema_version': '1.0',
        'kind': 'deload',
        'local_date': '2026-10-24',
      });
    });

    test('a database error is named', () async {
      for (final (code, failure) in [
        ('22023', TrainingGuidanceFailure.wrongDate),
        ('42501', TrainingGuidanceFailure.network),
      ]) {
        rpcAnswer = () => throw PostgrestException(message: 'no', code: code);
        await expectLater(
          repository().load(DateTime(2026, 10, 24)),
          throwsA(
            isA<TrainingGuidanceException>().having(
              (e) => e.failure,
              'failure',
              failure,
            ),
          ),
        );
      }
    });

    test('a payload it cannot read is unreadable', () async {
      rpcAnswer = () => {'schema_version': '2.0'};
      await expectLater(
        repository().load(DateTime(2026, 10, 24)),
        throwsA(
          isA<TrainingGuidanceException>().having(
            (e) => e.failure,
            'failure',
            TrainingGuidanceFailure.unreadable,
          ),
        ),
      );
      invokeAnswer = () => {'schema_version': '1.0'};
      await expectLater(
        repository().prepareDeload(DateTime(2026, 10, 24)),
        throwsA(
          isA<TrainingGuidanceException>().having(
            (e) => e.failure,
            'failure',
            TrainingGuidanceFailure.unreadable,
          ),
        ),
      );
    });

    test('the function\'s answers are named', () async {
      for (final (status, details, failure) in [
        (422, {'error': 'wrong_date'}, TrainingGuidanceFailure.wrongDate),
        (
          409,
          {'error': 'not_suggested', 'status': 'not_due'},
          TrainingGuidanceFailure.notSuggested,
        ),
        (
          409,
          {'error': 'plan_changed', 'reason': 'Your plan changed.'},
          TrainingGuidanceFailure.refused,
        ),
        (
          503,
          {'error': 'guidance_unavailable'},
          TrainingGuidanceFailure.network,
        ),
        (401, {'error': 'invalid_session'}, TrainingGuidanceFailure.network),
      ]) {
        invokeAnswer = () =>
            throw FunctionException(status: status, details: details);
        await expectLater(
          repository().prepareDeload(DateTime(2026, 10, 24)),
          throwsA(
            isA<TrainingGuidanceException>()
                .having((e) => e.failure, 'failure', failure)
                .having(
                  (e) => e.reason,
                  'reason',
                  failure == TrainingGuidanceFailure.refused
                      ? 'Your plan changed.'
                      : isNull,
                ),
          ),
          reason: '$status $details',
        );
      }
    });
  });
}
