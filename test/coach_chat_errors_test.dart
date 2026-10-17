import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/coach/coach_screen.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/coach/widgets/coach_message_bubble.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

/// Coach chat failures (A9): coach-chat answers errors with a non-2xx status,
/// which functions_client throws as an exception, so each error code reaches
/// the athlete as a plain sentence, with the raw diagnostic beneath it.

final _now = DateTime.utc(2026, 10, 17, 12);

String get _monthlyReset =>
    shortDate(DateTime.utc(2026, 11).toLocal(), now: _now);

final _monthlyLimit =
    'You’ve reached this month’s Coach limit. It resets on $_monthlyReset.';
final _dailyLimit = RegExp(
  r'^You’ve used all 30 of today’s Coach messages\. The limit resets at '
  r'\d{1,2}:\d{2} (am|pm) (today|tomorrow)\.$',
);
const _tryAgain = 'Please try again in a moment.';

typedef _Expected = ({
  Object message,
  bool retryable,
  bool sameKey,
  bool consent,
  String diagnostic,
});

_Expected _expect(
  Object message, {
  required String diagnostic,
  bool retryable = true,
  bool sameKey = false,
  bool consent = false,
}) => (
  message: message,
  retryable: retryable,
  sameKey: sameKey,
  consent: consent,
  diagnostic: diagnostic,
);

/// What the athlete reads for every response in the error fixture.
final Map<String, _Expected> _cases = {
  'usage_limit': _expect(
    'Coach has reached its usage limit for now. Please try again later.',
    diagnostic: 'Beta diagnostic: HTTP 429 · ai_usage_limit',
    retryable: false,
  ),
  'usage_limit_monthly_reason': _expect(
    _monthlyLimit,
    diagnostic:
        'Beta diagnostic: HTTP 429 · ai_usage_limit · monthly_cost_limit',
    retryable: false,
  ),
  'consent_required': _expect(
    'Coach needs your permission to use AI before it can answer. Review AI '
    'coaching, then ask again.',
    diagnostic: 'Beta diagnostic: HTTP 403 · ai_consent_required',
    retryable: false,
    consent: true,
  ),
  'consent_unavailable': _expect(
    'Coach couldn’t check your AI coaching setting just now. $_tryAgain',
    diagnostic: 'Beta diagnostic: HTTP 503 · ai_consent_unavailable',
  ),
  'session_expired': _expect(
    'Your session has expired. Sign in again to keep talking to Coach.',
    diagnostic: 'Beta diagnostic: HTTP 401 · invalid_session',
    retryable: false,
  ),
  'request_in_progress': _expect(
    'Coach is still working on your last message. Give it a few seconds, '
    'then retry.',
    diagnostic:
        'Beta diagnostic: HTTP 409 · chat_in_progress · request_in_progress',
    sameKey: true,
  ),
  'daily_rate_limit': _expect(
    RegExp(
      r'^You’ve used all of today’s Coach messages\. The limit resets at '
      r'\d{1,2}:\d{2} (am|pm) (today|tomorrow)\.$',
    ),
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · daily_rate_limit',
    retryable: false,
  ),
  'monthly_cost_limit': _expect(
    _monthlyLimit,
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · monthly_cost_limit',
    retryable: false,
  ),
  'approved_plan_required': _expect(
    'Coach needs an approved plan to look at. Finish setting up your plan in '
    'Train, then ask again.',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · approved_plan_required',
    retryable: false,
  ),
  'thread_not_found': _expect(
    'That conversation is no longer available. Start a new one.',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · thread_not_found',
    retryable: false,
  ),
  'invalid_chat_request_reason': _expect(
    'Coach couldn’t read that message. Shorten it and send it again.',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · invalid_chat_request',
    retryable: false,
  ),
  'account_not_found': _expect(
    'Coach couldn’t find your account. Sign out and back in, then try again.',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · account_not_found',
    retryable: false,
  ),
  'invalid_timezone': _expect(
    'Coach doesn’t recognise your time zone. Check it in Account, then try '
    'again.',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · invalid_timezone',
    retryable: false,
  ),
  'chat_context_too_large': _expect(
    'This conversation has grown too long for Coach to read. Start a new one.',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · chat_context_too_large',
    retryable: false,
  ),
  'unknown_preparation_failure': _expect(
    'Coach couldn’t prepare your data just now. $_tryAgain',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_unavailable · '
        'context_preparation_failed · sqlstate_XX000',
  ),
  'invalid_chat_request': _expect(
    'Coach couldn’t read that message. Shorten it and send it again.',
    diagnostic: 'Beta diagnostic: HTTP 422 · invalid_chat_request',
    retryable: false,
  ),
  'persistence_rejected': _expect(
    'Coach’s answer couldn’t be saved. Please try again.',
    diagnostic:
        'Beta diagnostic: HTTP 422 · chat_rejected · persistence_rejected',
  ),
  'provider_timeout': _expect(
    'Coach took too long to respond. Please try again.',
    diagnostic:
        'Beta diagnostic: HTTP 503 · chat_unavailable · provider_timeout',
  ),
  'provider_rate_limited': _expect(
    'Coach is busy right now. $_tryAgain',
    diagnostic:
        'Beta diagnostic: HTTP 503 · chat_unavailable · provider_rate_limited',
  ),
  'provider_response_invalid': _expect(
    'Coach couldn’t complete that response. Please try again.',
    diagnostic:
        'Beta diagnostic: HTTP 503 · chat_unavailable · '
        'provider_response_invalid',
  ),
  'provider_http_error': _expect(
    'Coach is unavailable right now. Your approved plan is unchanged.',
    diagnostic:
        'Beta diagnostic: HTTP 503 · chat_unavailable · provider_http_error',
  ),
  'gateway_timeout': _expect(
    'Coach took too long to answer. Retry will pick up the answer if it '
    'finished in the meantime.',
    diagnostic: 'Beta diagnostic: HTTP 546 · upstream timed out',
    sameKey: true,
  ),
};

Map<String, ({int status, Object? body})> _fixture() {
  final json =
      jsonDecode(
            File(
              'test/contract/fixtures/coach_chat_error_responses_v1.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return {
    for (final entry in (json['cases'] as Map<String, dynamic>).entries)
      entry.key: (
        status: (entry.value as Map)['status'] as int,
        body: (entry.value as Map)['body'],
      ),
  };
}

FunctionsHttpException _http(({int status, Object? body}) response) =>
    FunctionsHttpException(status: response.status, details: response.body);

void _expectMessage(String actual, Object expected) {
  if (expected is RegExp) {
    expect(actual, matches(expected));
  } else {
    expect(actual, expected);
  }
}

/// A Supabase project whose coach-chat answers with a scripted status and
/// body, and whose requests the test can read.
class _Server {
  _Server({
    this.status = 200,
    this.body = const <String, dynamic>{},
    this.budget = const <String, dynamic>{},
    this.offline = false,
  });

  int status;
  Object? body;
  Map<String, dynamic> budget;
  bool offline;
  final chatBodies = <Map<String, dynamic>>[];

  late final client = SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient((request) async {
      http.Response json(Object value, [int code = 200]) => http.Response(
        jsonEncode(value),
        code,
        headers: {'content-type': 'application/json'},
        request: request,
      );
      switch (request.url.path) {
        case '/rest/v1/user_accounts':
          return json({'timezone': 'Asia/Kolkata'});
        case '/rest/v1/rpc/get_my_ai_budget_state':
          return json(budget);
        case '/functions/v1/coach-chat':
          if (offline) throw http.ClientException('offline');
          chatBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return body is String
              ? http.Response(
                  body! as String,
                  status,
                  headers: {'content-type': 'text/plain'},
                  request: request,
                )
              : json(body!, status);
      }
      return json({}, 404);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

const _threadId = '11111111-1111-4111-8111-111111111111';

void main() {
  group('Coach chat failures reach the athlete as plain sentences', () {
    final fixture = _fixture();

    test('the fixture and the expectations cover the same responses', () {
      expect(fixture.keys.toSet(), _cases.keys.toSet());
    });

    for (final entry in _cases.entries) {
      test('${entry.key} maps to its sentence', () {
        final expected = entry.value;
        final failure = coachChatFailure(_http(fixture[entry.key]!), now: _now);
        _expectMessage(failure.message, expected.message);
        expect(failure.retryable, expected.retryable);
        expect(failure.retrySameKey, expected.sameKey);
        expect(failure.needsConsent, expected.consent);
        expect(failure.betaDiagnostic, expected.diagnostic);
        expect(failure.message, isNot(contains('Exception')));
        expect(failure.message, isNot(contains('{')));
      });
    }

    test('the retry delay of a busy provider is kept for the cooldown', () {
      final failure = coachChatFailure(
        _http(fixture['provider_rate_limited']!),
        now: _now,
      );
      expect(failure.retryAfterSeconds, 3);
      expect(
        coachChatFailure(
          _http(fixture['provider_timeout']!),
          now: _now,
        ).retryAfterSeconds,
        isNull,
      );
    });

    test('a 429 names the limit from the athlete’s budget state', () {
      final monthly = coachChatFailure(
        _http(fixture['usage_limit']!),
        now: _now,
        budget: {'blocked': true, 'today_requests': 4, 'daily_limit': 30},
      );
      expect(monthly.message, _monthlyLimit);
      final daily = coachChatFailure(
        _http(fixture['usage_limit']!),
        now: _now,
        budget: {'blocked': false, 'today_requests': 30, 'daily_limit': 30},
      );
      expect(daily.message, matches(_dailyLimit));
      final neither = coachChatFailure(
        _http(fixture['usage_limit']!),
        now: _now,
        budget: {'blocked': false, 'today_requests': 3, 'daily_limit': 30},
      );
      expect(neither.message, contains('usage limit for now'));
    });

    test('the monthly reset is the first of next month, 00:00 UTC', () {
      expect(
        coachMonthlyReset(DateTime.utc(2026, 10, 17, 12)),
        DateTime.utc(2026, 11),
      );
      expect(
        coachMonthlyReset(DateTime.utc(2026, 12, 31, 23)),
        DateTime.utc(2027),
      );
      expect(
        coachDailyReset(DateTime.utc(2026, 10, 31, 23)),
        DateTime.utc(2026, 11),
      );
    });

    test('a timeout and a lost connection can be retried safely', () {
      final timeout = coachChatFailure(
        TimeoutException('slow', const Duration(seconds: 45)),
        now: _now,
      );
      expect(timeout.retrySameKey, isTrue);
      expect(timeout.message, startsWith('Coach took too long to answer.'));
      expect(
        timeout.betaDiagnostic,
        startsWith('Beta diagnostic: app timeout'),
      );
      final offline = coachChatFailure(
        const FunctionsFetchException(details: 'offline'),
        now: _now,
      );
      expect(offline.retrySameKey, isTrue);
      expect(offline.message, contains('can’t reach Coach'));
    });

    test('an error the app does not know keeps its raw text visible', () {
      final failure = coachChatFailure(StateError('boom'), now: _now);
      expect(
        failure.message,
        'Coach couldn’t answer. Your approved plan is unchanged.',
      );
      expect(failure.betaDiagnostic, 'boom');
      expect(failure.retrySameKey, isFalse);
    });
  });

  group('SupabaseCoachRepository.sendMessage', () {
    final fixture = _fixture();

    for (final name in _cases.keys.where((name) => name != 'usage_limit')) {
      test(
        '$name arrives as a Coach failure, not a generic exception',
        () async {
          final response = fixture[name]!;
          final server = _Server(status: response.status, body: response.body);
          final repository = SupabaseCoachRepository(
            server.client,
            now: () => _now,
          );
          await expectLater(
            repository.sendMessage(_threadId, 'How am I doing?'),
            throwsA(
              isA<CoachUnavailableException>()
                  .having(
                    (e) => e.betaDiagnostic,
                    'diagnostic',
                    _cases[name]!.diagnostic,
                  )
                  .having(
                    (e) => e.retryable,
                    'retryable',
                    _cases[name]!.retryable,
                  ),
            ),
          );
        },
      );
    }

    test('a 429 reads the budget state to say which limit', () async {
      final response = fixture['usage_limit']!;
      final server = _Server(
        status: response.status,
        body: response.body,
        budget: {
          'schema_version': '1.0',
          'blocked': true,
          'today_requests': 2,
          'daily_limit': 30,
        },
      );
      final repository = SupabaseCoachRepository(
        server.client,
        now: () => _now,
      );
      await expectLater(
        repository.sendMessage(_threadId, 'How am I doing?'),
        throwsA(
          isA<CoachUnavailableException>().having(
            (e) => e.message,
            'message',
            _monthlyLimit,
          ),
        ),
      );
    });

    test('a lost connection is a retryable Coach failure', () async {
      final server = _Server(offline: true);
      final repository = SupabaseCoachRepository(
        server.client,
        now: () => _now,
      );
      await expectLater(
        repository.sendMessage(_threadId, 'How am I doing?'),
        throwsA(
          isA<CoachUnavailableException>()
              .having((e) => e.retrySameKey, 'same key', isTrue)
              .having((e) => e.code, 'code', 'offline'),
        ),
      );
    });

    test(
      'a retry repeats the key it was given; a new question gets a new one',
      () async {
        final server = _Server(
          body: {
            'message': {
              'id': 'm1',
              'role': 'assistant',
              'created_at': '2026-10-17T12:00:00Z',
              'answer': 'Keep going.',
            },
            'budget_warning': true,
          },
        );
        final repository = SupabaseCoachRepository(
          server.client,
          now: () => _now,
        );
        final first = await repository.sendMessage(
          _threadId,
          'How am I doing?',
          idempotencyKey: 'key-1',
        );
        await repository.sendMessage(
          _threadId,
          'How am I doing?',
          idempotencyKey: 'key-1',
        );
        await repository.sendMessage(_threadId, 'Another question');
        await repository.sendMessage(_threadId, 'Another question');
        final keys = [
          for (final body in server.chatBodies) body['idempotency_key'],
        ];
        expect(keys[0], 'key-1');
        expect(keys[1], 'key-1');
        expect(keys[2], isNot('key-1'));
        expect(keys[3], isNot(keys[2]));
        expect(first.nearBudgetLimit, isTrue);
      },
    );
  });

  group('Coach screen', () {
    Future<void> tall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
    }

    Widget app(CoachRepository repository) => MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(
        body: CoachScreen(repository: repository, threadMemory: _NoMemory()),
      ),
    );

    Future<void> ask(WidgetTester tester, String question) async {
      await tester.enterText(find.byType(TextField), question);
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
    }

    final fixture = _fixture();

    for (final entry in _cases.entries) {
      testWidgets('${entry.key} shows its sentence, diagnostic and actions', (
        tester,
      ) async {
        await tall(tester);
        final expected = entry.value;
        final repository = _ScriptedRepository([
          coachChatFailure(_http(fixture[entry.key]!), now: _now),
        ]);
        await tester.pumpWidget(app(repository));
        await tester.pumpAndSettle();
        await ask(tester, 'How am I doing?');

        final card = find.byType(CoachTurnError);
        expect(card, findsOneWidget);
        final message = tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .map((text) => text.data ?? '')
            .toList();
        if (expected.message is RegExp) {
          expect(
            message.any((line) => (expected.message as RegExp).hasMatch(line)),
            isTrue,
            reason: '$message',
          );
        } else {
          expect(message, contains(expected.message));
        }
        expect(
          find.descendant(of: card, matching: find.text(expected.diagnostic)),
          findsOneWidget,
        );
        // A retry is offered only where asking again can help; a busy
        // provider with a delay waits out its cooldown first.
        final delayed = entry.key == 'provider_rate_limited';
        expect(
          find.descendant(of: card, matching: find.text('Retry')),
          expected.retryable && !delayed ? findsOneWidget : findsNothing,
        );
        await tester.pumpAndSettle(TracendToast.visibleFor);
        if (delayed) await tester.pump(const Duration(seconds: 4));
      });
    }

    testWidgets('a refusal for consent offers to review AI coaching', (
      tester,
    ) async {
      await tall(tester);
      final repository = _ScriptedRepository([
        coachChatFailure(_http(fixture['consent_required']!), now: _now),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: CoachScreen(
              repository: repository,
              threadMemory: _NoMemory(),
              aiConsent: _grantedConsent(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'How am I doing?');

      expect(find.text('Review AI coaching'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets('a busy provider’s delay becomes a working cooldown', (
      tester,
    ) async {
      await tall(tester);
      final repository = _ScriptedRepository([
        coachChatFailure(_http(fixture['provider_rate_limited']!), now: _now),
        _answer('Here is my take.'),
      ]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await ask(tester, 'How am I doing?');

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        startsWith('Coach is busy. Try again in'),
      );
      expect(find.text('Retry'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle(TracendToast.visibleFor);

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Here is my take.'), findsOneWidget);
    });

    testWidgets('Retry after a timeout repeats the key and does not duplicate '
        'the question', (tester) async {
      await tall(tester);
      final timeout = coachChatFailure(
        TimeoutException('slow', const Duration(seconds: 45)),
        now: _now,
      );
      final repository = _ScriptedRepository([timeout, _answer('Done.')]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await ask(tester, 'How am I doing?');
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.keys.length, 2);
      expect(repository.keys[1], repository.keys[0]);
      expect(find.text('Done.'), findsOneWidget);
      expect(find.text('How am I doing?'), findsOneWidget);
      expect(find.byType(CoachTurnError), findsNothing);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets('Retry after the server answered with a failure is a new '
        'turn', (tester) async {
      await tall(tester);
      final repository = _ScriptedRepository([
        coachChatFailure(
          _http(fixture['provider_response_invalid']!),
          now: _now,
        ),
        _answer('Done.'),
      ]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await ask(tester, 'How am I doing?');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.keys.length, 2);
      expect(repository.keys[1], isNot(repository.keys[0]));
      expect(find.text('How am I doing?'), findsOneWidget);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets('a key is repeated twice at most, so a lost turn cannot trap '
        'Retry', (tester) async {
      await tall(tester);
      final stillWorking = coachChatFailure(
        _http(fixture['request_in_progress']!),
        now: _now,
      );
      final repository = _ScriptedRepository([
        stillWorking,
        stillWorking,
        stillWorking,
        _answer('Done.'),
      ]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await ask(tester, 'How am I doing?');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
      }

      expect(repository.keys.length, 4);
      expect(repository.keys[1], repository.keys[0]);
      expect(repository.keys[2], repository.keys[0]);
      expect(repository.keys[3], isNot(repository.keys[0]));
      expect(find.text('Done.'), findsOneWidget);
      await tester.pumpAndSettle(TracendToast.visibleFor);
    });

    testWidgets('a reply near the monthly limit carries the warning until a '
        'reply without it', (tester) async {
      await tall(tester);
      final repository = _ScriptedRepository([
        _answer('First.', nearLimit: true),
        _answer('Second.'),
      ]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await ask(tester, 'One');

      expect(
        find.textContaining('approaching this month’s Coach limit'),
        findsOneWidget,
      );
      expect(find.textContaining('It resets on'), findsOneWidget);
      await ask(tester, 'Two');
      expect(find.textContaining('approaching'), findsNothing);
    });

    testWidgets('an athlete without a plan is offered questions that work '
        'without one', (tester) async {
      await tall(tester);
      await tester.pumpWidget(
        app(_ScriptedRepository(const [], planAvailable: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Why don’t I have a plan yet?'), findsOneWidget);
      expect(find.text('What is my next meal?'), findsNothing);
      await tester.tap(find.text('What can you help me with?'));
      await tester.pumpAndSettle();
      // The send is answered (here by a scripted failure) in the same
      // conversation: the screen does not dead-end.
      expect(find.text('What can you help me with?'), findsOneWidget);
    });
  });
}

AiCoachingConsentController _grantedConsent() => AiCoachingConsentController(
  FixtureAiCoachingConsentRepository(AiCoachingChoice.granted),
  initial: AiCoachingChoice.granted,
);

CoachMessage _answer(String text, {bool nearLimit = false}) => CoachMessage(
  id: 'answer-${text.hashCode}',
  role: 'assistant',
  content: text,
  createdAt: DateTime(2026, 10, 17),
  answerSource: 'model',
  nearBudgetLimit: nearLimit,
);

class _NoMemory implements CoachThreadMemory {
  @override
  Future<String?> lastThreadId() async => null;

  @override
  Future<void> remember(String threadId) async {}
}

/// Answers each send with the next scripted outcome and records its key.
class _ScriptedRepository
    implements CoachRepository, CoachChatRepository, CoachContextRepository {
  _ScriptedRepository(List<Object> outcomes, {this.planAvailable = true})
    : _outcomes = List.of(outcomes);

  final List<Object> _outcomes;
  final bool planAvailable;
  final keys = <String?>[];

  @override
  Future<List<CoachContextSource>> loadContextStatus() async => [
    CoachContextSource(
      key: 'approved_plan',
      label: 'Approved training plan',
      available: planAvailable,
      records: 0,
    ),
  ];

  @override
  Future<List<CoachThread>> loadThreads() async => const [];
  @override
  Future<String> createThread() async => 'thread-1';
  @override
  Future<List<CoachMessage>> loadMessages(String threadId) async => const [];

  @override
  Future<CoachMessage> sendMessage(
    String threadId,
    String question, {
    String? idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    if (_outcomes.isEmpty) {
      throw const CoachUnavailableException('Nothing scripted.');
    }
    final outcome = _outcomes.removeAt(0);
    if (outcome is CoachMessage) return outcome;
    throw outcome;
  }

  @override
  Future<void> deleteThread(String threadId) async {}
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async => const {};
}
