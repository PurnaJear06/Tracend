import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';

Object? _fixture(String name) =>
    jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync());

/// Flutter to RPC: the app parses every payload `get_my_day_adjustment_v1`
/// and `respond_to_day_adjustment_v1` can return (the fixtures the server's
/// own tests pin) and sends the parameters they take.
void main() {
  const names = [
    'day_adjustment_v1_0_none',
    'day_adjustment_v1_0_hold',
    'day_adjustment_v1_0_reduce',
    'day_adjustment_v1_0_cardio',
    'day_adjustment_v1_0_safety',
    'day_adjustment_v1_0_safety_started',
    'day_adjustment_v1_0_reasked',
    'day_adjustment_v1_0_unknown',
    'respond_to_day_adjustment_v1_0',
  ];

  group('the app reads every 1.0 payload', () {
    for (final name in names) {
      test(name, () {
        final adjustment = DayAdjustment.tryParse(_fixture(name));
        expect(adjustment, isNotNull);
        expect(adjustment!.localDate, '2026-10-24');
        expect(adjustment.signals.recoveryScore, isNotNull);
      });
    }

    test('what each fixture says survives parsing', () {
      DayAdjustment read(String name) =>
          DayAdjustment.tryParse(_fixture(name))!;
      final reduce = read('day_adjustment_v1_0_reduce');
      expect(reduce.kind, DayAdjustmentKind.reduceSets);
      expect([reduce.setsTotalFrom, reduce.setsTotalTo], [9, 7]);
      expect(reduce.options.map((o) => o.kind), DayAdjustmentKind.values);
      final cardio = read('day_adjustment_v1_0_cardio');
      expect(cardio.cardio?.minutesMin, 20);
      expect(cardio.cardio?.minutesMax, 30);
      final safety = read('day_adjustment_v1_0_safety');
      expect(safety.safetyRoute, 'pain_referral');
      expect(safety.kind, isNull);
      expect(read('day_adjustment_v1_0_safety_started').sessionBegun, isTrue);
      final reasked = read('day_adjustment_v1_0_reasked');
      expect(reasked.previousAnswer?.reason, 'check_in');
      expect(reasked.appliedKind, DayAdjustmentKind.reduceSets);
      final unknown = read('day_adjustment_v1_0_unknown');
      expect(unknown.band, DayBand.unknown);
      expect(unknown.signals.recoveryLow, isTrue);
      final answered = read('respond_to_day_adjustment_v1_0');
      expect(answered.isAccepted, isTrue);
      expect(answered.origin, 'proposed');
      expect(answered.answeredAt, isNotNull);
    });

    test('a major version it does not know is refused, not guessed', () {
      final json = Map<String, dynamic>.from(
        _fixture('day_adjustment_v1_0_reduce')! as Map,
      )..['schema_version'] = '2.0';
      expect(DayAdjustment.tryParse(json), isNull);
    });

    test('a later 1.x payload with extra keys still reads', () {
      final json =
          Map<String, dynamic>.from(
              _fixture('day_adjustment_v1_0_reduce')! as Map,
            )
            ..['schema_version'] = '1.1'
            ..['joint_states'] = <Object>[];
      expect(DayAdjustment.tryParse(json), isNotNull);
    });
  });

  group('the parameters the app sends', () {
    late List<(String, Map<String, dynamic>)> calls;
    late Object? Function() answer;

    SupabaseDayAdjustmentRepository repository() =>
        SupabaseDayAdjustmentRepository.withRpc((function, params) async {
          calls.add((function, params));
          return answer();
        });

    setUp(() {
      calls = [];
      answer = () => _fixture('day_adjustment_v1_0_reduce');
    });

    test('a read sends the day as given, as a plain date', () async {
      await repository().load(DateTime(2026, 10, 24));
      expect(calls.single.$1, 'get_my_day_adjustment_v1');
      expect(calls.single.$2, {'local_date': '2026-10-24'});
    });

    test(
      'an answer sends accept, and a chosen kind only when chosen',
      () async {
        final repo = repository();
        await repo.respond(DateTime(2026, 10, 24), accept: true);
        await repo.respond(
          DateTime(2026, 10, 24),
          accept: true,
          chosen: DayAdjustmentKind.holdLoad,
        );
        await repo.respond(DateTime(2026, 10, 24), accept: false);
        expect(calls.map((c) => c.$1).toSet(), {
          'respond_to_day_adjustment_v1',
        });
        expect(calls[0].$2, {'local_date': '2026-10-24', 'accept': true});
        expect(calls[1].$2, {
          'local_date': '2026-10-24',
          'accept': true,
          'chosen_kind': 'hold_load',
        });
        expect(calls[2].$2, {'local_date': '2026-10-24', 'accept': false});
      },
    );

    for (final (code, read, answered) in [
      ('22023', DayAdjustmentFailure.wrongDate, DayAdjustmentFailure.refused),
      (
        '55000',
        DayAdjustmentFailure.unavailable,
        DayAdjustmentFailure.unavailable,
      ),
      ('P0001', DayAdjustmentFailure.tooMany, DayAdjustmentFailure.tooMany),
      ('42501', DayAdjustmentFailure.network, DayAdjustmentFailure.network),
    ]) {
      test('error $code is named', () async {
        answer = () => throw PostgrestException(message: 'no', code: code);
        await expectLater(
          repository().load(DateTime(2026, 10, 24)),
          throwsA(
            isA<DayAdjustmentException>().having(
              (e) => e.failure,
              'failure',
              read,
            ),
          ),
        );
        await expectLater(
          repository().respond(DateTime(2026, 10, 24), accept: true),
          throwsA(
            isA<DayAdjustmentException>().having(
              (e) => e.failure,
              'failure',
              answered,
            ),
          ),
        );
      });
    }

    test('an unreadable payload is named', () async {
      answer = () => {'schema_version': '9.0'};
      await expectLater(
        repository().load(DateTime(2026, 10, 24)),
        throwsA(
          isA<DayAdjustmentException>().having(
            (e) => e.failure,
            'failure',
            DayAdjustmentFailure.unreadable,
          ),
        ),
      );
    });
  });
}
