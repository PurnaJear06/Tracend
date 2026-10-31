import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/features/train/exercise_history.dart';
import 'package:tracend/features/train/unfinished_workout.dart';
import 'package:tracend/features/train/workout_repository.dart';

const _url = 'https://tracend-test.supabase.co';
const _userId = '11111111-1111-4111-8111-111111111111';
const _sessionId = '8a000000-0000-4000-8000-000000000001';
const _workoutId = '8a000000-0000-4000-8000-000000000002';

/// Scripted RPCs, keyed by function name. Every call is recorded with its
/// parameters; a missing answer is a lost connection.
class _Server {
  final calls = <(String, Map<String, dynamic>)>[];
  final answers = <String, http.Response Function(Map<String, dynamic>)>{};

  late final client = SupabaseClient(
    _url,
    'publishable-test',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      if (!path.startsWith('/rest/v1/rpc/')) {
        throw http.ClientException('unexpected $path');
      }
      final name = path.substring('/rest/v1/rpc/'.length);
      final body = request.body.isEmpty ? null : jsonDecode(request.body);
      final params = body is Map
          ? Map<String, dynamic>.from(body)
          : <String, dynamic>{};
      calls.add((name, params));
      final answer = answers[name];
      if (answer == null) throw http.ClientException('offline');
      final response = answer(params);
      return http.Response(
        response.body,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  void answer(String name, Object? body, {int status = 200}) =>
      answers[name] = (_) => _json(status, body);

  void refuse(String name, String code) =>
      answers[name] = (_) =>
          _json(400, {'code': code, 'message': 'refused', 'details': null});

  void goOffline(String name) => answers.remove(name);

  List<String> get names => [for (final call in calls) call.$1];
}

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

String _accessToken() {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1));
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': _userId, 'exp': exp.millisecondsSinceEpoch ~/ 1000}),
    'test-signature',
  ].join('.');
}

Map<String, dynamic> _session() => {
  'access_token': _accessToken(),
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
};

Map<String, dynamic> _draft() => {
  'workout_id': _workoutId,
  'session_id': _sessionId,
  'revision': 4,
  'exercises': const [],
};

/// The one set of the one exercise in a `sync_workout_draft` call.
Map<String, dynamic> _sentSet(Map<String, dynamic> call) {
  final draft = call['draft'] as Map;
  final exercise = (draft['exercises'] as List).single as Map;
  return Map<String, dynamic>.from((exercise['sets'] as List).single as Map);
}

void main() {
  late _Server server;
  late SharedPreferencesAsync preferences;
  late SupabaseWorkoutRepository repository;
  late List<Breadcrumb> breadcrumbs;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    server = _Server();
    await server.client.auth.setInitialSession(jsonEncode(_session()));
    repository = SupabaseWorkoutRepository(server.client, preferences);
    breadcrumbs = [];
    AppBreadcrumbs.sink = breadcrumbs.add;
    await repository.saveDraft(_workoutId, jsonEncode(_draft()));
  });

  group('finish with session effort', () {
    test(
      'sends the athlete effort, a null energy, and clears the draft',
      () async {
        server.answer('complete_workout_v2', {
          'schema_version': '1.0',
          'session_id': _sessionId,
          'completed_sets': 9,
          'total_sets': 12,
          'logging_completeness': 0.75,
          'replayed': false,
        });

        final completion = await repository.completeWithEffort(
          _sessionId,
          4,
          3125,
          _draft(),
          sessionEffort: 7,
        );

        final (name, params) = server.calls.single;
        expect(name, 'complete_workout_v2');
        expect(params, {
          'session_id': _sessionId,
          'client_revision': 4,
          'duration_seconds': 3125,
          'session_effort': 7,
          'notes': '',
          'session_energy': null,
        });
        expect(completion.replayed, isFalse);
        expect(completion.completedSets, 9);
        expect(completion.totalSets, 12);
        expect(await repository.loadDraft(_workoutId), isNull);
        expect(await repository.loadPendingFinish(_workoutId), isNull);
      },
    );

    test('a lost connection keeps the finish for a retry', () async {
      await expectLater(
        repository.completeWithEffort(
          _sessionId,
          4,
          3125,
          _draft(),
          sessionEffort: 6,
        ),
        throwsA(isA<http.ClientException>()),
      );

      final pending = (await repository.loadPendingFinish(_workoutId))!;
      expect(pending.sessionEffort, 6);
      expect(pending.durationSeconds, 3125);
      expect(await repository.loadDraft(_workoutId), isNotNull);

      server.answer('complete_workout_v2', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'replayed': true,
      });
      final retry = await repository.completeWithEffort(
        _sessionId,
        4,
        pending.durationSeconds,
        _draft(),
        sessionEffort: pending.sessionEffort,
      );

      expect(retry.replayed, isTrue);
      expect(retry.completedSets, isNull);
      expect(await repository.loadPendingFinish(_workoutId), isNull);
    });

    test(
      'a workout that never reached the server waits on the device',
      () async {
        await expectLater(
          repository.completeWithEffort(
            'pending-abc',
            1,
            600,
            _draft(),
            sessionEffort: 5,
          ),
          throwsA(isA<WorkoutSessionPendingException>()),
        );
        expect(server.calls, isEmpty);
        expect(
          (await repository.loadPendingFinish(_workoutId))!.sessionEffort,
          5,
        );
      },
    );

    test('effort must be a whole number from 1 to 10', () async {
      for (final effort in [0, 11]) {
        await expectLater(
          repository.completeWithEffort(
            _sessionId,
            4,
            600,
            _draft(),
            sessionEffort: effort,
          ),
          throwsRangeError,
        );
      }
      expect(server.calls, isEmpty);
      expect(await repository.loadPendingFinish(_workoutId), isNull);
    });

    test('breadcrumbs name the step, never the effort', () async {
      server.answer('complete_workout_v2', {'replayed': false});

      await repository.completeWithEffort(
        _sessionId,
        4,
        600,
        _draft(),
        sessionEffort: 9,
      );

      final crumb = breadcrumbs.single;
      expect(crumb.category, 'workout');
      expect(crumb.message, 'Workout finished');
      expect(crumb.data, {'effort_source': 'athlete', 'replayed': false});
    });
  });

  group('discard', () {
    test('discards on the server and clears the draft', () async {
      server.answer('abandon_workout', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'state': 'abandoned',
        'replayed': false,
      });

      final discard = await repository.abandon(
        _sessionId,
        workoutId: _workoutId,
      );

      expect(server.calls.single.$2, {'p_session_id': _sessionId});
      expect(discard.replayed, isFalse);
      expect(discard.queued, isFalse);
      expect(await repository.loadDraft(_workoutId), isNull);
      expect(breadcrumbs.single.message, 'Workout discarded');
    });

    test('a repeat is a replay, not an error', () async {
      server.answer('abandon_workout', {
        'state': 'abandoned',
        'replayed': true,
      });

      final discard = await repository.abandon(
        _sessionId,
        workoutId: _workoutId,
      );

      expect(discard.replayed, isTrue);
    });

    test('a refusal reaches the caller and nothing waits', () async {
      server.refuse('abandon_workout', '22023');

      await expectLater(
        repository.abandon(_sessionId, workoutId: _workoutId),
        throwsA(isA<PostgrestException>()),
      );
      server.answer('get_my_workout_session', null);
      await repository.loadSession(PlannedWorkout.fixture);
      expect(server.names, ['abandon_workout', 'get_my_workout_session']);
    });

    test('a passing server error keeps the discard waiting', () async {
      server.refuse('abandon_workout', '57014');
      final discard = await repository.abandon(
        _sessionId,
        workoutId: _workoutId,
      );
      expect(discard.queued, isTrue);

      // Still failing on the next load: the discard is kept, not dropped.
      server.answer('get_my_workout_session', {
        'session_id': _sessionId,
        'state': 'in_progress',
      });
      expect(await repository.loadSession(PlannedWorkout.fixture), isNull);

      // A final refusal settles it.
      server.refuse('abandon_workout', 'P0002');
      server.answer('get_my_workout_session', null);
      await repository.loadSession(PlannedWorkout.fixture);
      server.calls.clear();
      await repository.loadSession(PlannedWorkout.fixture);
      expect(server.names, ['get_my_workout_session']);
    });

    test(
      'offline, it waits and is sent before the next session load',
      () async {
        final discard = await repository.abandon(
          _sessionId,
          workoutId: _workoutId,
        );
        expect(discard.queued, isTrue);
        expect(await repository.loadDraft(_workoutId), isNull);

        // Still offline: the server's in-progress copy stays hidden.
        server.answer('get_my_workout_session', {
          'session_id': _sessionId,
          'state': 'in_progress',
        });
        expect(await repository.loadSession(PlannedWorkout.fixture), isNull);

        server.answer('abandon_workout', {
          'state': 'abandoned',
          'replayed': false,
        });
        server.answer('get_my_workout_session', null);
        expect(await repository.loadSession(PlannedWorkout.fixture), isNull);
        expect(server.names, [
          'abandon_workout',
          'abandon_workout',
          'get_my_workout_session',
          'abandon_workout',
          'get_my_workout_session',
        ]);

        // Sent: nothing waits any more.
        server.calls.clear();
        await repository.loadSession(PlannedWorkout.fixture);
        expect(server.names, ['get_my_workout_session']);
      },
    );

    test('a workout that never reached the server is only cleared', () async {
      final discard = await repository.abandon(
        'pending-abc',
        workoutId: _workoutId,
      );

      expect(discard.queued, isFalse);
      expect(server.calls, isEmpty);
      expect(await repository.loadDraft(_workoutId), isNull);
    });
  });

  group('unfinished workout', () {
    // The session was closed by the stale rule, which the read no longer
    // returns: its rows are unknown and the draft is sent as it fits.
    setUp(() => server.answer('get_my_workout_session', null));

    final offered = UnfinishedWorkout(
      sessionId: _sessionId,
      plannedWorkoutId: _workoutId,
      name: 'Legs B',
      localDate: DateTime(2026, 10, 23),
      loggedSets: 23,
      totalSets: 25,
      saveBy: DateTime(2026, 10, 30),
    );

    Map<String, Object?> payload() => {
      'schema_version': '1.0',
      'workout': {
        'session_id': _sessionId,
        'planned_workout_id': _workoutId,
        'name': 'Legs B',
        'local_date': '2026-10-23',
        'save_by': '2026-10-30',
        'started_at': '2026-10-23T16:45:00+00:00',
        'logged_sets': 23,
        'total_sets': 25,
        'first_set_at': null,
        'last_set_at': null,
      },
    };

    test('reads the workout the server offers back', () async {
      server.answer('get_my_unfinished_workout_v1', payload());

      final workout = (await repository.loadUnfinishedWorkout())!;

      expect(workout.sessionId, _sessionId);
      expect(workout.plannedWorkoutId, _workoutId);
      expect(workout.name, 'Legs B');
      expect(workout.localDate, DateTime(2026, 10, 23));
      expect(workout.loggedSets, 23);
      expect(workout.unloggedSets, 2);
      expect(workout.saveBy, DateTime(2026, 10, 30));
    });

    test('a discard queued offline is sent before the offer is read', () async {
      server.refuse('abandon_workout', '57014');
      await repository.abandon(_sessionId, workoutId: _workoutId);
      server.calls.clear();
      server.answer('abandon_workout', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'state': 'abandoned',
        'replayed': true,
      });
      server.answer('get_my_unfinished_workout_v1', {
        'schema_version': '1.0',
        'workout': null,
      });

      await repository.loadUnfinishedWorkout();

      expect(server.names, ['abandon_workout', 'get_my_unfinished_workout_v1']);
    });

    test('a discard still waiting hides its workout from the offer', () async {
      server.refuse('abandon_workout', '57014');
      await repository.abandon(_sessionId, workoutId: _workoutId);
      server.answer('get_my_unfinished_workout_v1', payload());

      expect(await repository.loadUnfinishedWorkout(), isNull);
      expect(server.names, [
        'abandon_workout',
        'abandon_workout',
        'get_my_unfinished_workout_v1',
      ]);
    });

    test('reads nothing when nothing is offered', () async {
      server.answer('get_my_unfinished_workout_v1', {
        'schema_version': '1.0',
        'workout': null,
      });

      expect(await repository.loadUnfinishedWorkout(), isNull);
    });

    test('an answer this build cannot read offers nothing', () {
      expect(UnfinishedWorkout.fromJson({'session_id': _sessionId}), isNull);
      expect(UnfinishedWorkout.fromJson('x'), isNull);
      expect(
        UnfinishedWorkout.fromJson({
          'session_id': _sessionId,
          'planned_workout_id': _workoutId,
          'name': 'Legs B',
          'local_date': 'not a date',
          'logged_sets': 1,
          'total_sets': 2,
        }),
        isNull,
      );
    });

    Map<String, dynamic> unsyncedDraft() => {
      ..._draft(),
      'exercises': [
        {
          'order': 1,
          'status': 'performed',
          'sets': [
            {
              'number': 1,
              'repetitions': '8',
              'load_kg': '100',
              'completed': true,
              'started_at': '2026-10-23T16:58:00Z',
              'completed_at': '2026-10-23T17:00:00Z',
            },
          ],
        },
      ],
    };

    test('save sends the athlete effort and removes the draft', () async {
      server.answer('sync_workout_draft', {
        'session_id': _sessionId,
        'client_revision': 4,
        'replayed': true,
      });
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'saved',
        'state': 'completed',
        'replayed': false,
      });

      await repository.saveUnfinishedWorkout(offered, sessionEffort: 8);

      expect(server.names, [
        'get_my_workout_session',
        'sync_workout_draft',
        'resolve_unfinished_workout_v1',
      ]);
      final (_, params) = server.calls.last;
      expect(params, {
        'p_session_id': _sessionId,
        'p_action': 'save',
        'p_session_effort': 8,
      });
      expect(await repository.loadDraft(_workoutId), isNull);
      expect(breadcrumbs.single.message, 'Unfinished workout saved');
    });

    test('save fits the draft to the rows the session holds', () async {
      // The plan had two exercises of three sets; the server's rows are two
      // for the first and none for the second (left out for a sore joint).
      await repository.saveDraft(
        _workoutId,
        jsonEncode({
          ..._draft(),
          'exercises': [
            for (final order in [1, 2])
              {
                'order': order,
                'status': 'unknown',
                'sets': [
                  for (var n = 1; n <= 3; n++)
                    {
                      'number': n,
                      'completed': order == 1 && n == 1,
                      if (order == 1 && n == 1) 'repetitions': '8',
                    },
                ],
              },
          ],
        }),
      );
      server.answer('get_my_workout_session', {
        'session_id': _sessionId,
        'exercises': [
          {
            'order': 1,
            'sets': [
              {'number': 1},
              {'number': 2},
            ],
          },
          {'order': 2, 'sets': <Object>[]},
        ],
      });
      server.answer('sync_workout_draft', {
        'session_id': _sessionId,
        'client_revision': 4,
        'replayed': false,
      });
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'saved',
        'state': 'completed',
        'replayed': false,
      });

      await repository.saveUnfinishedWorkout(offered, sessionEffort: 7);

      final sent = server.calls[1].$2;
      final exercises = (sent['draft'] as Map)['exercises'] as List;
      expect((exercises[0] as Map)['sets'], hasLength(2));
      expect((exercises[1] as Map)['sets'], isEmpty);
    });

    test('save sends sets that never reached the server first', () async {
      await repository.saveDraft(_workoutId, jsonEncode(unsyncedDraft()));
      server.answer('sync_workout_draft', {
        'session_id': _sessionId,
        'client_revision': 4,
        'replayed': false,
      });
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'saved',
        'state': 'completed',
        'replayed': false,
      });

      await repository.saveUnfinishedWorkout(offered, sessionEffort: 7);

      expect(server.names, [
        'get_my_workout_session',
        'sync_workout_draft',
        'resolve_unfinished_workout_v1',
      ]);
      final (_, sent) = server.calls[1];
      expect(sent['session_id'], _sessionId);
      expect(sent['client_revision'], 4);
      final set = _sentSet(sent);
      expect(set['repetitions'], '8');
      expect(set['started_at'], '2026-10-23T16:58:00Z');
      expect(await repository.loadDraft(_workoutId), isNull);
    });

    test('times the server refuses are sent again without them', () async {
      await repository.saveDraft(_workoutId, jsonEncode(unsyncedDraft()));
      var syncs = 0;
      server.answers['sync_workout_draft'] = (_) {
        syncs++;
        return syncs == 1
            ? _json(400, {'code': '22023', 'message': 'time', 'details': null})
            : _json(200, {'session_id': _sessionId, 'replayed': false});
      };
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'saved',
        'state': 'completed',
        'replayed': false,
      });

      await repository.saveUnfinishedWorkout(offered, sessionEffort: 7);

      final retried = _sentSet(server.calls[2].$2);
      expect(retried.containsKey('started_at'), isFalse);
      expect(retried['repetitions'], '8');
      expect(server.names.last, 'resolve_unfinished_workout_v1');
    });

    test('a failed send answers nothing and keeps the draft', () async {
      await repository.saveDraft(_workoutId, jsonEncode(unsyncedDraft()));
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'saved',
        'state': 'completed',
        'replayed': false,
      });

      await expectLater(
        repository.saveUnfinishedWorkout(offered, sessionEffort: 7),
        throwsA(isA<http.ClientException>()),
      );

      expect(server.names, ['get_my_workout_session', 'sync_workout_draft']);
      expect(jsonDecode((await repository.loadDraft(_workoutId))!), {
        ...unsyncedDraft(),
      });
    });

    test(
      'a send the server refuses for another reason answers nothing',
      () async {
        server.refuse('sync_workout_draft', '22P02');

        await expectLater(
          repository.saveUnfinishedWorkout(offered, sessionEffort: 7),
          throwsA(isA<PostgrestException>()),
        );

        expect(server.names, ['get_my_workout_session', 'sync_workout_draft']);
        expect(await repository.loadDraft(_workoutId), isNotNull);
      },
    );

    test(
      'a retry after a lost answer saves again and removes the draft',
      () async {
        // The first try reached the server, which saved the workout; the
        // answer was lost. The session now refuses the draft (55000).
        server.refuse('sync_workout_draft', '55000');
        server.answer('resolve_unfinished_workout_v1', {
          'schema_version': '1.0',
          'session_id': _sessionId,
          'resolution': 'saved',
          'state': 'completed',
          'replayed': true,
        });

        await repository.saveUnfinishedWorkout(offered, sessionEffort: 7);

        expect(server.names, [
          'get_my_workout_session',
          'sync_workout_draft',
          'resolve_unfinished_workout_v1',
        ]);
        expect(await repository.loadDraft(_workoutId), isNull);
      },
    );

    test('a workout discarded meanwhile is gone and its draft goes', () async {
      server.refuse('sync_workout_draft', '55000');
      server.refuse('resolve_unfinished_workout_v1', '55000');

      await expectLater(
        repository.saveUnfinishedWorkout(offered, sessionEffort: 7),
        throwsA(isA<UnfinishedWorkoutGone>()),
      );

      expect(await repository.loadDraft(_workoutId), isNull);
    });

    test('a workout past its seven days is gone and nothing is lost', () async {
      server.answer('sync_workout_draft', {
        'session_id': _sessionId,
        'replayed': true,
      });
      server.refuse('resolve_unfinished_workout_v1', 'P0002');

      await expectLater(
        repository.saveUnfinishedWorkout(offered, sessionEffort: 7),
        throwsA(isA<UnfinishedWorkoutGone>()),
      );

      expect(await repository.loadDraft(_workoutId), isNotNull);
    });

    test('a discard of a workout finished meanwhile is gone', () async {
      server.refuse('resolve_unfinished_workout_v1', '22023');

      await expectLater(
        repository.discardUnfinishedWorkout(offered),
        throwsA(isA<UnfinishedWorkoutGone>()),
      );
    });

    test('a draft of another session is not sent with this one', () async {
      await repository.saveDraft(
        _workoutId,
        jsonEncode({
          ..._draft(),
          'session_id': '8a000000-0000-4000-8000-000000000009',
        }),
      );
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'saved',
        'state': 'completed',
        'replayed': false,
      });

      await repository.saveUnfinishedWorkout(offered, sessionEffort: 7);

      expect(server.names, ['resolve_unfinished_workout_v1']);
      expect(await repository.loadDraft(_workoutId), isNotNull);
    });

    test('without a draft nothing is sent first', () async {
      await repository.clearDraft(_workoutId);
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'saved',
        'state': 'completed',
        'replayed': false,
      });

      await repository.saveUnfinishedWorkout(offered, sessionEffort: 7);

      expect(server.names, ['resolve_unfinished_workout_v1']);
    });

    test('an effort outside 1 to 10 is never sent', () async {
      expect(
        () => repository.saveUnfinishedWorkout(offered, sessionEffort: 11),
        throwsRangeError,
      );
      expect(server.calls, isEmpty);
    });

    test('discard sends the answer and removes the draft', () async {
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'discarded',
        'state': 'abandoned',
        'replayed': false,
      });

      await repository.discardUnfinishedWorkout(offered);

      final (name, params) = server.calls.single;
      expect(name, 'resolve_unfinished_workout_v1');
      expect(params, {'p_session_id': _sessionId, 'p_action': 'discard'});
      expect(await repository.loadDraft(_workoutId), isNull);
      expect(breadcrumbs.single.message, 'Unfinished workout discarded');
    });

    test('a draft of a newer session of the same workout stays', () async {
      await repository.saveDraft(
        _workoutId,
        jsonEncode({
          ..._draft(),
          'session_id': '8a000000-0000-4000-8000-000000000009',
        }),
      );
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'discarded',
        'state': 'abandoned',
        'replayed': false,
      });

      await repository.discardUnfinishedWorkout(offered);

      expect(await repository.loadDraft(_workoutId), isNotNull);
    });

    test('a refused answer keeps the draft and says so', () async {
      server.refuse('resolve_unfinished_workout_v1', '57014');

      await expectLater(
        repository.discardUnfinishedWorkout(offered),
        throwsA(isA<PostgrestException>()),
      );

      expect(await repository.loadDraft(_workoutId), isNotNull);
    });

    test('a draft that cannot be read does not undo the answer', () async {
      await repository.saveDraft(_workoutId, 'not json');
      server.answer('resolve_unfinished_workout_v1', {
        'schema_version': '1.0',
        'session_id': _sessionId,
        'resolution': 'discarded',
        'state': 'abandoned',
        'replayed': false,
      });

      await repository.discardUnfinishedWorkout(offered);

      expect(server.names, ['resolve_unfinished_workout_v1']);
    });
  });

  group('exercise history', () {
    Map<String, dynamic> answer(List<String> keys) => {
      'schema_version': '1.0',
      'sessions_limit': 8,
      'exercises': [
        for (final key in keys)
          {
            'key': key,
            'kind': 'load',
            'last_session': {
              'session_id': _sessionId,
              'local_date': '2026-09-25',
              'sets': [
                {'set_number': 1, 'load_kg': 70, 'repetitions': 8, 'rpe': null},
              ],
            },
            'best_set': {
              'kind': 'load',
              'load_kg': 72.5,
              'repetitions': 6,
              'local_date': '2026-09-11',
            },
            'top_sets': const [],
          },
      ],
    };

    void answerHistory() =>
        server.answers['get_my_exercise_history'] = (params) =>
            _json(200, answer(List<String>.from(params['p_keys'] as List)));

    test('sends clean keys and reads the answer', () async {
      answerHistory();

      final result = await repository.loadExerciseHistory([
        ' barbell-bench-press ',
        'barbell-bench-press',
        '',
        'x' * 121,
        'Cable fly',
      ], sessions: 4);

      expect(server.calls.single.$2, {
        'p_keys': ['barbell-bench-press', 'Cable fly'],
        'p_sessions': 4,
      });
      expect(result.fromCache, isFalse);
      expect(result['barbell-bench-press']!.bestSet!.loadKg, 72.5);
    });

    test('asks 20 keys at a time', () async {
      answerHistory();
      final keys = [for (var i = 0; i < 25; i++) 'exercise-$i'];

      final result = await repository.loadExerciseHistory(keys);

      expect(server.calls, hasLength(2));
      expect(server.calls.first.$2['p_keys'], hasLength(20));
      expect(server.calls.last.$2['p_keys'], hasLength(5));
      expect(result.exercises, hasLength(25));
    });

    test('offline, answers from the last copy on this device', () async {
      answerHistory();
      await repository.loadExerciseHistory(['barbell-bench-press']);

      server.goOffline('get_my_exercise_history');
      final result = await repository.loadExerciseHistory([
        'barbell-bench-press',
        'romanian-deadlift',
      ]);

      expect(result.fromCache, isTrue);
      expect(
        result['barbell-bench-press']!.lastSession!.sets.single.loadKg,
        70,
      );
      expect(result['romanian-deadlift'], isNull);
    });

    test('offline with no copy, every key is unknown', () async {
      final result = await repository.loadExerciseHistory(['squat']);

      expect(result.fromCache, isTrue);
      expect(result['squat'], isNull);
    });

    test('no usable key asks nothing', () async {
      final result = await repository.loadExerciseHistory([' ']);

      expect(server.calls, isEmpty);
      expect(result.exercises, isEmpty);
    });

    test('the copy is kept per athlete for account deletion', () async {
      answerHistory();
      await repository.loadExerciseHistory(['squat']);

      final keys = await preferences.getKeys();
      expect(
        keys.where((key) => WorkoutLocalKeys.owns(_userId, key)),
        containsAll([
          WorkoutLocalKeys.exerciseHistory(_userId),
          '${WorkoutLocalKeys.draftPrefix(_userId)}$_workoutId',
        ]),
      );
    });
  });

  test('the history key is the slug, or the name without one', () {
    final hub = PlannedWorkout.fromHubJson({
      'id': _workoutId,
      'name': 'Push',
      'objective': 'Press',
      'estimated_minutes': 60,
      'exercises': [
        {
          'order': 1,
          'name': 'Bench press',
          'set_count': 3,
          'rep_min': 6,
          'rep_max': 8,
          'exercise_slug': 'barbell-bench-press',
        },
        {
          'order': 2,
          'name': ' Cable fly ',
          'set_count': 3,
          'rep_min': 10,
          'rep_max': 12,
        },
      ],
    });

    expect(hub.exercises.first.historyKey, 'barbell-bench-press');
    expect(hub.exercises.last.historyKey, 'Cable fly');
  });

  test('fixture mode treats every exercise as a first log', () async {
    final result = await FixtureWorkoutRepository().loadExerciseHistory([
      'squat',
    ]);

    expect(result['squat']!.isFirstLog, isTrue);
    expect(result.fromCache, isFalse);
    expect(ExerciseHistoryKind.parse('load'), ExerciseHistoryKind.load);
  });
}
