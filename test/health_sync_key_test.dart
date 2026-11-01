import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/health/health_data_source.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/workout_hr/heart_rate_reader.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_summary.dart';
import 'package:tracend/shared/diagnostics.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

String _accessToken() {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': _userId, 'exp': exp}),
    'test-signature',
  ].join('.');
}

class _Reader implements HeartRateReader {
  @override
  Future<void> requestAccess() async {}

  @override
  Future<List<HeartRateSample>> readSamples(DateTime from, DateTime to) async =>
      const [];
}

class _Source implements HealthDataSource {
  @override
  Future<bool> requestReadAccess() async => true;

  @override
  Future<HealthReadResult> read(DateTime start, DateTime end) async =>
      const HealthReadResult(
        requestedMetrics: {HealthMetric.steps},
        returnedMetrics: {HealthMetric.steps},
        samples: [],
      );
}

/// A signed-in client whose health-sync answers come from [answer], and the
/// idempotency key of every attempt it receives.
Future<(SupabaseClient, List<String>)> _client(
  http.Response Function(http.Request request) answer,
) async {
  final keys = <String>[];
  final client = SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient((request) async {
      if (request.url.path == '/functions/v1/health-sync') {
        keys.add(
          (jsonDecode(request.body) as Map<String, dynamic>)['idempotency_key']
              as String,
        );
        return answer(request);
      }
      return http.Response('{}', 404, request: request);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': _accessToken(),
      'expires_in': 3600,
      'refresh_token': 'refresh-test',
      'token_type': 'bearer',
      'user': {
        'id': _userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
  return (client, keys);
}

SupabaseHealthRepository _repository(SupabaseClient client) =>
    SupabaseHealthRepository(
      client,
      SharedPreferencesAsync(),
      source: _Source(),
      heartRateReader: _Reader(),
    );

http.Response _json(http.Request request, int status, Object body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    resetLoadFailures();
  });

  test('every attempt of one sync repeats its key, and the next sync '
      'makes a new one', () async {
    var failures = 1;
    final (client, keys) = await _client((request) {
      if (failures > 0) {
        failures--;
        return _json(request, 500, {'error': 'boom'});
      }
      return _json(request, 200, <String, Object>{});
    });
    final repository = _repository(client);

    await repository.connectAndSync();
    expect(keys, hasLength(2), reason: 'one failed attempt, one retry');
    expect(keys.toSet(), hasLength(1));

    await repository.sync();
    expect(keys, hasLength(3));
    expect(keys.toSet(), hasLength(2));
  });

  test('a server fault (503) is tried again', () async {
    var failures = 1;
    final (client, keys) = await _client((request) {
      if (failures > 0) {
        failures--;
        return _json(request, 503, {
          'error': 'health_sync_unavailable',
          'code': '57014',
        });
      }
      return _json(request, 200, <String, Object>{});
    });

    await _repository(client).connectAndSync();
    expect(keys, hasLength(2));
  });

  for (final (status, error) in [
    (422, 'health_sync_rejected'),
    (429, 'health_sync_limit'),
  ]) {
    test('a $status ($error) is not sent again, and says so', () async {
      final (client, keys) = await _client(
        (request) => _json(request, status, {'error': error, 'code': 'x'}),
      );

      await expectLater(
        _repository(client).connectAndSync(),
        throwsA(predicate((Object e) => '$e'.contains('status: $status'))),
      );
      expect(keys, hasLength(1));
    });
  }

  test(
    'a sync that keeps being refused reaches Sentry once, by its code',
    () async {
      final reported = <NonCriticalFailure>[];
      final previous = failureSink;
      failureSink = (failure, _) => reported.add(failure);
      addTearDown(() => failureSink = previous);
      final (client, _) = await _client(
        (request) => _json(request, 422, {
          'error': 'health_sync_rejected',
          'code': '22023',
        }),
      );
      final repository = _repository(client);

      for (var i = 0; i < 4; i++) {
        await expectLater(repository.connectAndSync(), throwsException);
      }
      expect(reported, hasLength(1));
      expect(reported.single.what, 'Apple Health sync failed 3 times in a row');
      expect(reported.single.detail, 'FunctionsHttpException 422');
    },
  );
}
