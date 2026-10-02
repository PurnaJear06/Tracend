import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/progress/physique_check_repository.dart';

Map<String, dynamic> _loadFixtureJson(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  final parsed = json.decode(file.readAsStringSync());
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('Contract fixture "$name" must be a JSON object');
  }
  return parsed;
}

void main() {
  group('Physique check contract — physique-check v1.0', () {
    test('a check response parses into priorities, notes and issues', () {
      final json = _loadFixtureJson('physique_check_response_v1_0.json');
      expect(json['schema_version'], '1.0');
      expect(json['analysis_id'], isA<String>());
      final result = PhysiqueCheckResult.fromJson(json['result'])!;
      expect(result.priorities.map((p) => p.muscle), ['chest', 'calves']);
      expect(result.priorities.map((p) => p.confidence), ['medium', 'low']);
      expect(result.observations, hasLength(1));
      expect(result.photoIssues, ['lighting']);
      expect(result.limitations, isNotEmpty);
    });
  });

  group('Photo AI notice contract — get_my_photo_ai_notice v1.0', () {
    test('the notice parses with its version, provider and paragraphs', () {
      final json = _loadFixtureJson('photo_ai_notice_v1_0.json');
      expect(json['schema_version'], '1.0');
      final notice = PhotoAiNotice.fromJson(json)!;
      expect(notice.version, 'progress-photo-ai-v1');
      expect(notice.providerLabel, 'Groq');
      expect(notice.model, 'qwen/qwen3.8-27b');
      expect(notice.paragraphs, hasLength(2));
      expect(notice.granted, isFalse);
    });
  });
}
