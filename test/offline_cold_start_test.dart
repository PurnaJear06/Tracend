import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/auth/account_session.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/auth/phase_2_gate.dart';
import 'package:tracend/features/shell/app_shell.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/app_lifecycle.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'home_widgets/fake_home_widget_bridge.dart';
import 'live_activity/fake_workout_activity_bridge.dart';
import 'train_fixtures.dart';

const _url = 'https://tracend-test.supabase.co';
const _userId = '11111111-1111-4111-8111-111111111111';
const _otherUserId = '22222222-2222-4222-8222-222222222222';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: _url,
  supabasePublishableKey: 'publishable-test',
);

/// The 1.7 hub fixture with its one workout planned for today, so a launch
/// today finds it by weekday.
Map<String, dynamic> _hubJson({DateTime? now, String? localToday}) {
  final day = now ?? DateTime.now();
  final hub =
      jsonDecode(
            File(
              'test/contract/fixtures/training_hub_v1_7.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final workout in hub['workouts'] as List) {
    (workout as Map<String, dynamic>)['weekday'] = day.weekday;
  }
  hub['local_today'] = localToday ?? localDayKey(day);
  hub['completed_day_set'] = <String>[];
  return hub;
}

/// The scripted server: while [online] is false every request fails like a
/// phone with no signal. Every attempt is recorded.
class _Backend {
  bool online = false;
  Map<String, dynamic> hub = _hubJson();
  bool sessionStarted = false;
  final attempts = <String>[];
  final startKeys = <String>[];
  final efforts = <int>[];

  Future<http.Response> handle(http.Request request) async {
    final route = '${request.method} ${request.url.path}';
    attempts.add(route);
    if (!online) throw http.ClientException('offline');
    switch (route) {
      case 'GET /auth/v1/user':
        return _ok(_user());
      case 'GET /rest/v1/user_accounts':
        return _ok({'onboarding_state': 'completed'});
      case 'POST /rest/v1/rpc/get_my_training_hub':
        return _ok(hub);
      case 'POST /rest/v1/rpc/start_workout':
        sessionStarted = true;
        startKeys.add(
          (jsonDecode(request.body) as Map)['p_idempotency_key'] as String,
        );
        return _ok('server-session');
      case 'POST /rest/v1/rpc/get_my_workout_session':
        return _ok(sessionStarted ? _serverSession() : null);
      case 'POST /rest/v1/rpc/sync_workout_draft':
        return _ok(null);
      case 'POST /rest/v1/rpc/complete_workout_v2':
        efforts.add((jsonDecode(request.body) as Map)['session_effort'] as int);
        return _ok({'replayed': false, 'completed_sets': 1, 'total_sets': 2});
      case 'POST /rest/v1/rpc/get_my_exercise_history':
        return _ok({'exercises': <Object>[]});
    }
    return http.Response(
      jsonEncode({'message': route}),
      404,
      headers: _headers,
      request: request,
    );
  }

  http.Response _ok(Object? body) =>
      http.Response(jsonEncode(body), 200, headers: _headers);

  Map<String, dynamic> _serverSession() => {
    'session_id': 'server-session',
    'state': 'in_progress',
    'revision': 0,
    'idempotency_key': startKeys.last,
    'local_date': localDayKey(DateTime.now()),
    'actual_started_at': DateTime.now().toUtc().toIso8601String(),
    'exercises': [
      {
        'order': 1,
        'status': 'unknown',
        'sets': [
          for (var n = 1; n <= 3; n++) {'number': n, 'completed': false},
        ],
      },
    ],
  };
}

const _headers = {
  'content-type': 'application/json',
  'x-supabase-api-version': '2024-01-01',
};

Map<String, dynamic> _user([String id = _userId]) => {
  'id': id,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'athlete@tracend.test',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-10-01T00:00:00Z',
};

String _accessToken(DateTime exp) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': _userId, 'exp': exp.millisecondsSinceEpoch ~/ 1000}),
    'test-signature',
  ].join('.');
}

/// A stored session whose access token is still valid, as a launch within the
/// hour finds it, or already expired, as a launch the next day does.
String _storedSession({bool expired = false}) => jsonEncode({
  'access_token': _accessToken(
    DateTime.now().add(Duration(minutes: expired ? -50 : 50)),
  ),
  'expires_in': 3600,
  'refresh_token': 'refresh-test',
  'token_type': 'bearer',
  'user': _user(),
});

/// A repository whose server never answers, but whose phone has a copy.
class _SlowServer extends TrainFixtureRepository
    implements SavedTrainingHubRepository {
  _SlowServer(this.saved);

  final TrainingHubData saved;
  final answer = Completer<TrainingHubData>();

  @override
  Future<TrainingHubData> loadTrainingHub({int periodDays = 28}) =>
      answer.future;

  @override
  Future<TrainingHubData?> loadSavedTrainingHub() async => saved;
}

class _Alerts implements RestAlertScheduler {
  @override
  Future<bool> scheduleRestAlert(int seconds) async => true;

  @override
  Future<void> cancelRestAlert() async {}
}

class _Notifications implements NotificationRepository {
  @override
  Future<NotificationPreferences> load() async => const NotificationPreferences(
    authorizationStatus: 'authorized',
    dailyCheckIn: false,
    weeklyReview: false,
  );

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) => load();
}

void main() {
  late _Backend backend;
  late SharedPreferencesAsync preferences;
  late TrainingHubCache cache;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    preferences = SharedPreferencesAsync();
    cache = TrainingHubCache(preferences);
    backend = _Backend();
    // The device time zone is not available under test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.tracend.app/time_zone'),
          (call) async => null,
        );
  });

  /// The app's one Supabase client, wired to [backend], with the stored
  /// session of [_userId].
  Future<SupabaseClient> startSupabase(
    WidgetTester tester, {
    bool signedIn = true,
    bool expired = false,
  }) async {
    await tester.runAsync(
      () => Supabase.initialize(
        url: _url,
        publishableKey: 'publishable-test',
        httpClient: MockClient((request) async {
          final response = await backend.handle(request);
          return http.Response(
            response.body,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }),
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: const EmptyLocalStorage(),
        ),
      ),
    );
    addTearDown(Supabase.instance.dispose);
    final client = Supabase.instance.client;
    if (signedIn) {
      await client.auth.setInitialSession(_storedSession(expired: expired));
    }
    return client;
  }

  Future<void> pumpGate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Phase2Gate(
          environment: _environment,
          liveActivity: FakeWorkoutActivityBridge(),
          homeWidgets: FakeHomeWidgetBridge(),
        ),
      ),
    );
    // Past the wait for a connection that is not coming.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  }

  final savedThreeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
  String savedLabel(DateTime at) =>
      'Offline. Showing your saved plan from ${shortDate(at)}.';

  group('the gate on a cold start', () {
    testWidgets('a stored session and a saved plan open the plan offline', (
      tester,
    ) async {
      await startSupabase(tester);
      await cache.save(_userId, _hubJson(), savedThreeDaysAgo);

      await pumpGate(tester);

      expect(find.text('Connection needed'), findsNothing);
      // The app opens on Train, from the saved plan, and says so.
      expect(find.text(savedLabel(savedThreeDaysAgo)), findsOneWidget);
      expect(find.text('Upper body A'), findsWidgets);
      expect(find.text('Start workout'), findsOneWidget);

      // What needs the server says so and points at Train.
      await tester.tap(find.byKey(const ValueKey('tab-today')));
      await tester.pumpAndSettle();
      expect(find.text('You are offline.'), findsOneWidget);
      expect(find.text('Open Train'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-coach')));
      await tester.pumpAndSettle();
      expect(find.text('Coach needs a connection.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-nutrition')));
      await tester.pumpAndSettle();
      expect(find.text('Meals needs a connection.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-progress')));
      await tester.pumpAndSettle();
      expect(find.text('Progress needs a connection.'), findsOneWidget);
    });

    testWidgets('an expired access token still opens the saved plan', (
      tester,
    ) async {
      await startSupabase(tester, expired: true);
      await cache.save(_userId, _hubJson(), savedThreeDaysAgo);

      await pumpGate(tester);

      expect(find.text('Connection needed'), findsNothing);
      expect(find.text(savedLabel(savedThreeDaysAgo)), findsOneWidget);
      // The session's refresh and the reads beside the plan give up.
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('a stored session with no saved plan needs a connection', (
      tester,
    ) async {
      await startSupabase(tester);

      await pumpGate(tester);

      expect(find.text('Connection needed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);
    });

    testWidgets('another athlete\'s saved plan is never shown', (tester) async {
      await startSupabase(tester);
      await cache.save(_otherUserId, _hubJson(), savedThreeDaysAgo);

      await pumpGate(tester);

      expect(find.text('Connection needed'), findsOneWidget);
      expect(find.text('Upper body A'), findsNothing);
    });

    testWidgets('a copy tagged with another athlete is not read', (
      tester,
    ) async {
      await startSupabase(tester);
      // Written under this athlete's key, but for another account.
      await preferences.setString(
        TrainingHubCache.keyFor(_userId),
        jsonEncode({
          'v': 1,
          'user_id': _otherUserId,
          'saved_at': savedThreeDaysAgo.toUtc().toIso8601String(),
          'hub': _hubJson(),
        }),
      );

      await pumpGate(tester);

      expect(find.text('Connection needed'), findsOneWidget);
    });

    testWidgets('no stored session shows sign-in', (tester) async {
      await startSupabase(tester, signedIn: false);
      await cache.save(_userId, _hubJson(), savedThreeDaysAgo);

      await pumpGate(tester);

      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(find.text('Upper body A'), findsNothing);
    });

    testWidgets('a copy older than two weeks says how old it is', (
      tester,
    ) async {
      await startSupabase(tester);
      final old = DateTime.now().subtract(const Duration(days: 19));
      await cache.save(_userId, _hubJson(), old);

      await pumpGate(tester);

      expect(
        find.text(
          'Offline. Showing your saved plan from ${shortDate(old)}, '
          '19 days ago. It may have changed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start workout'), findsOneWidget);
    });

    testWidgets('the connection coming back leaves offline mode on resume', (
      tester,
    ) async {
      await startSupabase(tester);
      await cache.save(_userId, _hubJson(), savedThreeDaysAgo);
      await pumpGate(tester);
      expect(find.text(savedLabel(savedThreeDaysAgo)), findsOneWidget);
      expect(tester.widget<AppShell>(find.byType(AppShell)).offline, isTrue);

      backend.online = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Train loaded for real, and the app left its offline mode.
      expect(find.textContaining('Offline.'), findsNothing);
      expect(find.text('Upper body A'), findsWidgets);
      expect(tester.widget<AppShell>(find.byType(AppShell)).offline, isFalse);
      // The fresh hub replaced the saved copy.
      final saved = await cache.load(_userId);
      expect(saved!.savedAt.isAfter(savedThreeDaysAgo), isTrue);
    });

    testWidgets('Try again on the note checks the connection', (tester) async {
      await startSupabase(tester);
      await cache.save(_userId, _hubJson(), savedThreeDaysAgo);
      await pumpGate(tester);

      backend.online = true;
      await tester.tap(find.text('Try again').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Offline.'), findsNothing);
      expect(find.text('Upper body A'), findsWidgets);
      expect(tester.widget<AppShell>(find.byType(AppShell)).offline, isFalse);
    });
  });

  group('the hub copy on the phone', () {
    Future<SupabaseWorkoutRepository> repository(
      WidgetTester tester, {
      DateTime Function()? clock,
    }) async {
      final client = await startSupabase(tester);
      return SupabaseWorkoutRepository(client, preferences, clock: clock);
    }

    testWidgets('a hub that loads is kept for the next launch', (tester) async {
      final source = await repository(tester);
      backend.online = true;

      final hub = await source.loadTrainingHub();

      expect(hub.cachedAt, isNull);
      final saved = await cache.load(_userId);
      expect(saved, isNotNull);
      expect((saved!.hub['workouts'] as List).length, 1);
      expect(saved.hub['schema_version'], isNotNull);
    });

    testWidgets('with no connection the last copy answers, marked as such', (
      tester,
    ) async {
      final source = await repository(tester);
      backend.online = true;
      await source.loadTrainingHub();
      backend.online = false;

      final hub = await source.loadTrainingHub();

      expect(hub.cachedAt, isNotNull);
      expect(hub.workouts.single.name, 'Upper body A');
      expect(hub.planTitle, isNotEmpty);
    });

    testWidgets('a copy from an earlier day is shown on the phone\'s day '
        'without that day\'s numbers', (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await cache.save(_userId, _hubJson(now: yesterday), yesterday);
      final source = await repository(tester);

      final hub = await source.loadTrainingHub();

      expect(localDayKey(hub.localToday!), localDayKey(DateTime.now()));
      expect(hub.dailyLoad, isEmpty);
      expect(hub.load, isNull);
      expect(hub.todayWorkout, isNull);
      expect(hub.workouts.single.exercises, isNotEmpty);
    });

    testWidgets('with no copy the failure is the answer', (tester) async {
      final source = await repository(tester);

      expect(source.loadTrainingHub(), throwsA(isA<Exception>()));
    });

    testWidgets('a window other than the cached one is never served', (
      tester,
    ) async {
      final source = await repository(tester);
      backend.online = true;
      await source.loadTrainingHub();
      backend.online = false;

      expect(source.loadTrainingHub(periodDays: 90), throwsA(anything));
    });

    testWidgets('another athlete\'s copy is not served', (tester) async {
      await cache.save(_otherUserId, _hubJson(), DateTime.now());
      final source = await repository(tester);

      expect(source.loadTrainingHub(), throwsA(anything));
    });
  });

  group('Train from the saved plan', () {
    Future<void> pumpTrain(
      WidgetTester tester,
      TrainFixtureRepository repository,
    ) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TracendMotionScope(
          level: TracendMotionLevel.static,
          child: MaterialApp(
            theme: TracendTheme.dark,
            home: Scaffold(
              body: TrainScreen(
                repository: repository,
                brief: TrainBriefRepository(computed: trainComputed()),
                coach: const TrainCoachRepository(),
                now: trainNow,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the saved plan, the date and no recovery', (
      tester,
    ) async {
      final saved = DateTime(2026, 9, 30, 18);
      await pumpTrain(
        tester,
        TrainFixtureRepository(hub: trainHub(cachedAt: saved)),
      );

      expect(
        find.text('Offline. Showing your saved plan from 30 Sep.'),
        findsOneWidget,
      );
      expect(find.text('Upper body A'), findsWidgets);
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.textContaining('Recovery'), findsNothing);
    });

    testWidgets('opened offline, shows the phone\'s copy while the server is '
        'tried, then the answer', (tester) async {
      final repository = _SlowServer(trainHub(cachedAt: DateTime(2026, 9, 30)));
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TracendMotionScope(
          level: TracendMotionLevel.static,
          child: MaterialApp(
            theme: TracendTheme.dark,
            home: Scaffold(
              body: TrainScreen(
                repository: repository,
                brief: TrainBriefRepository(computed: trainComputed()),
                coach: const TrainCoachRepository(),
                now: trainNow,
                onRetryConnection: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Offline. Showing your saved plan from 30 Sep.'),
        findsOneWidget,
      );
      expect(find.text('Start workout'), findsOneWidget);

      repository.answer.complete(trainHub());
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline.'), findsNothing);
      expect(find.text('Start workout'), findsOneWidget);
    });

    testWidgets('tries the server again when the tab comes back', (
      tester,
    ) async {
      final repository = TrainFixtureRepository(
        hub: trainHub(cachedAt: DateTime(2026, 9, 30)),
      );
      await pumpTrain(tester, repository);
      final loads = repository.hubLoads;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.hubLoads, greaterThan(loads));

      repository.hub = trainHub();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Offline.'), findsNothing);
    });
  });

  group('a workout with no signal', () {
    const workout = PlannedWorkout(
      id: 'upper-a',
      name: 'Upper A',
      objective: 'Press.',
      estimatedMinutes: 45,
      exercises: [
        PlannedExercise(
          order: 1,
          name: 'Bench press',
          setCount: 3,
          repMin: 8,
          repMax: 10,
          targetRpe: 8,
          restSeconds: 60,
          targetLoadKg: 55,
          exerciseSlug: 'bench-press',
        ),
      ],
    );

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      await tester.tap(finder.first);
      await tester.pumpAndSettle();
    }

    testWidgets('starts, logs and finishes on the phone, then syncs on '
        'resume with the same start key', (tester) async {
      final client = await startSupabase(tester);
      final source = SupabaseWorkoutRepository(client, preferences);
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: ActiveWorkoutScreen(
            workout: workout,
            repository: source,
            restAlerts: _Alerts(),
            notifications: _Notifications(),
            activity: FakeWorkoutActivityBridge(),
            lockScreenNumbers: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Offline: the screen opens from the plan, says so, and invents no
      // server session.
      expect(find.text('Upper A'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(backend.startKeys, isEmpty);

      await tap(tester, find.text('Done set 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final drafts = (await preferences.getKeys()).where(
        (key) => key.startsWith(WorkoutLocalKeys.draftPrefix(_userId)),
      );
      expect(drafts, hasLength(1));
      final draft = decodeDraft((await preferences.getString(drafts.single))!);
      expect(
        (draft['session_id'] as String).startsWith('pending-'),
        isTrue,
        reason: 'no server id is invented for a start that never arrived',
      );
      final key = draft['idempotency_key'] as String;

      await tap(tester, find.bySemanticsLabel('Skip rest'));
      await tap(tester, find.bySemanticsLabel('Finish workout'));
      await tap(tester, find.bySemanticsLabel('6, Moderate'));
      await tester.tap(find.widgetWithText(FilledButton, 'Finish workout'));
      await tester.pumpAndSettle();

      // The finish waits on the phone.
      expect(find.text('Finish not sent yet'), findsOneWidget);
      final waiting = await source.loadPendingFinish(workout.id);
      expect(waiting?.sessionEffort, 6);
      expect(backend.efforts, isEmpty);

      // The connection returns and the app comes back to the front: the
      // start is made with the key it was queued under, then the sets and
      // the finish follow.
      backend.online = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(backend.startKeys, [key]);
      expect(backend.efforts, [6]);
      expect(
        backend.attempts.indexOf('POST /rest/v1/rpc/start_workout'),
        lessThan(
          backend.attempts.indexOf('POST /rest/v1/rpc/complete_workout_v2'),
        ),
      );
      expect(find.text('Workout complete'), findsOneWidget);
      expect(await source.loadPendingFinish(workout.id), isNull);
    });
  });

  group('leaving the account', () {
    Future<void> save(String userId) =>
        cache.save(userId, _hubJson(), DateTime.now());

    Future<bool> kept(String userId) async => await cache.load(userId) != null;

    test(
      'signing out removes the saved plan, and only that athlete\'s',
      () async {
        await save(_userId);
        await save(_otherUserId);
        final client = SupabaseClient(
          _url,
          'publishable-test',
          httpClient: MockClient(
            (request) async => http.Response('{}', 204, request: request),
          ),
        );

        await signOutAthlete(client, LocalAccountData(), _userId);

        expect(await kept(_userId), isFalse);
        expect(await kept(_otherUserId), isTrue);
      },
    );

    test('a refused session removes it', () async {
      await save(_userId);
      await LocalAccountData().forgetSession(_userId);
      expect(await kept(_userId), isFalse);
    });

    test('a deleted account removes it with the rest of its data', () async {
      await save(_userId);
      await save(_otherUserId);
      await LocalAccountData().clear(_userId);
      expect(await kept(_userId), isFalse);
      expect(await kept(_otherUserId), isTrue);
    });

    test('a copy of an unknown version or a broken one is not read', () async {
      await preferences.setString(TrainingHubCache.keyFor(_userId), '{');
      expect(await cache.load(_userId), isNull);
      await preferences.setString(
        TrainingHubCache.keyFor(_userId),
        jsonEncode({'v': 2, 'user_id': _userId}),
      );
      expect(await cache.load(_userId), isNull);
    });
  });
}
