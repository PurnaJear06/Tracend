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

void main() {
  test('every attempt of one sync repeats its key, and the next sync '
      'makes a new one', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final keys = <String>[];
    var failures = 1;
    final client = SupabaseClient(
      'https://tracend-test.supabase.co',
      'publishable-test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/functions/v1/health-sync') {
          keys.add(
            (jsonDecode(request.body)
                    as Map<String, dynamic>)['idempotency_key']
                as String,
          );
          if (failures > 0) {
            failures--;
            return http.Response('{"error":"boom"}', 500, request: request);
          }
          return http.Response('{}', 200, request: request);
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
    final repository = SupabaseHealthRepository(
      client,
      SharedPreferencesAsync(),
      source: _Source(),
      heartRateReader: _Reader(),
    );

    await repository.connectAndSync();
    expect(keys, hasLength(2), reason: 'one failed attempt, one retry');
    expect(keys.toSet(), hasLength(1));

    await repository.sync();
    expect(keys, hasLength(3));
    expect(keys.toSet(), hasLength(2));
  });
}
