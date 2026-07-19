import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadFixtureJson(String name) {
  final file = File('test/contract/fixtures/$name');
  if (!file.existsSync()) {
    throw FileSystemException('Contract fixture not found: $name');
  }
  final raw = file.readAsStringSync();
  final parsed = json.decode(raw);
  if (parsed is! Map<String, dynamic>) {
    throw FormatException('Contract fixture "$name" must be a JSON object');
  }
  return parsed;
}

void main() {
  group('Coach Context contract — get_my_coach_context_status', () {
    const fixture = 'coach_context_status.json';

    test('fixture has expected envelope and sources', () {
      final json = _loadFixtureJson(fixture);

      expect(json['schema_version'], '1.0');
      expect(json['sources'], isA<List>());
    });

    test('each source matches CoachContextSource.fromJson parsing', () {
      final json = _loadFixtureJson(fixture);
      final sources = json['sources'] as List;

      expect(sources, isNotEmpty);

      for (final source in sources.cast<Map<String, dynamic>>()) {
        expect(source['source'], isA<String>());
        expect(source['available'], isA<bool>());
        // latest_date is nullable
        expect(source['count'], isA<num>());
      }
    });
  });
}
