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
  group('Coach Chat contract — coach-chat Edge Function response', () {
    const fixture = 'coach_chat_response.json';

    test('fixture is valid JSON and has message envelope', () {
      final json = _loadFixtureJson(fixture);

      expect(json['message'], isA<Map>());
    });

    test('message shape matches SupabaseCoachRepository._messageFromJson parsing', () {
      final json = _loadFixtureJson(fixture);
      final message = Map<String, dynamic>.from(json['message'] as Map);

      // Exact field checks matching _messageFromJson in coach_repository.dart
      expect(message['id'], isA<String>());
      expect(message['role'], isA<String>());
      expect(message['content'] ?? message['answer'], isA<String>());
      expect(message['created_at'], isA<String>());

      // Evidence
      expect(message['evidence'], isA<List>());
      for (final item in (message['evidence'] as List).cast<Map<String, dynamic>>()) {
        expect(item['code'], isA<String>());
        expect(item['label'], isA<String>());
        expect(item['source'], isA<String>());
        expect(
          ['feature_snapshot', 'policy_evaluation', 'coach_context'],
          contains(item['source'] as String),
        );
      }

      // Missing data
      expect(message['missing_data'], isA<List>());
      for (final item in (message['missing_data'] as List)) {
        expect(item, isA<String>());
      }

      // Safety
      expect(message['safety_state'], isA<String>());
      expect(
        ['allowed', 'limited', 'refused', 'unavailable'],
        contains(message['safety_state'] as String),
      );

      // Follow-ups
      expect(message['suggested_follow_ups'], isA<List>());
      for (final item in (message['suggested_follow_ups'] as List)) {
        expect(item, isA<String>());
      }
    });

    test('message includes provider metadata when present', () {
      final json = _loadFixtureJson(fixture);
      final message = Map<String, dynamic>.from(json['message'] as Map);

      // Optional but expected in live responses
      if (message.containsKey('model_provider')) {
        expect(message['model_provider'], isA<String>());
      }
      if (message.containsKey('model')) {
        expect(message['model'], isA<String>());
      }
    });

    test('reasoning_chain is parseable when present', () {
      final json = _loadFixtureJson(fixture);
      final message = Map<String, dynamic>.from(json['message'] as Map);

      if (message.containsKey('reasoning_chain') && message['reasoning_chain'] != null) {
        final chain = message['reasoning_chain'] as List;
        for (final item in chain.cast<Map<String, dynamic>>()) {
          expect(item['step'], isA<String>());
          expect(item['value'], isA<String>());
          // evidence_id may be null
        }
      }
    });
  });
}
