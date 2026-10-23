import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/workout_hr/watch_workout_prompt.dart';

Map<String, dynamic> _fixture() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'test/contract/fixtures/watch_workout_status_v1_0.json',
        ).readAsStringSync(),
      )
      as Map,
);

void main() {
  group('the rule', () {
    WatchWorkoutStatus status(Object? json) =>
        WatchWorkoutStatus.tryParse(json)!;

    test('no finished workout yet suggests a Watch workout', () {
      expect(
        status({'recent_sessions': <Object?>[]}).suggestsWatchWorkout,
        isTrue,
      );
    });

    test('three workouts with no Watch heart rate suggest one', () {
      expect(
        status({
          'recent_sessions': [
            for (var i = 0; i < 3; i++) {'completed_sets': 9, 'watch_sets': 0},
          ],
        }).suggestsWatchWorkout,
        isTrue,
      );
    });

    test('one tracked workout among the last three keeps it quiet', () {
      expect(
        status({
          'recent_sessions': [
            {'completed_sets': 9, 'watch_sets': 0},
            {'completed_sets': 9, 'watch_sets': 1},
            {'completed_sets': 9, 'watch_sets': 0},
          ],
        }).suggestsWatchWorkout,
        isFalse,
      );
    });

    test('a payload that cannot be trusted is no status at all', () {
      const good = {'completed_sets': 9, 'watch_sets': 0};
      final malformed = <String, Object?>{
        'null': null,
        'not an object': 'nothing',
        'a list': <Object?>[],
        'no recent_sessions': <String, Object?>{'as_of': '2026-10-23'},
        'recent_sessions null': {'recent_sessions': null},
        'recent_sessions not a list': {'recent_sessions': 'none'},
        'only malformed rows': {
          'recent_sessions': [
            {'watch_sets': 4},
            'nothing',
          ],
        },
        'a malformed row among good ones': {
          'recent_sessions': [
            good,
            {'watch_sets': 0},
            good,
          ],
        },
        'a row without watch_sets': {
          'recent_sessions': [
            {'completed_sets': 9},
          ],
        },
        'a fractional count': {
          'recent_sessions': [
            {'completed_sets': 9, 'watch_sets': 0.5},
          ],
        },
        'a string count': {
          'recent_sessions': [
            {'completed_sets': '9', 'watch_sets': 0},
          ],
        },
      };
      malformed.forEach((name, json) {
        expect(WatchWorkoutStatus.tryParse(json), isNull, reason: name);
      });
    });
  });

  group('get_my_watch_workout_status_v1 1.0', () {
    final json = _fixture();

    test('carries its schema version and complete key lists', () {
      expect(json.keys.toSet(), {'schema_version', 'as_of', 'recent_sessions'});
      expect(json['schema_version'], '1.0');
      for (final row in json['recent_sessions'] as List) {
        expect((row as Map).keys.toSet(), {
          'local_date',
          'completed_sets',
          'watch_sets',
        });
      }
    });

    test('reads as the sets the Watch tracked', () {
      final status = WatchWorkoutStatus.tryParse(json)!;
      expect(status.recentSessions.map((s) => s.completedSets), [9, 8, 10]);
      expect(status.recentSessions.map((s) => s.watchSets), [0, 6, 0]);
      expect(status.suggestsWatchWorkout, isFalse);
    });
  });

  group('the source', () {
    late List<http.Request> requests;
    late Object? reply;
    late int status;
    late DateTime now;

    SupabaseWatchWorkoutPromptSource source() {
      final client = SupabaseClient(
        'https://tracend-test.supabase.co',
        'publishable-test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(reply),
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      return SupabaseWatchWorkoutPromptSource(
        client,
        preferences: SharedPreferencesAsync(),
        now: () => now,
      );
    }

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      requests = [];
      status = 200;
      now = DateTime(2026, 10, 23, 18, 5);
      reply = {
        'schema_version': '1.0',
        'as_of': '2026-10-23',
        'recent_sessions': [
          {'local_date': '2026-10-21', 'completed_sets': 9, 'watch_sets': 0},
        ],
      };
    });

    test(
      'asks the server for today and suggests when nothing was tracked',
      () async {
        expect(await source().shouldSuggest(), isTrue);
        expect(
          requests.single.url.path,
          endsWith('get_my_watch_workout_status_v1'),
        );
        expect(jsonDecode(requests.single.body), {'local_date': '2026-10-23'});
      },
    );

    test('stays quiet when the Watch tracked a recent workout', () async {
      reply = _fixture();
      expect(await source().shouldSuggest(), isFalse);
    });

    test('a reply that is not a valid status suggests nothing', () async {
      for (final bad in <Object?>[
        null,
        <String, Object?>{},
        {'recent_sessions': 'none'},
        {
          'recent_sessions': [
            {'watch_sets': 0},
          ],
        },
      ]) {
        reply = bad;
        expect(await source().shouldSuggest(), isFalse, reason: '$bad');
      }
    });

    test('a server it cannot read suggests nothing', () async {
      status = 500;
      reply = {'message': 'down'};
      expect(await source().shouldSuggest(), isFalse);
    });

    test('Not now keeps it quiet for seven days, then it may return', () async {
      final prompt = source();
      await prompt.snooze();

      requests.clear();
      expect(await prompt.shouldSuggest(), isFalse);
      expect(requests, isEmpty, reason: 'the answer is checked before asking');

      now = now
          .add(const Duration(days: 7))
          .subtract(const Duration(minutes: 1));
      expect(await prompt.shouldSuggest(), isFalse);
      now = now.add(const Duration(minutes: 2));
      expect(await prompt.shouldSuggest(), isTrue);
    });

    test('"I don\'t use a Watch" keeps it quiet for good', () async {
      final prompt = source();
      await prompt.mute();

      requests.clear();
      expect(await prompt.shouldSuggest(), isFalse);
      now = now.add(const Duration(days: 400));
      expect(await prompt.shouldSuggest(), isFalse);
      expect(requests, isEmpty);
    });
  });
}
