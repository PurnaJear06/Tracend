import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
      as Map,
);

void main() {
  group('record_screening_v1 1.0', () {
    final json = _fixture('record_screening_v1_0');

    test('carries its schema version and complete key list', () {
      expect(json.keys.toSet(), {'schema_version', 'outcome', 'screened_at'});
      expect(json['schema_version'], '1.0');
    });

    test('reads the outcome and the date', () {
      final record = ScreeningRecord.fromJson(json);
      expect(record.outcome, ScreeningOutcome.moderateUntilCleared);
      expect(record.screenedAt.toUtc().year, 2026);
    });

    test('every Contract 8 outcome has a wire value and reads back', () {
      expect(ScreeningOutcome.values.map((outcome) => outcome.wire), [
        'cleared',
        'moderate_until_cleared',
        'see_professional',
      ]);
      for (final outcome in ScreeningOutcome.values) {
        expect(ScreeningOutcome.fromWire(outcome.wire), outcome);
      }
    });

    test('an unknown outcome or a missing date is refused, never cleared', () {
      expect(
        () => ScreeningRecord.fromJson({...json, 'outcome': 'fine'}),
        throwsFormatException,
      );
      expect(
        () => ScreeningRecord.fromJson({'outcome': 'cleared'}),
        throwsFormatException,
      );
      expect(() => ScreeningRecord.fromJson(null), throwsFormatException);
    });
  });

  group('screening answers', () {
    test('send the keys the database and the draft read', () {
      const answers = ScreeningAnswers(
        exercisesRegularly: true,
        knownCondition: true,
        symptoms: false,
        clearedByProfessional: false,
      );
      expect(answers.toJson(), {
        'exercises_regularly': true,
        'known_disease': true,
        'symptoms': false,
        'cleared_by_professional': false,
      });
    });

    test('read back from a draft, with clearance defaulting to no', () {
      final answers = ScreeningAnswers.fromJson({
        'exercises_regularly': false,
        'known_disease': false,
        'symptoms': false,
      });
      expect(answers?.clearedByProfessional, isFalse);
      expect(answers?.exercisesRegularly, isFalse);
    });

    test('an older draft or a damaged one has none', () {
      expect(ScreeningAnswers.fromJson(null), isNull);
      expect(ScreeningAnswers.fromJson('yes'), isNull);
      expect(
        ScreeningAnswers.fromJson({
          'exercises_regularly': true,
          'known_disease': 'no',
          'symptoms': false,
        }),
        isNull,
      );
    });
  });
}
