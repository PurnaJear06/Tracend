import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/cycle/cycle_repository.dart';

Map<String, dynamic> _fixture(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  return Map<String, dynamic>.from(json.decode(file.readAsStringSync()) as Map);
}

Map<String, dynamic> _first(Map<String, dynamic> source, String list) =>
    (source[list] as List).first as Map<String, dynamic>;

Map<String, dynamic> _copy(Map<String, dynamic> source) =>
    Map<String, dynamic>.from(json.decode(json.encode(source)) as Map);

void main() {
  group('Cycle contract: get_my_cycle_v1 and the RPCs that return it, 1.0', () {
    // The key lists are the contract: add keys, never remove or rename them.
    // supabase/tests/database pins the same lists against the database.
    const keys = [
      'apple_health_enabled',
      'cycles',
      'recent_days',
      'schema_version',
      'state',
      'status',
      'tracking_enabled',
      'typical_cycle_days',
    ];
    const stateKeys = [
      'confidence',
      'cycle_day',
      'expected_from',
      'expected_to',
      'late_days',
      'no_period_long',
      'period_day',
      'phase',
      'weight_water_window',
    ];

    const names = [
      'my_cycle_v1_0_off.json',
      'my_cycle_v1_0_regular.json',
      'my_cycle_v1_0_contraception.json',
    ];

    for (final name in names) {
      test('$name carries exactly the contract keys', () {
        final fixture = _fixture(name);
        expect(fixture['schema_version'], '1.0');
        expect(fixture.keys.toList()..sort(), keys);
        expect((fixture['state'] as Map).keys.toList()..sort(), stateKeys);
      });
    }

    test('tracking off reads as off', () {
      final answer = parseCycleAnswer(_fixture('my_cycle_v1_0_off.json'));
      expect(answer.trackingEnabled, isFalse);
      expect(answer.status, isNull);
      expect(answer.recentDays, isEmpty);
      expect(answer.cycles, isEmpty);
      expect(answer.state.noPeriodLong, isFalse);
    });

    test('a regular cycle reads with its state, days and cycles', () {
      final answer = parseCycleAnswer(_fixture('my_cycle_v1_0_regular.json'));
      expect(answer.trackingEnabled, isTrue);
      expect(answer.status, CycleStatus.regular);
      expect(answer.typicalCycleDays, 28);
      expect(answer.state.cycleDay, 18);
      expect(answer.state.phase, CyclePhase.secondHalf);
      expect(answer.state.confidence, CycleConfidence.medium);
      expect(answer.state.expectedFrom, DateTime(2026, 12, 8));
      expect(answer.state.expectedTo, DateTime(2026, 12, 12));
      expect(answer.recentDays.single.flow, PeriodFlow.medium);
      expect(answer.recentDays.single.cramps, CycleCramps.mild);
      expect(answer.recentDays.single.isStart, isTrue);
      expect(answer.recentDays.single.source, CycleSource.manual);
      expect(answer.cycles, hasLength(2));
      expect(answer.cycles.first.lengthDays, 28);
      expect(answer.cycles.last.lengthDays, isNull);
      expect(answer.cycles.last.used, isFalse);
    });

    test('hormonal contraception reads with a bleed and no phase', () {
      final answer = parseCycleAnswer(
        _fixture('my_cycle_v1_0_contraception.json'),
      );
      expect(answer.status, CycleStatus.hormonalContraception);
      expect(answer.state.periodDay, 2);
      expect(answer.state.phase, isNull);
      expect(answer.state.weightWaterWindow, isTrue);
      expect(answer.recentDays, hasLength(2));
      expect(answer.cycles, isEmpty);
    });

    test('a 1.x answer from a later minor version still reads', () {
      final answer = parseCycleAnswer({
        ..._fixture('my_cycle_v1_0_regular.json'),
        'schema_version': '1.3',
        'future_key': true,
      });
      expect(answer.status, CycleStatus.regular);
    });

    test('an unreadable answer is refused, never read as off', () {
      Map<String, dynamic> with_(void Function(Map<String, dynamic>) edit) {
        final copy = _copy(_fixture('my_cycle_v1_0_regular.json'));
        edit(copy);
        return copy;
      }

      for (final bad in <Object?>[
        null,
        'regular',
        <String, dynamic>{},
        with_((m) => m['schema_version'] = '2.0'),
        with_((m) => m['schema_version'] = 1.0),
        with_((m) => m.remove('state')),
        with_((m) => m.remove('recent_days')),
        with_((m) => m.remove('cycles')),
        with_((m) => m['tracking_enabled'] = 'yes'),
        with_((m) => m['tracking_enabled'] = null),
        with_((m) => m['status'] = 'sometimes'),
        with_((m) => m['typical_cycle_days'] = 14),
        with_((m) => m['typical_cycle_days'] = 61),
        with_((m) => m['typical_cycle_days'] = '28'),
        with_((m) => (m['state'] as Map)['phase'] = 'luteal'),
        with_((m) => (m['state'] as Map)['confidence'] = 'certain'),
        with_((m) => (m['state'] as Map)['expected_from'] = '8 Dec'),
        with_((m) => (m['state'] as Map)['expected_to'] = '2026-13-40'),
        with_((m) => (m['state'] as Map)['no_period_long'] = null),
        with_((m) => (m['state'] as Map)['cycle_day'] = '18'),
        with_((m) => _first(m, 'recent_days')['flow'] = 'torrential'),
        with_((m) => _first(m, 'recent_days')['source'] = 'watch'),
        with_((m) => _first(m, 'recent_days')['source'] = null),
        with_((m) => _first(m, 'recent_days')['local_date'] = null),
        with_((m) => _first(m, 'recent_days')['is_start'] = 1),
        with_((m) => _first(m, 'cycles')['used'] = null),
        with_((m) => _first(m, 'cycles')['start_date'] = 'Oct 13'),
        with_((m) => m['cycles'] = 'none'),
      ]) {
        expect(
          () => parseCycleAnswer(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('an import answer reads, and a changed one is refused', () {
      final result = parseCycleImport({
        'schema_version': '1.0',
        'imported': 4,
        'removed': 1,
      });
      expect(result.imported, 4);
      expect(result.removed, 1);
      for (final bad in <Object?>[
        null,
        {'imported': 4, 'removed': 1},
        {'schema_version': '2.0', 'imported': 4, 'removed': 1},
        {'schema_version': '1.0', 'imported': 4},
        {'schema_version': '1.0', 'imported': '4', 'removed': 1},
        {'schema_version': '1.0', 'imported': -1, 'removed': 1},
      ]) {
        expect(
          () => parseCycleImport(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('the enum codes match the database values', () {
      expect(CycleStatus.values.map((v) => v.code), [
        'regular',
        'irregular',
        'hormonal_contraception',
        'no_periods',
      ]);
      expect(PeriodFlow.values.map((v) => v.code), [
        'spotting',
        'light',
        'medium',
        'heavy',
        'unspecified',
      ]);
      expect(CycleCramps.values.map((v) => v.code), ['none', 'mild', 'strong']);
      expect(CyclePhase.values.map((v) => v.code), [
        'period',
        'first_half',
        'second_half',
      ]);
      expect(CycleConfidence.values.map((v) => v.code), [
        'low',
        'medium',
        'high',
      ]);
      expect(CycleSource.values.map((v) => v.code), ['manual', 'apple_health']);
      expect(CycleConsent.type, 'cycle_data');
      expect(CycleConsent.noticeVersion, '2026-11-27');
    });
  });
}
