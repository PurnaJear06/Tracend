import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(
  jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync())
      as Map,
);

void main() {
  group('get_my_set_heart_rate_v1 1.0', () {
    final json = _fixture('set_heart_rate_v1_0');
    final report = SetHeartRateReport.fromJson(json);

    test('carries its schema version and complete top-level keys', () {
      expect(json.keys.toSet(), {'schema_version', 'session_id', 'sets'});
      expect(json['schema_version'], '1.0');
    });

    test('each set carries the complete Contract 4 key list', () {
      for (final set in json['sets'] as List) {
        expect((set as Map).keys.toSet(), {
          'exercise_order',
          'set_number',
          'start_bpm',
          'peak_bpm',
          'end_bpm',
          'drop_30s_bpm',
          'drop_60s_bpm',
          'coverage',
          'sample_count',
          'source',
        });
      }
    });

    test('reads the sets by exercise and keeps empty values empty', () {
      expect(report.sets, hasLength(3));
      final first = report.forExercise(1).first;
      expect(first.startBpm, 112);
      expect(first.peakBpm, 148);
      expect(first.endBpm, 141);
      expect(first.drop30sBpm, 14);
      expect(first.drop60sBpm, 27);
      expect(first.coverage, 0.943);
      expect(first.sampleCount, 18);
      expect(first.source, HeartRateSource.watchWorkout);
      expect(report.forExercise(1).last.drop30sBpm, -3);
      expect(report.forExercise(1).last.drop60sBpm, isNull);
      final sparse = report.forExercise(2).single;
      expect(sparse.peakBpm, isNull);
      expect(sparse.source, HeartRateSource.background);
      expect(report.forExercise(3), isEmpty);
    });

    test('an empty or missing list reads as no summaries', () {
      expect(SetHeartRateReport.fromJson(const {}).sets, isEmpty);
      expect(
        SetHeartRateReport.fromJson(const {'sets': <Object?>[]}).sets,
        isEmpty,
      );
    });

    test('a summary round-trips to the keys the save reads', () {
      final summary = report.forExercise(1).first;
      expect(summary.toJson().keys.toSet(), {
        'exercise_order',
        'set_number',
        'start_bpm',
        'peak_bpm',
        'end_bpm',
        'drop_30s_bpm',
        'drop_60s_bpm',
        'coverage',
        'sample_count',
        'source',
      });
      expect(summary.toJson()['source'], 'watch_workout');
    });
  });

  group('persist_set_heart_rate_v1 1.0', () {
    test('carries its schema version and complete key list', () {
      final json = _fixture('persist_set_heart_rate_v1_0');
      expect(json.keys.toSet(), {'schema_version', 'session_id', 'saved'});
      expect(json['schema_version'], '1.0');
      expect(json['saved'], 3);
    });
  });
}
