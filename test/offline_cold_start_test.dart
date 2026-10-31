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
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/shell/app_shell.dart';
import 'package:tracend/features/train/active_workout_screen.dart';
import 'package:tracend/features/train/offline_safety_notes.dart';
import 'package:tracend/features/train/train_screen.dart';
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/app_lifecycle.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/formatting.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'day_adjustment_fixtures.dart';
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

  /// The planned workout ids `start_workout` was asked for, in order.
  final startedIds = <String>[];

  /// The workout ids the draft payloads of `sync_workout_draft` named.
  final syncedWorkoutIds = <String>[];

  /// `start_workout` answers "planned workout not found" (P0002) for these.
  final staleIds = <String>{};

  /// The code every `start_workout` is refused with, when set.
  String? startRefusal;

  /// The state the server reports for the session it holds.
  String sessionState = 'in_progress';

  /// The code every `sync_workout_draft` is refused with, when set.
  String? syncRefusal;

  /// `start_workout` waits for this before it answers, when set.
  Completer<void>? holdStart;

  /// `complete_workout_v2` makes the session completed on the server.
  bool completingCompletesSession = false;

  /// Runs while a hub request is being answered, before it is.
  Future<void> Function()? duringHub;

  Future<http.Response> handle(http.Request request) async {
    final route = '${request.method} ${request.url.path}';
    attempts.add(route);
    if (!online) throw http.ClientException('offline');
    switch (route) {
      case 'GET /auth/v1/user':
        return _ok(_user());
      case 'POST /auth/v1/logout':
        return http.Response('', 204, headers: _headers);
      case 'GET /rest/v1/user_accounts':
        return _ok({'onboarding_state': 'completed'});
      case 'POST /rest/v1/rpc/get_my_training_hub':
        await duringHub?.call();
        return _ok(hub);
      case 'POST /rest/v1/rpc/start_workout':
        final params = jsonDecode(request.body) as Map;
        final id = params['p_planned_workout_id'] as String;
        startedIds.add(id);
        await holdStart?.future;
        if (staleIds.contains(id)) return _error('P0002', 'not found');
        final refusal = startRefusal;
        if (refusal != null) return _error(refusal, 'refused');
        sessionStarted = true;
        startKeys.add(params['p_idempotency_key'] as String);
        return _ok('server-session');
      case 'POST /rest/v1/rpc/get_my_workout_session':
        return _ok(
          sessionStarted || sessionState == 'completed'
              ? _serverSession()
              : null,
        );
      case 'POST /rest/v1/rpc/sync_workout_draft':
        final draft = (jsonDecode(request.body) as Map)['draft'] as Map;
        syncedWorkoutIds.add(draft['workout_id'] as String);
        final refusal = syncRefusal;
        return refusal == null ? _ok(null) : _error(refusal, 'refused');
      case 'POST /rest/v1/rpc/complete_workout_v2':
        efforts.add((jsonDecode(request.body) as Map)['session_effort'] as int);
        if (completingCompletesSession) sessionState = 'completed';
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

  http.Response _error(String code, String message) => http.Response(
    jsonEncode({'code': code, 'message': message}),
    400,
    headers: _headers,
  );

  Map<String, dynamic> _serverSession() => {
    'session_id': 'server-session',
    'state': sessionState,
    'revision': 0,
    'idempotency_key': startKeys.isEmpty ? '' : startKeys.last,
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

String _accessToken(DateTime exp, String userId) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': userId, 'exp': exp.millisecondsSinceEpoch ~/ 1000}),
    'test-signature',
  ].join('.');
}

/// A stored session whose access token is still valid, as a launch within the
/// hour finds it, or already expired, as a launch the next day does.
String _storedSession({bool expired = false, String userId = _userId}) =>
    jsonEncode({
      'access_token': _accessToken(
        DateTime.now().add(Duration(minutes: expired ? -50 : 50)),
        userId,
      ),
      'expires_in': 3600,
      'refresh_token': 'refresh-test',
      'token_type': 'bearer',
      'user': _user(userId),
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

/// The fixture hub with one workout of one exercise, whose id is [workoutId].
Map<String, dynamic> _singleHub(
  String workoutId, {
  int order = 1,
  DateTime? now,
}) {
  final hub = _hubJson(now: now);
  final workout = (hub['workouts'] as List).first as Map<String, dynamic>;
  workout
    ..['id'] = workoutId
    ..['order'] = order
    ..['exercises'] = [(workout['exercises'] as List).first];
  hub
    ..['workouts'] = [workout]
    ..['today_workout'] = workout;
  return hub;
}

/// The workout the athlete logs, as a hub with [workoutId] names it.
PlannedWorkout _workoutOf(String workoutId) =>
    TrainingHubData.fromHubJson(_singleHub(workoutId)).workouts.single;

/// A draft as the logger saves it, with one set done.
Map<String, dynamic> _draftOf(
  PlannedWorkout workout, {
  required String key,
  bool withIdentity = true,
  DateTime? startedAt,
}) => {
  'workout_id': workout.id,
  'session_id': 'pending-$key',
  'idempotency_key': key,
  'revision': 3,
  'actual_started_at': (startedAt ?? DateTime.now()).toUtc().toIso8601String(),
  if (withIdentity) 'workout_identity': workout.identity!.toJson(),
  'exercises': [
    {
      'order': 1,
      'status': 'completed',
      'pain_flag': false,
      'rest_seconds': 60,
      'sets': [
        {'number': 1, 'completed': true, 'load_kg': '55', 'repetitions': '8'},
        {'number': 2, 'completed': false},
        {'number': 3, 'completed': false},
      ],
    },
  ],
};

/// A repository that has a saved plan and sore-area notes on the phone.
class _WithNotes extends TrainFixtureRepository
    implements SavedSafetyNotesRepository {
  _WithNotes(this.notes, {super.hub});

  final OfflineSafetyNotes? notes;

  @override
  Future<void> saveSafetyNotes(
    DayAdjustment adjustment, {
    required String userId,
  }) async {}

  @override
  Future<OfflineSafetyNotes?> loadSavedSafetyNotes() async => notes;
}

/// A repository whose athlete changes while the plan is read: the draft it is
/// sent for belongs to the athlete who was signed in when the send began.
class _SwitchingRepository extends FixtureWorkoutRepository
    implements WorkoutPlanRemapper {
  String? signedIn = 'athlete-a';
  final started = <String>[];
  final owners = <String?>[];

  @override
  String? get signedInUserId => signedIn;

  @override
  Future<PlannedWorkout?> moveToCurrentPlan(
    String staleId,
    WorkoutIdentity? identity, {
    required String? ownerId,
  }) async {
    owners.add(ownerId);
    signedIn = 'athlete-b';
    return _workoutOf('new-workout');
  }

  @override
  Future<String> start(
    PlannedWorkout workout,
    String idempotencyKey, {
    DateTime? localDate,
  }) async {
    started.add(workout.id);
    throw const PostgrestException(message: 'not found', code: 'P0002');
  }

  @override
  Future<PendingWorkoutFinish?> loadPendingFinish(String workoutId) async =>
      PendingWorkoutFinish(sessionEffort: 6, durationSeconds: 600);
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
    SupabaseWorkoutRepository.forgetSending();
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

  group('a plan copied while the workout waited', () {
    const oldId = 'old-workout';
    const newId = 'new-workout';

    Future<SupabaseWorkoutRepository> pumpLogger(
      WidgetTester tester,
      PlannedWorkout workout, {
      SupabaseWorkoutRepository? using,
    }) async {
      final source =
          using ??
          SupabaseWorkoutRepository(await startSupabase(tester), preferences);
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
      return source;
    }

    Future<void> tapText(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      await tester.tap(finder.first);
      await tester.pumpAndSettle();
    }

    /// Logs one set and finishes with effort 6, all with no signal.
    Future<void> finishOffline(WidgetTester tester) async {
      await tapText(tester, find.text('Done set 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, find.bySemanticsLabel('Skip rest'));
      await tapText(tester, find.bySemanticsLabel('Finish workout'));
      await tapText(tester, find.bySemanticsLabel('6, Moderate'));
      await tester.tap(find.widgetWithText(FilledButton, 'Finish workout'));
      await tester.pumpAndSettle();
      expect(find.text('Finish not sent yet'), findsOneWidget);
    }

    Iterable<String> draftKeys(Set<String> keys) =>
        keys.where((k) => k.startsWith(WorkoutLocalKeys.draftPrefix(_userId)));

    testWidgets('a start the server does not know moves the draft to the '
        'plan\'s copy and the sets and finish are sent', (tester) async {
      final source = await pumpLogger(tester, _workoutOf(oldId));
      await finishOffline(tester);
      final key =
          decodeDraft(
                (await preferences.getString(
                  '${WorkoutLocalKeys.draftPrefix(_userId)}$oldId',
                ))!,
              )['idempotency_key']
              as String;

      backend
        ..online = true
        ..hub = _singleHub(newId)
        ..staleIds.add(oldId);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(backend.startedIds, [oldId, newId]);
      expect(backend.startKeys, [key], reason: 'the same key is reused');
      expect(backend.syncedWorkoutIds, everyElement(newId));
      expect(backend.efforts, [6]);
      expect(find.text('Workout complete'), findsOneWidget);
      expect(draftKeys(await preferences.getKeys()), isEmpty);
      expect(await source.loadPendingFinish(newId), isNull);
      expect(await source.loadPendingFinish(oldId), isNull);
    });

    testWidgets('with no copy in the current plan the sets stay and the '
        'workout says so', (tester) async {
      final source = await pumpLogger(tester, _workoutOf(oldId));
      await finishOffline(tester);

      backend
        ..online = true
        ..hub = _singleHub(newId, order: 2)
        ..staleIds.add(oldId);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Not in your current plan'), findsOneWidget);
      expect(find.textContaining('cannot be finished yet'), findsOneWidget);
      expect(backend.efforts, isEmpty);
      expect(backend.startedIds, [oldId]);
      final kept = await source.loadDraft(oldId);
      expect(kept, isNotNull, reason: 'the sets are never dropped');
      final draft = decodeDraft(kept!);
      expect(
        ((draft['exercises'] as List).first as Map)['sets'],
        contains(containsPair('completed', true)),
      );
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('a workout the server holds as completed opens as completed '
        'and the draft goes', (tester) async {
      final source = await pumpLogger(tester, _workoutOf(oldId));
      await finishOffline(tester);

      backend
        ..online = true
        ..startRefusal = '55000'
        ..sessionState = 'completed';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Finish not sent yet'), findsNothing);
      expect(backend.efforts, isEmpty);
      expect(backend.syncedWorkoutIds, isEmpty);
      expect(await source.loadDraft(oldId), isNull);
      expect(await source.loadPendingFinish(oldId), isNull);
    });

    testWidgets('a server error is not read as being offline', (tester) async {
      await pumpLogger(tester, _workoutOf(oldId));
      backend.online = true;
      backend.startRefusal = '42501';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tapText(tester, find.text('Done set 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('a sync refused because the workout was finished meanwhile '
        'opens it as completed', (tester) async {
      backend.online = true;
      final source = await pumpLogger(tester, _workoutOf(oldId));
      backend
        ..syncRefusal = '55000'
        ..sessionState = 'completed';
      await tapText(tester, find.text('Done set 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Needs attention'), findsNothing);
      expect(await source.loadDraft(oldId), isNull);
    });

    testWidgets('opening the logger waits for a send that is finishing the '
        'same workout', (tester) async {
      final client = await startSupabase(tester);
      final source = SupabaseWorkoutRepository(client, preferences);
      final workout = _workoutOf(oldId);
      final draft = _draftOf(
        workout,
        key: '33333333-3333-4333-8333-333333333333',
      );
      await source.saveDraft(oldId, jsonEncode(draft));
      await expectLater(
        source.completeWithEffort(
          draft['session_id'] as String,
          3,
          1800,
          draft,
          sessionEffort: 6,
        ),
        throwsA(isA<WorkoutSessionPendingException>()),
      );
      final hold = Completer<void>();
      backend
        ..online = true
        ..completingCompletesSession = true
        ..holdStart = hold;
      final sending = source.sendWaiting();
      await tester.pump();

      await pumpLogger(tester, workout, using: source);
      hold.complete();
      await sending;
      await tester.pumpAndSettle();

      expect(backend.startedIds, [oldId], reason: 'the workout starts once');
      expect(backend.efforts, [6]);
      expect(find.text('Needs attention'), findsNothing);
      expect(await source.loadDraft(oldId), isNull);
    });

    testWidgets('a finish with no match in the plan stays on the phone and '
        'reaches Sentry without user data', (tester) async {
      final reported = <NonCriticalFailure>[];
      final previous = failureSink;
      failureSink = (failure, _) => reported.add(failure);
      addTearDown(() => failureSink = previous);
      backend
        ..online = true
        ..hub = _singleHub(newId, order: 2)
        ..staleIds.add(oldId);
      final source = await pumpLogger(tester, _workoutOf(oldId));
      await tapText(tester, find.text('Done set 1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, find.bySemanticsLabel('Skip rest'));
      await tapText(tester, find.bySemanticsLabel('Finish workout'));
      await tapText(tester, find.bySemanticsLabel('6, Moderate'));
      await tester.tap(find.widgetWithText(FilledButton, 'Finish workout'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot be finished yet'), findsOneWidget);
      final saved = await source.loadPendingFinish(oldId);
      expect(saved?.sessionEffort, 6);
      expect(await source.loadDraft(oldId), isNotNull);
      expect(reported.map((f) => f.what), ['workout not in current plan']);
      expect(reported.single.detail, isNot(contains(oldId)));
    });
  });

  group('waiting workouts without the logger', () {
    const oldId = 'old-workout';
    const newId = 'new-workout';
    const key = '33333333-3333-4333-8333-333333333333';

    Future<SupabaseWorkoutRepository> repo(
      WidgetTester tester, {
      bool Function()? loggerOpen,
    }) async {
      final client = await startSupabase(tester);
      return SupabaseWorkoutRepository(
        client,
        preferences,
        loggerOpen: loggerOpen,
      );
    }

    /// A finished workout on the phone: draft and finish, never sent.
    Future<void> finished(
      SupabaseWorkoutRepository source,
      PlannedWorkout workout, {
      bool withIdentity = true,
    }) async {
      final draft = _draftOf(workout, key: key, withIdentity: withIdentity);
      await source.saveDraft(workout.id, jsonEncode(draft));
      await expectLater(
        source.completeWithEffort(
          draft['session_id'] as String,
          3,
          1800,
          draft,
          sessionEffort: 6,
        ),
        throwsA(isA<WorkoutSessionPendingException>()),
      );
    }

    testWidgets('a finish waiting on the phone is sent with no screen open', (
      tester,
    ) async {
      final source = await repo(tester);
      await finished(source, _workoutOf(oldId));
      backend.online = true;

      await source.sendWaiting();

      expect(backend.startedIds, [oldId]);
      expect(backend.startKeys, [key]);
      expect(backend.efforts, [6]);
      expect(await source.loadDraft(oldId), isNull);
      expect(await source.loadPendingFinish(oldId), isNull);
    });

    testWidgets('offline it sends nothing and keeps everything', (
      tester,
    ) async {
      final source = await repo(tester);
      await finished(source, _workoutOf(oldId));

      await source.sendWaiting();

      expect(backend.efforts, isEmpty);
      expect(await source.loadDraft(oldId), isNotNull);
      expect(await source.loadPendingFinish(oldId), isNotNull);
    });

    testWidgets('the connection coming back sends it from the gate', (
      tester,
    ) async {
      final source = await repo(tester);
      await cache.save(_userId, _hubJson(), savedThreeDaysAgo);
      await finished(source, _workoutOf(oldId));
      await pumpGate(tester);
      expect(tester.widget<AppShell>(find.byType(AppShell)).offline, isTrue);
      expect(backend.efforts, isEmpty);

      backend.online = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(backend.efforts, [6], reason: 'sent without opening the workout');
      expect(await source.loadPendingFinish(oldId), isNull);
    });

    testWidgets('a hub that loads sends it too', (tester) async {
      final source = await repo(tester);
      await finished(source, _workoutOf(oldId));
      backend.online = true;

      await source.loadTrainingHub();
      await tester.pumpAndSettle();

      expect(backend.efforts, [6]);
    });

    testWidgets('a plan copied meanwhile gets the workout at its new id', (
      tester,
    ) async {
      final source = await repo(tester);
      await finished(source, _workoutOf(oldId));
      backend
        ..online = true
        ..hub = _singleHub(newId)
        ..staleIds.add(oldId);

      await source.sendWaiting();

      expect(backend.startedIds, [oldId, newId]);
      expect(backend.startKeys, [key]);
      expect(backend.efforts, [6]);
      expect(await source.loadDraft(newId), isNull);
      expect(await source.loadPendingFinish(newId), isNull);
      expect(await source.loadDraft(oldId), isNull);
    });

    testWidgets('a copy with no such workout leaves the draft where it is', (
      tester,
    ) async {
      final source = await repo(tester);
      await finished(source, _workoutOf(oldId));
      backend
        ..online = true
        ..hub = _singleHub(newId, order: 2)
        ..staleIds.add(oldId);

      await source.sendWaiting();

      expect(backend.efforts, isEmpty);
      expect(await source.loadDraft(oldId), isNotNull);
      expect(await source.loadPendingFinish(oldId), isNotNull);
    });

    testWidgets('today\'s open workout belongs to its logger', (tester) async {
      final source = await repo(tester);
      final workout = _workoutOf(oldId);
      await source.saveDraft(oldId, jsonEncode(_draftOf(workout, key: key)));
      backend.online = true;

      await source.sendWaiting();

      expect(backend.startedIds, isEmpty);
      expect(await source.loadDraft(oldId), isNotNull);
    });

    testWidgets('an open logger sends its own workout, not the repository', (
      tester,
    ) async {
      final source = await repo(tester, loggerOpen: () => true);
      await finished(source, _workoutOf(oldId));
      backend.online = true;

      await source.sendWaiting();

      expect(backend.startedIds, isEmpty);
      expect(await source.loadPendingFinish(oldId), isNotNull);
    });

    testWidgets('an account switch while the plan is read starts nothing under '
        'the new account and keeps the draft', (tester) async {
      final client = await startSupabase(tester);
      final source = SupabaseWorkoutRepository(client, preferences);
      await finished(source, _workoutOf(oldId));
      backend
        ..online = true
        ..hub = _singleHub(newId)
        ..staleIds.add(oldId)
        ..duringHub = () async {
          await client.auth.setInitialSession(
            _storedSession(userId: _otherUserId),
          );
        };

      await tester.runAsync(source.sendWaiting);

      expect(backend.startedIds, [oldId]);
      expect(backend.efforts, isEmpty);
      expect(
        await preferences.getString(
          '${WorkoutLocalKeys.draftPrefix(_userId)}$oldId',
        ),
        isNotNull,
      );
      expect(
        (await preferences.getKeys()).where(
          (k) => k.startsWith(WorkoutLocalKeys.draftPrefix(_otherUserId)),
        ),
        isEmpty,
      );
    });

    testWidgets('finding the workout in the plan gives nothing to an athlete '
        'who signed in meanwhile', (tester) async {
      final client = await startSupabase(tester);
      final source = SupabaseWorkoutRepository(client, preferences);
      final workout = _workoutOf(oldId);
      backend
        ..online = true
        ..hub = _singleHub(newId)
        ..duringHub = () async {
          await client.auth.setInitialSession(
            _storedSession(userId: _otherUserId),
          );
        };

      final moved = await tester.runAsync(
        () =>
            source.moveToCurrentPlan(oldId, workout.identity, ownerId: _userId),
      );

      expect(moved, isNull);
    });

    testWidgets('another athlete\'s workout is never sent', (tester) async {
      final source = await repo(tester);
      final other = '${WorkoutLocalKeys.draftPrefix(_otherUserId)}$oldId';
      final otherFinish =
          '${WorkoutLocalKeys.finishPrefix(_otherUserId)}$oldId';
      await preferences.setString(
        other,
        jsonEncode(_draftOf(_workoutOf(oldId), key: key)),
      );
      await preferences.setString(
        otherFinish,
        jsonEncode({'session_effort': 6, 'duration_seconds': 600}),
      );
      backend.online = true;

      await source.sendWaiting();

      expect(backend.startedIds, isEmpty);
      expect(await preferences.getString(other), isNotNull);
      expect(await preferences.getString(otherFinish), isNotNull);
    });
  });

  group('sore areas offline', () {
    Map<String, dynamic> withAreas({String? route}) => {
      ...adjustmentJson(kind: 'none', status: 'none', safetyRoute: route),
      'joint_states': [
        {
          'area': 'knee',
          'state': 'held',
          'severity': 7,
          'persistent': false,
          'since': '2026-10-01',
          'hold_outcome': 'clinician_today',
        },
        {
          'area': 'back',
          'state': 'held',
          'severity': 5,
          'persistent': false,
          'since': '2026-10-01',
          'hold_outcome': 'clinician',
        },
        {
          'area': 'shoulder',
          'state': 'limited',
          'severity': 5,
          'persistent': false,
          'since': '2026-10-01',
        },
        {
          'area': 'other',
          'state': 'watch',
          'severity': 2,
          'persistent': false,
          'since': '2026-10-01',
        },
      ],
    };

    test('the notes are the hold lines and the route, in fixed words', () {
      final notes = OfflineSafetyNotes.from(
        DayAdjustment.tryParse(withAreas(route: 'clinician_today'))!,
      );
      expect(notes.safetyRoute, 'clinician_today');
      expect(notes.lines, [
        'Your knee is resting until you have been seen.',
        "Your lower back is on hold until you've had it checked.",
        'Your shoulder needs a lighter touch this week.',
      ]);
      expect(OfflineSafetyNotes.fromJson(notes.toJson())!.lines, notes.lines);
    });

    test('the controller hands every server answer on', () async {
      final seen = <DayAdjustment>[];
      final controller = DayAdjustmentController(
        repository: FakeDayAdjustmentRepository(withAreas()),
        onAnswered: seen.add,
      );
      await controller.load(localToday: DateTime(2026, 10, 2));
      expect(seen, hasLength(1));
      expect(seen.single.jointStates, hasLength(4));
    });

    testWidgets('an answer for an athlete who is no longer signed in is '
        'dropped', (tester) async {
      final client = await startSupabase(tester);
      final source = SupabaseWorkoutRepository(client, preferences);

      await source.saveSafetyNotes(
        DayAdjustment.tryParse(withAreas())!,
        userId: _otherUserId,
      );

      expect(await cache.loadSafety(_otherUserId), isNull);
      expect(await source.loadSavedSafetyNotes(), isNull);
    });

    testWidgets('the notes live and go with the saved plan', (tester) async {
      final client = await startSupabase(tester);
      final source = SupabaseWorkoutRepository(client, preferences);
      await source.saveSafetyNotes(
        DayAdjustment.tryParse(withAreas())!,
        userId: _userId,
      );

      expect((await source.loadSavedSafetyNotes())!.lines, hasLength(3));
      await cache.save(_userId, _hubJson(), DateTime.now());
      await cache.save(_otherUserId, _hubJson(), DateTime.now());
      await cache.saveSafety(
        _otherUserId,
        OfflineSafetyNotes.from(DayAdjustment.tryParse(withAreas())!),
      );

      await LocalAccountData().forgetSession(_userId);
      expect(await source.loadSavedSafetyNotes(), isNull);
      expect(await cache.loadSafety(_otherUserId), isNotNull);
      expect(
        WorkoutLocalKeys.owns(_userId, TrainingHubCache.safetyKeyFor(_userId)),
        isTrue,
      );
    });

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

    testWidgets('a saved plan says the holds and the route that were saved', (
      tester,
    ) async {
      final notes = OfflineSafetyNotes.from(
        DayAdjustment.tryParse(withAreas(route: 'clinician_today'))!,
      );
      await pumpTrain(
        tester,
        _WithNotes(notes, hub: trainHub(cachedAt: DateTime(2026, 9, 30))),
      );

      expect(find.text('Get this checked today'), findsOneWidget);
      expect(
        find.text('Your knee is resting until you have been seen.'),
        findsOneWidget,
      );
      expect(find.textContaining('From your last check on 2 Oct'), findsOne);
      expect(find.text(offlinePainHoldsUnknown), findsNothing);
    });

    testWidgets('with nothing saved it says holds cannot be checked', (
      tester,
    ) async {
      await pumpTrain(
        tester,
        TrainFixtureRepository(hub: trainHub(cachedAt: DateTime(2026, 9, 30))),
      );
      expect(
        find.text(
          "Pain holds can't be checked offline. Skip any area on hold.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a fresh plan shows neither', (tester) async {
      await pumpTrain(tester, TrainFixtureRepository());
      expect(find.text(offlinePainHoldsUnknown), findsNothing);
    });

    test('a copy from another day leaves out the day\'s targets', () {
      final saved = DateTime(2026, 10, 2, 8);
      final cached = CachedTrainingHub(savedAt: saved, hub: _hubJson());
      final sameDay = TrainingHubData.fromCache(
        CachedTrainingHub(
          savedAt: saved,
          hub: _hubJson(localToday: localDayKey(DateTime(2026, 10, 2))),
        ),
        DateTime(2026, 10, 2, 20),
      );
      final later = TrainingHubData.fromCache(cached, DateTime(2026, 10, 9));

      expect(
        sameDay.workouts.single.exercises.any((e) => e.nextTarget != null),
        isTrue,
      );
      expect(
        later.workouts.single.exercises.any((e) => e.nextTarget != null),
        isFalse,
      );
    });
  });

  group('signing out while a hub loads', () {
    testWidgets('a load in flight at sign-out does not save the plan again', (
      tester,
    ) async {
      final client = await startSupabase(tester);
      final source = SupabaseWorkoutRepository(client, preferences);
      backend
        ..online = true
        // The athlete signs out while the answer is on its way.
        ..duringHub = () => client.auth.signOut(scope: SignOutScope.local);

      await tester.runAsync(source.loadTrainingHub);

      expect(await cache.load(_userId), isNull);
    });

    testWidgets('the gate clears the athlete\'s saved plan when the session '
        'ends', (tester) async {
      final client = await startSupabase(tester);
      await cache.save(_userId, _hubJson(), savedThreeDaysAgo);
      await cache.saveSafety(
        _userId,
        OfflineSafetyNotes.from(
          DayAdjustment.tryParse(adjustmentJson(kind: 'none', status: 'none'))!,
        ),
      );
      await pumpGate(tester);
      expect(await cache.load(_userId), isNotNull);

      backend.online = true;
      await tester.runAsync(
        () => client.auth.signOut(scope: SignOutScope.local),
      );
      await tester.pumpAndSettle();

      expect(await cache.load(_userId), isNull);
      expect(await cache.loadSafety(_userId), isNull);
    });
  });

  group('a send that outlives its athlete', () {
    test('is not started again under the athlete signed in by then', () async {
      final repository = _SwitchingRepository();
      final workout = _workoutOf('old-workout');

      final result = await sendLeftOverDraft(
        repository,
        workout,
        _draftOf(workout, key: '33333333-3333-4333-8333-333333333333'),
      );

      expect(result.settled, isFalse);
      expect(repository.owners, ['athlete-a']);
      expect(repository.started, ['old-workout']);
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
