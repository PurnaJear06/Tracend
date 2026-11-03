import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/feedback/feedback_rating.dart';

Map<String, dynamic> _fixture(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  return Map<String, dynamic>.from(json.decode(file.readAsStringSync()) as Map);
}

void main() {
  group('Feedback contract: submit_feedback_rating_v1 1.0', () {
    // The key list is the contract: add keys, never remove or rename them.
    // supabase/tests/database/feedback_ratings_test.sql asserts the same list
    // against the database.
    test('the response carries exactly the contract keys', () {
      final fixture = _fixture('feedback_rating_v1_0.json');

      expect(fixture['schema_version'], '1.0');
      expect(fixture.keys.toList()..sort(), [
        'rating',
        'schema_version',
        'subject_id',
        'subject_type',
      ]);
    });

    test('the fixture names a subject type and rating the app sends', () {
      final fixture = _fixture('feedback_rating_v1_0.json');

      expect(
        FeedbackSubject.values.map((subject) => subject.wire),
        contains(fixture['subject_type']),
      );
      expect(
        FeedbackRating.values.map((rating) => rating.name),
        contains(fixture['rating']),
      );
    });
  });
}
