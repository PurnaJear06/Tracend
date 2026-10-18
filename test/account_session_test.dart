import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/widgets/account_sheets.dart';
import 'package:tracend/features/auth/account_session.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/auth/phase_2_gate.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/onboarding/onboarding_flow.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';

import 'home_widgets/fake_home_widget_bridge.dart';
import 'live_activity/fake_workout_activity_bridge.dart';

const _url = 'https://tracend-test.supabase.co';
const _userId = '11111111-1111-4111-8111-111111111111';
const _otherUserId = '22222222-2222-4222-8222-222222222222';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: _url,
  supabasePublishableKey: 'publishable-test',
);

/// Scripted Supabase endpoints, keyed by `METHOD /path`; every request is
/// recorded in order.
class _Server {
  final requests = <String>[];
  final routes = <String, Future<http.Response> Function()>{};

  late final client = SupabaseClient(
    _url,
    'publishable-test',
    httpClient: MockClient((request) async {
      final route = '${request.method} ${request.url.path}';
      requests.add(route);
      final handler = routes[route];
      final response = handler == null
          ? _json(404, {'message': route})
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
}

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {
    'content-type': 'application/json',
    'x-supabase-api-version': '2024-01-01',
  },
);

Map<String, dynamic> _user() => {
  'id': _userId,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'athlete@tracend.test',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-10-01T00:00:00Z',
};

/// An access token whose payload carries [exp]; Auth checks it, not the app.
String _accessToken(DateTime exp) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': _userId, 'exp': exp.millisecondsSinceEpoch ~/ 1000}),
    'test-signature',
  ].join('.');
}

Map<String, dynamic> _session(DateTime exp) => {
  'access_token': _accessToken(exp),
  'expires_in': 3600,
  'refresh_token': 'refresh-test',
  'token_type': 'bearer',
  'user': _user(),
};

Future<void> _storeSession(SupabaseClient client, DateTime exp) =>
    client.auth.setInitialSession(jsonEncode(_session(exp)));

const _userNotFound = {
  'code': 'user_not_found',
  'msg': 'User from sub claim in JWT does not exist',
};

void main() {
  late SharedPreferencesAsync preferences;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    await preferences.setString(
      HealthPreferenceKeys(_userId).lastSync,
      '2026-10-01T00:00:00Z',
    );
    await preferences.setString(
      SupabaseHealthBaselineSource.historyMonthKey(_userId),
      '2026-10',
    );
    await preferences.setString(
      HealthPreferenceKeys(_otherUserId).lastSync,
      '2026-10-01T00:00:00Z',
    );
    await preferences.setString('tracend_theme_mode', 'dark');
    // An earlier build's one choice for the phone, this athlete's and
    // another athlete's.
    await preferences.setBool(TodayWidgetPublisher.lockScreenNumbersKey, true);
    await preferences.setBool(
      TodayWidgetPublisher.lockScreenNumbersKeyFor(_userId),
      true,
    );
    await preferences.setBool(
      TodayWidgetPublisher.lockScreenNumbersKeyFor(_otherUserId),
      true,
    );
    await preferences.setString(
      '${WorkoutLocalKeys.draftPrefix(_userId)}workout-1',
      '{}',
    );
    await preferences.setString(
      WorkoutLocalKeys.exerciseHistory(_userId),
      '{}',
    );
    await preferences.setString(
      WorkoutLocalKeys.exerciseHistory(_otherUserId),
      '{}',
    );
    SharedPreferences.setMockInitialValues({
      SharedPreferencesCoachThreadMemory.storageKey: 'thread-1',
      CheckInQueue.storageKeyFor(_userId): '{}',
      CheckInQueue.storageKeyFor(_otherUserId): '{}',
    });
  });

  /// The athlete's Lock Screen choice and the phone-wide one are gone;
  /// another athlete's stays theirs.
  Future<void> expectWidgetChoiceForgotten() async {
    expect(
      await preferences.getBool(TodayWidgetPublisher.lockScreenNumbersKey),
      isNull,
    );
    expect(
      await preferences.getBool(
        TodayWidgetPublisher.lockScreenNumbersKeyFor(_userId),
      ),
      isNull,
    );
    expect(
      await preferences.getBool(
        TodayWidgetPublisher.lockScreenNumbersKeyFor(_otherUserId),
      ),
      isTrue,
    );
  }

  Future<void> expectAthleteDataCleared() async {
    expect(
      await preferences.getString(HealthPreferenceKeys(_userId).lastSync),
      isNull,
    );
    expect(
      await preferences.getString(
        SupabaseHealthBaselineSource.historyMonthKey(_userId),
      ),
      isNull,
    );
    // Another athlete's state and device settings stay.
    expect(
      await preferences.getString(HealthPreferenceKeys(_otherUserId).lastSync),
      isNotNull,
    );
    expect(await preferences.getString('tracend_theme_mode'), 'dark');
    // The Lock Screen widget choice goes with the account.
    await expectWidgetChoiceForgotten();
    expect(
      await preferences.getString(
        '${WorkoutLocalKeys.draftPrefix(_userId)}workout-1',
      ),
      isNull,
    );
    expect(
      await preferences.getString(WorkoutLocalKeys.exerciseHistory(_userId)),
      isNull,
    );
    expect(
      await preferences.getString(
        WorkoutLocalKeys.exerciseHistory(_otherUserId),
      ),
      isNotNull,
    );
    final legacy = await SharedPreferences.getInstance();
    expect(
      legacy.getString(SharedPreferencesCoachThreadMemory.storageKey),
      isNull,
    );
    expect(legacy.getString(CheckInQueue.storageKeyFor(_userId)), isNull);
    expect(
      legacy.getString(CheckInQueue.storageKeyFor(_otherUserId)),
      isNotNull,
    );
  }

  /// A refused session may belong to an account that still exists: only the
  /// open Coach thread and the Lock Screen choice are forgotten.
  Future<void> expectAthleteDataKept() async {
    await expectWidgetChoiceForgotten();
    expect(
      await preferences.getString(HealthPreferenceKeys(_userId).lastSync),
      isNotNull,
    );
    final legacy = await SharedPreferences.getInstance();
    expect(
      legacy.getString(SharedPreferencesCoachThreadMemory.storageKey),
      isNull,
    );
    expect(legacy.getString(CheckInQueue.storageKeyFor(_userId)), isNotNull);
  }

  late FakeWorkoutActivityBridge liveActivity;
  late FakeHomeWidgetBridge homeWidgets;

  Future<void> pumpGate(WidgetTester tester, _Server server) async {
    liveActivity = FakeWorkoutActivityBridge();
    homeWidgets = FakeHomeWidgetBridge();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Phase2Gate(
          environment: _environment,
          client: server.client,
          liveActivity: liveActivity,
          homeWidgets: homeWidgets,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('only a refusal from Auth ends the session', () {
    expect(
      isRejectedSession(
        const AuthApiException(
          'gone',
          statusCode: '403',
          code: 'user_not_found',
        ),
      ),
      isTrue,
    );
    expect(
      isRejectedSession(
        const AuthApiException(
          'expired',
          statusCode: '400',
          code: 'refresh_token_not_found',
        ),
      ),
      isTrue,
    );
    expect(
      isRejectedSession(
        const AuthApiException(
          'slow down',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
      ),
      isFalse,
    );
    expect(isRejectedSession(AuthRetryableFetchException()), isFalse);
    expect(isRejectedSession(const PostgrestException(message: 'x')), isFalse);
  });

  group('signing out', () {
    test(
      'forgets the Lock Screen choice, so the next athlete starts off',
      () async {
        final server = _Server()..answer('POST /auth/v1/logout', 204, {});
        await _storeSession(
          server.client,
          DateTime.now().add(const Duration(minutes: 50)),
        );

        await signOutAthlete(server.client, LocalAccountData(), _userId);

        expect(server.requests, contains('POST /auth/v1/logout'));
        expect(server.client.auth.currentSession, isNull);
        await expectWidgetChoiceForgotten();
        // Nothing else of the athlete's goes.
        expect(
          await preferences.getString(HealthPreferenceKeys(_userId).lastSync),
          isNotNull,
        );
        final next = TodayWidgetPublisher(
          bridge: FakeHomeWidgetBridge(),
          userId: _otherUserId,
          preferences: preferences,
        );
        expect(await next.lockScreenNumbers(), isTrue);
        final another = TodayWidgetPublisher(
          bridge: FakeHomeWidgetBridge(),
          userId: '33333333-3333-4333-8333-333333333333',
          preferences: preferences,
        );
        expect(await another.lockScreenNumbers(), isFalse);
      },
    );

    test('without Auth the session still ends on this device', () async {
      final server = _Server();
      server.routes['POST /auth/v1/logout'] = () =>
          Future.error(http.ClientException('offline'));
      await _storeSession(
        server.client,
        DateTime.now().add(const Duration(minutes: 50)),
      );

      await signOutAthlete(server.client, LocalAccountData(), _userId);

      expect(server.client.auth.currentSession, isNull);
      await expectWidgetChoiceForgotten();
    });
  });

  group('restoring a stored session', () {
    testWidgets('a deleted athlete lands on sign-in, not Connection needed', (
      tester,
    ) async {
      final server = _Server()
        ..answer('GET /auth/v1/user', 403, _userNotFound)
        ..answer('POST /auth/v1/logout', 403, _userNotFound);
      // The access token is still unexpired: the database would accept it.
      await _storeSession(
        server.client,
        DateTime.now().add(const Duration(minutes: 50)),
      );

      await pumpGate(tester, server);

      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(find.text('Connection needed'), findsNothing);
      expect(server.client.auth.currentSession, isNull);
      expect(server.requests, isNot(contains('GET /rest/v1/user_accounts')));
      await expectAthleteDataCleared();
      expect(liveActivity.methods, contains('end'));
      expect(homeWidgets.calls, contains('clear'));
    });

    testWidgets(
      'a refused refresh token lands on sign-in, keeping athlete data',
      (tester) async {
        final server = _Server()
          ..answer('POST /auth/v1/token', 400, {
            'code': 'refresh_token_not_found',
            'msg': 'Invalid Refresh Token: Refresh Token Not Found',
          });
        await _storeSession(
          server.client,
          DateTime.now().subtract(const Duration(hours: 2)),
        );

        await pumpGate(tester, server);

        expect(find.byType(OwnerAuthScreen), findsOneWidget);
        expect(find.text('Connection needed'), findsNothing);
        expect(server.client.auth.currentSession, isNull);
        await expectAthleteDataKept();
        expect(liveActivity.methods, contains('end'));
        expect(homeWidgets.calls, contains('clear'));
      },
    );

    testWidgets('a lost connection keeps the session and offers Retry', (
      tester,
    ) async {
      final server = _Server();
      server.routes['GET /auth/v1/user'] = () =>
          Future.error(http.ClientException('offline'));
      await _storeSession(
        server.client,
        DateTime.now().add(const Duration(minutes: 50)),
      );

      await pumpGate(tester, server);

      expect(find.text('Connection needed'), findsOneWidget);
      expect(server.client.auth.currentSession, isNotNull);
      expect(liveActivity.calls, isEmpty);
      expect(homeWidgets.calls, isEmpty);
      expect(
        await preferences.getString(HealthPreferenceKeys(_userId).lastSync),
        isNotNull,
      );
    });

    testWidgets('the intro plays on a cold start only, never on a retry', (
      tester,
    ) async {
      final server = _Server();
      server.routes['GET /auth/v1/user'] = () =>
          Future.error(http.ClientException('offline'));
      await _storeSession(
        server.client,
        DateTime.now().add(const Duration(minutes: 50)),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: Phase2Gate(environment: _environment, client: server.client),
        ),
      );
      expect(find.bySemanticsLabel('Tracend'), findsOneWidget);
      expect(find.text('Restoring your session'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Connection needed'), findsOneWidget);
      expect(find.bySemanticsLabel('Tracend'), findsNothing);

      // The retry waits on Auth: the loader shows, not the intro.
      final answer = Completer<http.Response>();
      server.routes['GET /auth/v1/user'] = () => answer.future;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.bySemanticsLabel('Restoring your session'), findsOneWidget);
      expect(find.bySemanticsLabel('Tracend'), findsNothing);

      answer.completeError(http.ClientException('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Connection needed'), findsOneWidget);
    });
  });

  group('the AI coaching notice', () {
    late _Server server;

    setUp(() async {
      server = _Server()
        ..answer('GET /auth/v1/user', 200, _user())
        ..answer('GET /rest/v1/user_accounts', 200, {
          'onboarding_state': 'completed',
        })
        ..answer('GET /rest/v1/onboarding_drafts', 200, <Object>[])
        ..answer('GET /rest/v1/consent_records', 200, <Object>[]);
      await _storeSession(
        server.client,
        DateTime.now().add(const Duration(minutes: 50)),
      );
    });

    void startOnboarding() => server.answer('GET /rest/v1/user_accounts', 200, {
      'onboarding_state': 'in_progress',
    });

    /// The gate's requests resolve on real time; the signed-in app keeps
    /// animating, so it is pumped for a fixed span instead of settled.
    Future<void> openGate(WidgetTester tester) async {
      await pumpGate(tester, server);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a failed notice call never blocks the gate', (tester) async {
      startOnboarding();
      server.answer('POST /rest/v1/rpc/get_current_ai_notice', 500, {
        'message': 'down',
      });

      await openGate(tester);

      expect(find.byType(OnboardingFlow), findsOneWidget);
      expect(find.text('Connection needed'), findsNothing);
      expect(find.byType(AiCoachingConsentScreen), findsNothing);
      expect(server.requests, isNot(contains('POST /rest/v1/consent_records')));
    });

    testWidgets('a malformed notice never blocks the gate', (tester) async {
      startOnboarding();
      server.answer('POST /rest/v1/rpc/get_current_ai_notice', 200, {
        'version': 'ai-coaching-v6',
      });

      await openGate(tester);

      expect(find.byType(OnboardingFlow), findsOneWidget);
      expect(find.text('Connection needed'), findsNothing);
      expect(find.byType(AiCoachingConsentScreen), findsNothing);
    });

    testWidgets('a notice that loads still asks before the app opens', (
      tester,
    ) async {
      server.answer('POST /rest/v1/rpc/get_current_ai_notice', 200, {
        'version': 'ai-coaching-v6',
        'provider_label': 'Anthropic',
        'body': 'One.',
      });

      await openGate(tester);

      expect(find.byType(AiCoachingConsentScreen), findsOneWidget);
      expect(find.text('Allow AI coaching'), findsOneWidget);
    });
  });

  group('widgets and the rest activity follow every sign-out', () {
    late _Server server;

    setUp(() async {
      server = _Server()
        ..answer('GET /auth/v1/user', 200, _user())
        ..answer('GET /rest/v1/user_accounts', 200, {
          'onboarding_state': 'in_progress',
        })
        ..answer('GET /rest/v1/onboarding_drafts', 200, <Object>[])
        ..answer('GET /rest/v1/consent_records', 200, <Object>[])
        ..answer('GET /rest/v1/deletion_requests', 200, <Object>[])
        ..answer('POST /auth/v1/logout', 204, {});
      await _storeSession(
        server.client,
        DateTime.now().add(const Duration(minutes: 50)),
      );
    });

    /// Opens the gate with an athlete signed in, then forgets what opening
    /// it did to the bridges so only the sign-out shows.
    Future<void> openSignedIn(WidgetTester tester) async {
      await pumpGate(tester, server);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      // The intro covers the app until it has played.
      for (var second = 0; second < 6; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(OnboardingFlow), findsOneWidget);
      homeWidgets.calls.clear();
      liveActivity.calls.clear();
    }

    /// Lets the auth event reach the gate and its bridge calls finish.
    Future<void> settle(WidgetTester tester) async {
      for (var round = 0; round < 3; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(seconds: 1));
      }
    }

    testWidgets('the athlete signing out empties the widgets once', (
      tester,
    ) async {
      await openSignedIn(tester);

      await tester.tap(find.text('Sign out'));
      await settle(tester);

      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(homeWidgets.calls, ['clear']);
      expect(liveActivity.methods, ['end']);
      await expectWidgetChoiceForgotten();
    });

    testWidgets('a deletion settling after its sheet closed empties them', (
      tester,
    ) async {
      await openSignedIn(tester);
      homeWidgets.stored = {'local_date': '2026-10-18'};

      // The sheet was dismissed mid-request, so Account never calls the
      // gate's sign-out; the repository ends the session on its own.
      server.answer('GET /auth/v1/user', 403, _userNotFound);
      final outcome = await tester.runAsync(
        () => SupabaseAccountDeletionRepository(server.client).confirm(),
      );
      await settle(tester);

      expect(outcome, AccountDeletionOutcome.deleted);
      expect(server.client.auth.currentSession, isNull);
      // Account never signed out, yet the gate left the signed-in app.
      expect(find.byType(OnboardingFlow), findsNothing);
      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(homeWidgets.stored, isNull);
      expect(homeWidgets.calls, contains('clear'));
      expect(liveActivity.methods, contains('end'));
      await expectAthleteDataCleared();
    });

    testWidgets('a sign-out during a refresh is not undone by that refresh', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      server.routes['GET /rest/v1/user_accounts'] = () => answer.future;
      await pumpGate(tester, server);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 1));
      // The refresh waits on the onboarding state when the session ends.
      await tester.runAsync(
        () => server.client.auth.signOut(scope: SignOutScope.local),
      );
      await settle(tester);

      answer.complete(_json(200, {'onboarding_state': 'in_progress'}));
      await settle(tester);
      for (var second = 0; second < 6; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsNothing);
      expect(find.byType(TracendLoader), findsNothing);
    });

    testWidgets('a sign-out is not hidden behind Connection needed', (
      tester,
    ) async {
      server.routes['GET /auth/v1/user'] = () =>
          Future.error(http.ClientException('offline'));
      await pumpGate(tester, server);
      await settle(tester);
      expect(find.text('Connection needed'), findsOneWidget);

      await tester.runAsync(
        () => server.client.auth.signOut(scope: SignOutScope.local),
      );
      await settle(tester);

      expect(find.text('Connection needed'), findsNothing);
      expect(find.byType(OwnerAuthScreen), findsOneWidget);
    });

    testWidgets('a clear that failed is tried again at once', (tester) async {
      await openSignedIn(tester);
      homeWidgets.failClears = 1;

      await tester.tap(find.text('Sign out'));
      await settle(tester);

      expect(homeWidgets.calls, ['clear', 'clear']);
      expect(homeWidgets.stored, isNull);
    });

    testWidgets('a launch with no session empties the widgets', (tester) async {
      await pumpGate(tester, _Server());

      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(homeWidgets.calls, ['clear']);
    });

    testWidgets('a session Auth refuses while the app is open empties them', (
      tester,
    ) async {
      await openSignedIn(tester);
      homeWidgets.stored = {'local_date': '2026-10-18'};

      server.answer('POST /auth/v1/token', 400, {
        'code': 'refresh_token_not_found',
        'msg': 'Invalid Refresh Token: Refresh Token Not Found',
      });
      await tester.runAsync(
        () => server.client.auth.refreshSession().then<void>(
          (_) {},
          onError: (_) {},
        ),
      );
      await settle(tester);

      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(homeWidgets.stored, isNull);
      expect(liveActivity.methods, contains('end'));
      await expectAthleteDataKept();
    });
  });

  group('deleting the account', () {
    late _Server server;

    setUp(() async {
      server = _Server()
        ..answer('GET /auth/v1/user', 200, _user())
        ..answer('GET /rest/v1/deletion_requests', 200, <Object>[])
        ..answer(
          'POST /auth/v1/token',
          200,
          _session(DateTime.now().add(const Duration(hours: 1))),
        )
        ..answer('POST /auth/v1/logout', 403, _userNotFound);
      await _storeSession(
        server.client,
        DateTime.now().add(const Duration(minutes: 50)),
      );
    });

    SupabaseAccountDeletionRepository repository() =>
        SupabaseAccountDeletionRepository(
          server.client,
          requestTimeout: const Duration(milliseconds: 50),
          checkInterval: Duration.zero,
          checks: 3,
        );

    test(
      'an unanswered request ends once Auth confirms the deletion',
      () async {
        // The function never answers; meanwhile the server deletes the user.
        server.routes['POST /functions/v1/privacy-delete-account'] = () {
          server.answer('GET /auth/v1/user', 403, _userNotFound);
          return Completer<http.Response>().future;
        };

        final outcome = await repository().delete(
          accountPassword: 'password',
          confirmation: 'DELETE',
        );

        expect(outcome, AccountDeletionOutcome.deleted);
        expect(server.client.auth.currentSession, isNull);
        await expectAthleteDataCleared();
      },
    );

    test('a request still running stays unconfirmed, then confirms', () async {
      server.routes['POST /functions/v1/privacy-delete-account'] = () {
        server.answer('GET /rest/v1/deletion_requests', 200, [
          {
            'status': 'processing',
            'requested_at': DateTime.now().toUtc().toIso8601String(),
            'started_at': DateTime.now().toUtc().toIso8601String(),
          },
        ]);
        return Completer<http.Response>().future;
      };
      final deletion = repository();

      final outcome = await deletion.delete(
        accountPassword: 'password',
        confirmation: 'DELETE',
      );
      expect(outcome, AccountDeletionOutcome.unconfirmed);
      expect(server.client.auth.currentSession, isNotNull);

      server.answer('GET /auth/v1/user', 403, _userNotFound);
      expect(await deletion.confirm(), AccountDeletionOutcome.deleted);
      expect(server.client.auth.currentSession, isNull);
    });

    test('reopening after an interrupted deletion needs no password', () async {
      // The app was closed mid-request and the server finished.
      server.answer('GET /auth/v1/user', 403, _userNotFound);

      final outcome = await repository().delete(
        accountPassword: 'password',
        confirmation: 'DELETE',
      );

      expect(outcome, AccountDeletionOutcome.deleted);
      expect(server.requests, isNot(contains('POST /auth/v1/token')));
      expect(
        server.requests,
        isNot(contains('POST /functions/v1/privacy-delete-account')),
      );
    });

    test('offline, nothing is reported as still finishing', () async {
      Future<http.Response> offline() =>
          Future.error(http.ClientException('offline'));
      server.routes['GET /auth/v1/user'] = offline;
      server.routes['POST /auth/v1/token'] = offline;

      await expectLater(
        repository().delete(
          accountPassword: 'password',
          confirmation: 'DELETE',
        ),
        throwsA(isA<AuthRetryableFetchException>()),
      );
      expect(server.client.auth.currentSession, isNotNull);
    });

    test('a failed deletion reports that the account remains', () async {
      server.routes['POST /functions/v1/privacy-delete-account'] = () async {
        server.answer('GET /rest/v1/deletion_requests', 200, [
          {
            'status': 'failed',
            'requested_at': DateTime.now().toUtc().toIso8601String(),
            'started_at': DateTime.now().toUtc().toIso8601String(),
          },
        ]);
        return _json(503, {'error': 'deletion_failed'});
      };

      await expectLater(
        repository().delete(
          accountPassword: 'password',
          confirmation: 'DELETE',
        ),
        throwsA(isA<AccountDeletionFailed>()),
      );
      expect(server.client.auth.currentSession, isNotNull);
    });

    test('a deletion whose worker stopped can be sent again', () async {
      final stale = DateTime.now()
          .subtract(const Duration(minutes: 30))
          .toUtc()
          .toIso8601String();
      server.answer('GET /rest/v1/deletion_requests', 200, [
        {'status': 'processing', 'requested_at': stale, 'started_at': stale},
      ]);
      server.routes['POST /functions/v1/privacy-delete-account'] = () async =>
          _json(200, {'schema_version': '1.0', 'status': 'completed'});

      final outcome = await repository().delete(
        accountPassword: 'password',
        confirmation: 'DELETE',
      );

      expect(outcome, AccountDeletionOutcome.deleted);
      expect(
        server.requests,
        contains('POST /functions/v1/privacy-delete-account'),
      );
    });
  });

  testWidgets('the sheet offers Check again until the server confirms', (
    tester,
  ) async {
    final deletion = _UnconfirmedDeletion();
    AccountDeletionOutcome? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<AccountDeletionOutcome>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => AccountDeletionSheet(repository: deletion),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'password');
    await tester.enterText(find.byType(TextField).at(1), 'DELETE');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Permanently delete account'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not been confirmed yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check again'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Check again'));
    await tester.pumpAndSettle();

    expect(result, AccountDeletionOutcome.deleted);
  });
}

class _UnconfirmedDeletion implements AccountDeletionRepository {
  @override
  Future<AccountDeletionOutcome> delete({
    required String accountPassword,
    required String confirmation,
  }) async => AccountDeletionOutcome.unconfirmed;

  @override
  Future<AccountDeletionOutcome> confirm() async =>
      AccountDeletionOutcome.deleted;
}
