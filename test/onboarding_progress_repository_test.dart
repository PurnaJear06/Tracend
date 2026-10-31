import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/onboarding/onboarding_repository.dart';
import 'package:tracend/features/onboarding/onboarding_screening.dart';
import 'package:tracend/features/progress/progress_repository.dart';

const _url = 'https://tracend-test.supabase.co';
const _userId = '11111111-1111-4111-8111-111111111111';

/// Scripted Supabase endpoints keyed by `METHOD /path`, recording every
/// request with its query.
class _Server {
  final requests = <String>[];
  final routes = <String, Future<http.Response> Function()>{};

  late final client = SupabaseClient(
    _url,
    'publishable-test',
    httpClient: MockClient((request) async {
      final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
      requests.add('${request.method} ${request.url.path}$query');
      final handler = routes['${request.method} ${request.url.path}'];
      final response = handler == null
          ? _json(404, {'message': 'no route'})
          : await handler();
      return http.Response(
        response.body,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  void answer(String route, int status, Object body) =>
      routes[route] = () async => _json(status, body);

  /// A route that never answers.
  void hang(String route) =>
      routes[route] = () => Completer<http.Response>().future;

  Future<void> signIn() {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(hours: 1));
    final token = [
      part({'alg': 'HS256', 'typ': 'JWT'}),
      part({'sub': _userId, 'exp': exp.millisecondsSinceEpoch ~/ 1000}),
      'test-signature',
    ].join('.');
    return client.auth.setInitialSession(
      jsonEncode({
        'access_token': token,
        'expires_in': 3600,
        'refresh_token': 'refresh-test',
        'token_type': 'bearer',
        'user': {
          'id': _userId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'athlete@tracend.test',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-10-01T00:00:00Z',
        },
      }),
    );
  }
}

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {
    'content-type': 'application/json',
    'x-supabase-api-version': '2024-01-01',
  },
);

void main() {
  group('onboarding repository', () {
    late _Server server;
    late SupabaseOnboardingRepository repository;

    setUp(() async {
      server = _Server();
      await server.signIn();
      repository = SupabaseOnboardingRepository(
        server.client,
        callTimeout: const Duration(milliseconds: 50),
      );
    });

    test(
      'saving a draft writes the draft and nothing on the account',
      () async {
        server.answer('POST /rest/v1/onboarding_drafts', 201, <Object>[]);

        await repository.saveDraft(
          path: 'beginner',
          currentSection: 'goal',
          payload: {'goal': 'strength'},
        );

        // The database moves the account to in_progress; the app can no longer
        // write that column.
        expect(
          server.requests.where(
            (request) => request.contains('/user_accounts'),
          ),
          isEmpty,
        );
        expect(server.requests, hasLength(1));
        expect(
          server.requests.single,
          startsWith('POST /rest/v1/onboarding_drafts'),
        );
      },
    );

    test('a call that never answers ends instead of saving for good', () async {
      server
        ..hang('GET /rest/v1/onboarding_drafts')
        ..hang('GET /rest/v1/user_accounts')
        ..hang('POST /rest/v1/onboarding_drafts')
        ..hang('POST /rest/v1/rpc/record_screening_v1')
        ..hang('POST /rest/v1/rpc/get_my_screening_v1')
        ..hang('POST /rest/v1/rpc/get_my_onboarding_generation');

      await expectLater(
        repository.loadDraft(),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        repository.isOnboardingComplete(),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        repository.saveDraft(
          path: 'beginner',
          currentSection: 'goal',
          payload: {},
        ),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        repository.recordScreening(
          const ScreeningAnswers(
            exercisesRegularly: true,
            knownCondition: false,
            symptoms: false,
            clearedByProfessional: false,
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        repository.loadScreening(),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        repository.loadGeneration(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a call that answers in time is untouched', () async {
      server.answer('POST /rest/v1/rpc/get_my_screening_v1', 200, {
        'schema_version': '1.0',
        'screened': false,
        'outcome': 'cleared',
      });
      final stored = await repository.loadScreening();
      expect(stored.outcome, ScreeningOutcome.cleared);
      expect(stored.answers, isNull);
    });
  });

  group('progress repository', () {
    late _Server server;
    late SupabaseProgressRepository repository;

    setUp(() async {
      server = _Server();
      await server.signIn();
      repository = SupabaseProgressRepository(server.client);
    });

    test(
      'photo sets are capped and their photos read for those sets only',
      () async {
        server
          ..answer('GET /rest/v1/progress_photo_sets', 200, [
            {'id': 'set-1', 'captured_on': '2026-10-30', 'status': 'complete'},
            {'id': 'set-2', 'captured_on': '2026-10-01', 'status': 'draft'},
          ])
          ..answer('GET /rest/v1/progress_photos', 200, [
            {
              'photo_set_id': 'set-1',
              'media_objects': {'object_key': 'u/progress/set-1/front.jpg'},
            },
          ]);

        final sets = await repository.loadPhotoSets();

        expect(sets.map((set) => set.id), ['set-1', 'set-2']);
        expect(sets.first.objectKeys, ['u/progress/set-1/front.jpg']);
        expect(server.requests.first, contains('limit=100'));
        expect(
          Uri.decodeQueryComponent(server.requests.last),
          contains('photo_set_id=in.("set-1","set-2")'),
        );
      },
    );

    test('with no sets there is no photo read', () async {
      server.answer('GET /rest/v1/progress_photo_sets', 200, <Object>[]);
      expect(await repository.loadPhotoSets(), isEmpty);
      expect(server.requests, hasLength(1));
    });

    ProgressPhotoSet set(List<String> keys) => ProgressPhotoSet(
      id: 'set-1',
      date: DateTime(2026, 10, 30),
      status: 'complete',
      objectKeys: keys,
    );

    test('deleting a set removes its rows before its files', () async {
      server
        ..answer('POST /rest/v1/rpc/delete_my_progress_photo_set', 200, true)
        ..answer('DELETE /storage/v1/object/progress-photos', 200, <Object>[]);

      await repository.deletePhotoSet(set(['u/progress/set-1/front.jpg']));

      expect(server.requests, [
        'POST /rest/v1/rpc/delete_my_progress_photo_set',
        'DELETE /storage/v1/object/progress-photos',
      ]);
    });

    test(
      'a file that will not go is left to the sweep, not reported',
      () async {
        server
          ..answer('POST /rest/v1/rpc/delete_my_progress_photo_set', 200, true)
          ..answer('DELETE /storage/v1/object/progress-photos', 500, {
            'message': 'down',
          });
        await repository.deletePhotoSet(set(['u/progress/set-1/front.jpg']));
        expect(server.requests, hasLength(2));
      },
    );

    test('rows that cannot be deleted leave the files alone', () async {
      server.answer('POST /rest/v1/rpc/delete_my_progress_photo_set', 500, {
        'message': 'down',
      });
      await expectLater(
        repository.deletePhotoSet(set(['u/progress/set-1/front.jpg'])),
        throwsA(isA<PostgrestException>()),
      );
      expect(server.requests, hasLength(1));
    });

    test('a set with no photos needs no storage call', () async {
      server.answer(
        'POST /rest/v1/rpc/delete_my_progress_photo_set',
        200,
        true,
      );
      await repository.deletePhotoSet(set(const []));
      expect(server.requests, hasLength(1));
    });

    test('photo storage consent is read from the newest record', () async {
      server.answer('GET /rest/v1/consent_records', 200, {'action': 'granted'});
      expect(await repository.hasPhotoStorageConsent(), isTrue);
      expect(
        server.requests.single,
        contains('consent_type=eq.progress_photo_storage'),
      );
      expect(server.requests.single, contains('order=created_at.desc'));

      server.answer('GET /rest/v1/consent_records', 200, {
        'action': 'withdrawn',
      });
      expect(await repository.hasPhotoStorageConsent(), isFalse);
    });
  });
}
