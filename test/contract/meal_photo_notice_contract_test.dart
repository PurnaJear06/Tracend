import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/consent/photo_ai_notice.dart';

void main() {
  group('Meal photo AI notice contract — get_my_meal_photo_ai_notice v1.0', () {
    test('the notice parses with its version, provider and paragraphs', () {
      final json =
          jsonDecode(
                File(
                  'test/contract/fixtures/meal_photo_ai_notice_v1_0.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(json['schema_version'], '1.0');
      final notice = PhotoAiNotice.fromJson(json)!;
      expect(notice.version, 'meal-photo-ai-v1');
      expect(notice.providerLabel, 'Groq');
      expect(notice.model, 'qwen/qwen3.8-27b');
      expect(notice.paragraphs, hasLength(3));
      expect(notice.granted, isFalse);
    });
  });
}
