import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/coach/coach_repository.dart';

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

      expect(json['schema_version'], '1.1');
      expect(json['message'], isA<Map>());
    });

    test(
      'failure fixture exposes a safe versioned code without raw detail',
      () {
        final json = _loadFixtureJson('coach_chat_failure_response_v1_1.json');

        expect(json['schema_version'], '1.1');
        expect(json['error'], 'chat_unavailable');
        expect(json['code'], 'provider_response_invalid');
        expect(json.containsKey('detail'), isFalse);
        expect(json.containsKey('provider'), isFalse);
        expect(json.containsKey('model'), isFalse);
        expect(
          jsonEncode(json),
          isNot(contains('Unexpected end of JSON input')),
        );
      },
    );

    test('Flutter maps stable failure codes to safe visible messages', () {
      expect(
        coachChatFailureMessage('provider_response_invalid'),
        'Coach couldn’t complete that response. Please try again.',
      );
      expect(
        coachChatFailureMessage('provider_response_truncated'),
        'Coach couldn’t complete that response. Please try again.',
      );
      expect(
        coachChatFailureMessage('provider_response_empty'),
        'Coach couldn’t complete that response. Please try again.',
      );
      expect(
        coachChatFailureMessage('provider_timeout'),
        'Coach took too long to respond. Please try again.',
      );
      expect(
        coachChatFailureMessage('provider_http_error'),
        'Coach is unavailable right now. Your approved plan is unchanged.',
      );
    });

    test(
      'message shape matches SupabaseCoachRepository._messageFromJson parsing',
      () {
        final json = _loadFixtureJson(fixture);
        final message = Map<String, dynamic>.from(json['message'] as Map);

        // Exact field checks matching _messageFromJson in coach_repository.dart
        expect(message['id'], isA<String>());
        expect(message['role'], isA<String>());
        expect(message['content'] ?? message['answer'], isA<String>());
        expect(message['created_at'], isA<String>());

        // Evidence
        expect(message['evidence'], isA<List>());
        for (final item
            in (message['evidence'] as List).cast<Map<String, dynamic>>()) {
          expect(item['code'], isA<String>());
          expect(item['label'], isA<String>());
          expect(item['source'], isA<String>());
          expect([
            'feature_snapshot',
            'policy_evaluation',
            'coach_context',
          ], contains(item['source'] as String));
        }

        // Missing data
        expect(message['missing_data'], isA<List>());
        for (final item in (message['missing_data'] as List)) {
          expect(item, isA<String>());
        }

        // Safety
        expect(message['safety_state'], isA<String>());
        expect([
          'allowed',
          'limited',
          'refused',
          'unavailable',
        ], contains(message['safety_state'] as String));

        // Follow-ups
        expect(message['suggested_follow_ups'], isA<List>());
        for (final item in (message['suggested_follow_ups'] as List)) {
          expect(item, isA<String>());
        }
      },
    );

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

      if (message.containsKey('reasoning_chain') &&
          message['reasoning_chain'] != null) {
        final chain = message['reasoning_chain'] as List;
        for (final item in chain.cast<Map<String, dynamic>>()) {
          expect(item['step'], isA<String>());
          expect(item['value'], isA<String>());
          // evidence_id may be null
        }
      }
    });
  });

  // The Deno tests read the same request and data-summary fixtures, so the
  // app and coach-chat cannot drift apart.
  group('Coach Chat contract — request 1.1, response 1.2, thread list', () {
    final fallbackCreatedAt = DateTime.utc(2026, 9, 29);

    CoachMessage parse(Map<String, dynamic> row) => CoachMessage.fromJson(
      row,
      fallbackId: 'fallback-id',
      fallbackCreatedAt: fallbackCreatedAt,
    );

    test('the app builds exactly the request 1.1 the server parses', () {
      final fixture = _loadFixtureJson('coach_chat_request_v1_1.json');

      expect(
        coachChatRequestBody(
          threadId: fixture['thread_id'] as String,
          question: '  ${fixture['question']}  ',
          timezone: fixture['timezone'] as String,
          idempotencyKey: fixture['idempotency_key'] as String,
        ),
        fixture,
      );
      expect(coachChatRequestSchemaVersion, '1.1');
    });

    test('a model answer 1.2 is the Coach AI answer', () {
      final json = _loadFixtureJson('coach_chat_response_v1_2.json');
      expect(json['schema_version'], '1.2');
      final message = parse(Map<String, dynamic>.from(json['message'] as Map));

      expect(message.answerSource, 'model');
      expect(message.isDataSummary, isFalse);
      expect(message.diagnostic, isNull);
      expect(message.modelProvider, 'deepseek');
      expect(message.content, startsWith('You are 78.4 kg'));
      expect(message.createdAt, DateTime.utc(2026, 9, 29, 8, 30));
    });

    test('a data summary 1.2 is labeled and carries its diagnostic', () {
      final json = _loadFixtureJson(
        'coach_chat_data_summary_response_v1_2.json',
      );
      expect(json['schema_version'], '1.2');
      final message = parse(Map<String, dynamic>.from(json['message'] as Map));

      expect(message.isDataSummary, isTrue);
      expect(message.isSafetyReferral, isFalse);
      expect(message.modelProvider, 'deterministic');
      expect(message.safetyState, 'unavailable');
      expect(message.suggestedFollowUps, isEmpty);
      expect(message.evidence.single['code'], 'APPROVED_PLAN_ACTIVE');
      expect(message.diagnostic?.failureCode, 'provider_response_invalid');
      expect(message.diagnostic?.initialRule, 'evidence_code_not_permitted');
      expect(message.diagnostic?.repairRule, 'reasoning_step_too_long');
    });

    test('a stored row without answer_source is a model answer', () {
      final message = parse({
        'id': 'stored-1',
        'role': 'assistant',
        'content': 'Stored answer.',
        'created_at': '2026-09-28T07:58:00+00:00',
        'answer_source': null,
      });

      expect(message.answerSource, isNull);
      expect(message.isDataSummary, isFalse);
    });

    test('a stored safety referral is a data summary without a diagnostic', () {
      final message = parse({
        'id': 'stored-2',
        'role': 'assistant',
        'content': 'Please talk to a doctor.',
        'created_at': '2026-09-28T07:58:00+00:00',
        'answer_source': 'data_summary',
        'safety_state': 'limited',
        'evidence': <Object>[],
        'missing_data': <Object>[],
      });

      expect(message.isSafetyReferral, isTrue);
      expect(message.diagnostic, isNull);
    });

    test('the thread list 1.0 lists threads newest first', () {
      final json = _loadFixtureJson('coach_threads_v1_0.json');
      expect(json['schema_version'], '1.0');
      final threads = (json['threads'] as List)
          .map(
            (thread) =>
                CoachThread.fromJson(Map<String, dynamic>.from(thread as Map)),
          )
          .toList();

      expect(threads.map((thread) => thread.id), [
        '5f0f9a2e-3c1b-4d8e-9a6f-2b7c1d4e8f90',
        '9b2d4f6a-1c3e-4a5b-8d7f-0e1a2b3c4d5e',
      ]);
      expect(threads.first.updatedAt, DateTime.utc(2026, 9, 29, 8, 31));
    });
  });
}
