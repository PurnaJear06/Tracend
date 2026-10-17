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

class _ThrowingReader implements HeartRateReader {
  int requests = 0;

  @override
  Future<void> requestAccess() async {
    requests += 1;
    throw StateError('channel exploded');
  }

  @override
  Future<List<HeartRateSample>> readSamples(DateTime from, DateTime to) async =>
      const [];
}

class _Source implements HealthDataSource {
  int reads = 0;

  @override
  Future<bool> requestReadAccess() async => true;

  @override
  Future<HealthReadResult> read(DateTime start, DateTime end) async {
    reads += 1;
    return const HealthReadResult(
      requestedMetrics: {},
      returnedMetrics: {},
      samples: [],
      unavailable: true,
      accessError: HealthAccessError.readFailed,
    );
  }
}

void main() {
  test(
    'a heart-rate access request that throws does not stop the sync',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final client = SupabaseClient(
        'https://tracend-test.supabase.co',
        'publishable-test',
        httpClient: MockClient((request) async => http.Response('{}', 404)),
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
      final reader = _ThrowingReader();
      final source = _Source();
      final repository = SupabaseHealthRepository(
        client,
        SharedPreferencesAsync(),
        source: source,
        heartRateReader: reader,
      );

      final status = await repository.connectAndSync();

      expect(reader.requests, 1);
      expect(source.reads, 1, reason: 'the sync still ran');
      expect(status.state, HealthConnectionState.unavailable);
      expect(status.accessError, HealthAccessError.readFailed);
    },
  );
}
