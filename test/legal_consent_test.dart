import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/notification_repository.dart';
import 'package:tracend/features/account/widgets/account_sheets.dart';
import 'package:tracend/features/auth/owner_auth_screen.dart';
import 'package:tracend/features/auth/phase_2_gate.dart';
import 'package:tracend/features/consent/ai_coaching_consent.dart';
import 'package:tracend/features/consent/legal_consent.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'home_widgets/fake_home_widget_bridge.dart';
import 'live_activity/fake_workout_activity_bridge.dart';

const _url = 'https://tracend-test.supabase.co';
const _userId = '11111111-1111-4111-8111-111111111111';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: _url,
  supabasePublishableKey: 'publishable-test',
);

/// Records every page the app asks the platform to open.
class _Launcher extends UrlLauncherPlatform {
  final launched = <(String, PreferredLaunchMode)>[];

  /// Whether the platform reports the page as opened.
  var opens = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    return opens;
  }
}

/// Records grants; fails them while [fails] is set.
class _Repository implements LegalConsentRepository {
  final granted = <Set<LegalConsent>>[];
  var fails = false;

  @override
  Future<Set<LegalConsent>> loadOutdated() async => const {};

  @override
  Future<void> grant(Set<LegalConsent> consents) async {
    if (fails) throw const PostgrestException(message: 'down', code: '500');
    granted.add(consents);
  }
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

Map<String, dynamic> _row(String type, String version, {String? action}) => {
  'consent_type': type,
  'notice_version': version,
  'action': action ?? 'granted',
};

const _rowLabels = [
  'I accept the private-beta terms',
  'I have read the privacy notice',
  'I agree to Tracend using my health data',
];

Future<void> _tickAll(WidgetTester tester) async {
  for (final label in _rowLabels) {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }
}

/// Scrolls the screen until [text] is built and on screen, then taps it.
Future<void> _tapBelow(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
}

FilledButton _agreeButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Agree and continue'),
);

/// Scripted Supabase endpoints for the account check. The legal lookup
/// (`consent_type=in.(...)`) answers [legal]; every request is recorded, and
/// every insert's body.
class _Server {
  _Server({required this.legal});

  final Future<http.Response> Function() legal;
  final requests = <String>[];
  final inserted = <Object?>[];

  late final client = SupabaseClient(
    _url,
    'publishable-test',
    httpClient: MockClient((request) async {
      final route = '${request.method} ${request.url.path}';
      requests.add(route);
      final response = await _answer(route, request);
      return http.Response(
        response.body,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  Future<http.Response> _answer(String route, http.Request request) async {
    switch (route) {
      case 'GET /auth/v1/user':
        return _json(200, _user());
      case 'POST /auth/v1/logout':
        return http.Response('', 204);
      case 'GET /rest/v1/user_accounts':
        return _json(200, {'onboarding_state': 'completed'});
      // An AI notice nobody answered yet: its screen is what opens next.
      case 'POST /rest/v1/rpc/get_current_ai_notice':
        return _json(200, {
          'version': 'ai-coaching-v6',
          'provider_label': 'Anthropic',
          'body': 'One.',
        });
      case 'GET /rest/v1/consent_records':
        final type = request.url.queryParameters['consent_type'] ?? '';
        if (type.startsWith('in.')) return legal();
        return _json(200, <Object>[]);
      case 'POST /rest/v1/consent_records':
        inserted.add(jsonDecode(request.body));
        return _json(201, <Object>[]);
    }
    return _json(404, {'message': route});
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

Map<String, dynamic> _user() => {
  'id': _userId,
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

Future<void> _storeSession(SupabaseClient client) =>
    client.auth.setInitialSession(
      jsonEncode({
        'access_token': _accessToken(
          DateTime.now().add(const Duration(minutes: 50)),
        ),
        'expires_in': 3600,
        'refresh_token': 'refresh-test',
        'token_type': 'bearer',
        'user': _user(),
      }),
    );

void main() {
  late _Launcher launcher;

  setUp(() {
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('which agreements are asked again', () {
    test('none recorded asks for all three', () {
      expect(outdatedLegalConsents(const []), LegalConsent.values.toSet());
    });

    test('a grant of an older page asks again; the newest record decides', () {
      final outdated = outdatedLegalConsents([
        _row('terms', LegalNotices.termsVersion),
        _row('privacy', '2026-07-01'),
        _row('health_data', LegalNotices.privacyVersion),
        _row('terms', '2026-07-01'),
      ]);
      expect(outdated, {LegalConsent.privacy});
    });

    test('a withdrawal asks again', () {
      final outdated = outdatedLegalConsents([
        _row('terms', LegalNotices.termsVersion),
        _row('privacy', LegalNotices.privacyVersion),
        _row('health_data', LegalNotices.privacyVersion, action: 'withdrawn'),
        _row('health_data', LegalNotices.privacyVersion),
      ]);
      expect(outdated, {LegalConsent.healthData});
    });

    test('a grant of a newer page, from a later build, still counts', () {
      final outdated = outdatedLegalConsents([
        _row('terms', '2099-01-01'),
        _row('privacy', '2099-01-01'),
        _row('health_data', '2099-01-01'),
      ]);
      expect(outdated, isEmpty);
    });
  });

  group('the consent rows', () {
    Future<Set<LegalConsent>> pumpRows(WidgetTester tester) async {
      final checked = <LegalConsent>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ListView(
                children: [
                  LegalConsentRows(
                    checked: checked,
                    onChanged: (consent, value) => setState(() {
                      value ? checked.add(consent) : checked.remove(consent);
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return checked;
    }

    testWidgets('three separate rows, all unticked at first', (tester) async {
      final checked = await pumpRows(tester);
      final semantics = tester.ensureSemantics();

      for (final label in _rowLabels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(checked, isEmpty);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(RegExp('^I agree to Tracend using my health')),
        ),
        matchesSemantics(
          label:
              'I agree to Tracend using my health data. My Apple Health '
              'data, check-ins, pain reports, body measurements and photos, '
              'used to coach me as the privacy notice describes.',
          hasCheckedState: true,
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text('I agree to Tracend using my health data'));
      await tester.pump();
      expect(checked, {LegalConsent.healthData});
      semantics.dispose();
    });

    testWidgets('the links open the hosted pages in the in-app browser', (
      tester,
    ) async {
      final checked = await pumpRows(tester);

      await tester.tap(find.text('Read the beta terms'));
      await tester.pump();
      await tester.tap(find.text('Read the privacy notice'));
      await tester.pump();

      expect(launcher.launched, [
        (
          'https://tracend.pages.dev/beta-terms/',
          PreferredLaunchMode.inAppBrowserView,
        ),
        (
          'https://tracend.pages.dev/privacy/',
          PreferredLaunchMode.inAppBrowserView,
        ),
      ]);
      expect(checked, isEmpty, reason: 'opening a page ticks nothing');
    });

    testWidgets('a page that opens nowhere says where it lives', (
      tester,
    ) async {
      launcher.opens = false;
      await pumpRows(tester);

      await tester.tap(find.text('Read the privacy notice'));
      await tester.pump();

      expect(launcher.launched.map((launch) => launch.$2), [
        PreferredLaunchMode.inAppBrowserView,
        PreferredLaunchMode.externalApplication,
      ]);
      expect(
        find.text('The page did not open. It is at tracend.pages.dev/privacy/'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('Account opens both pages at any time', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const AccountScreen(
          environment: AppEnvironment(
            name: 'test',
            supabaseUrl: '',
            supabasePublishableKey: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapBelow(tester, 'Privacy notice');
    await tester.pump();
    await _tapBelow(tester, 'Beta terms');
    await tester.pump();

    expect(launcher.launched, [
      (
        'https://tracend.pages.dev/privacy/',
        PreferredLaunchMode.inAppBrowserView,
      ),
      (
        'https://tracend.pages.dev/beta-terms/',
        PreferredLaunchMode.inAppBrowserView,
      ),
    ]);
  });

  group('the re-consent screen', () {
    late _Repository repository;
    late int agreed;
    late int signedOut;

    Future<void> pumpScreen(WidgetTester tester) async {
      repository = _Repository();
      agreed = 0;
      signedOut = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: LegalConsentScreen(
            repository: repository,
            outdated: const {LegalConsent.privacy, LegalConsent.healthData},
            onAgreed: () => agreed++,
            onSignOut: () async => signedOut++,
            deletion: const FixtureAccountDeletionRepository(),
          ),
        ),
      );
    }

    testWidgets('Agree waits for all three rows, then records what changed', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(_agreeButton(tester).onPressed, isNull);

      await tester.tap(find.text(_rowLabels[0]));
      await tester.tap(find.text(_rowLabels[1]));
      await tester.pump();
      expect(_agreeButton(tester).onPressed, isNull);
      expect(repository.granted, isEmpty);

      await tester.tap(find.text(_rowLabels[2]));
      await tester.pump();
      await tester.tap(find.text('Agree and continue'));
      await tester.pump();

      expect(repository.granted, [
        {LegalConsent.privacy, LegalConsent.healthData},
      ]);
      expect(agreed, 1);
    });

    testWidgets('a failed save keeps the screen and says so', (tester) async {
      await pumpScreen(tester);
      repository.fails = true;
      await _tickAll(tester);

      await tester.tap(find.text('Agree and continue'));
      await tester.pump();

      expect(agreed, 0);
      expect(
        find.text(
          'Your agreement was not saved. Check the connection and try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Sign out leaves without agreeing', (tester) async {
      await pumpScreen(tester);

      await _tapBelow(tester, 'Sign out');
      await tester.pump();

      expect(signedOut, 1);
      expect(repository.granted, isEmpty);
    });

    testWidgets('Delete account opens the account deletion sheet', (
      tester,
    ) async {
      await pumpScreen(tester);

      await _tapBelow(tester, 'Delete account');
      await tester.pumpAndSettle();

      expect(find.byType(AccountDeletionSheet), findsOneWidget);
      expect(repository.granted, isEmpty);
    });
  });

  // What opens after the gate's legal check stands for the app: the AI
  // coaching question, which the scripted server leaves unanswered.
  group('the gate asks again after a page changes', () {
    Future<void> openGate(WidgetTester tester, _Server server) async {
      await _storeSession(server.client);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: Phase2Gate(
            environment: _environment,
            client: server.client,
            liveActivity: FakeWorkoutActivityBridge(),
            homeWidgets: FakeHomeWidgetBridge(),
            notifications: _Notifications(),
          ),
        ),
      );
      // The intro covers the app until it has played; the account check's
      // requests resolve on real time meanwhile.
      for (var second = 0; second < 6; second++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(seconds: 1));
      }
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('an athlete who agreed to older pages agrees again first', (
      tester,
    ) async {
      final server = _Server(
        legal: () async => _json(200, [
          _row('terms', '2026-07-01'),
          _row('privacy', '2026-07-01'),
        ]),
      );
      await openGate(tester, server);

      expect(find.byType(LegalConsentScreen), findsOneWidget);
      expect(find.byType(AiCoachingConsentScreen), findsNothing);
      expect(server.inserted, isEmpty);

      await _tickAll(tester);
      await tester.tap(find.text('Agree and continue'));
      await settle(tester);

      expect(server.inserted, [
        [
          for (final (type, version) in [
            ('terms', LegalNotices.termsVersion),
            ('privacy', LegalNotices.privacyVersion),
            ('health_data', LegalNotices.privacyVersion),
          ])
            {
              'user_id': _userId,
              'consent_type': type,
              'notice_version': version,
              'action': 'granted',
              'source': 'ios_app',
            },
        ],
      ]);
      expect(find.byType(LegalConsentScreen), findsNothing);
      expect(find.byType(AiCoachingConsentScreen), findsOneWidget);
    });

    testWidgets('current agreements open the app', (tester) async {
      final server = _Server(
        legal: () async => _json(200, [
          _row('health_data', LegalNotices.privacyVersion),
          _row('privacy', LegalNotices.privacyVersion),
          _row('terms', LegalNotices.termsVersion),
        ]),
      );
      await openGate(tester, server);

      expect(find.byType(LegalConsentScreen), findsNothing);
      expect(find.byType(AiCoachingConsentScreen), findsOneWidget);
    });

    testWidgets('a lookup the server refuses opens the app and records '
        'nothing', (tester) async {
      final server = _Server(
        legal: () async => _json(500, {'message': 'down'}),
      );
      await openGate(tester, server);

      expect(find.byType(LegalConsentScreen), findsNothing);
      expect(find.text('Connection needed'), findsNothing);
      expect(find.byType(AiCoachingConsentScreen), findsOneWidget);
      expect(server.requests, isNot(contains('POST /rest/v1/consent_records')));
    });

    testWidgets('a lookup with no signal opens the app and records nothing', (
      tester,
    ) async {
      final server = _Server(
        legal: () async => throw http.ClientException('offline'),
      );
      await openGate(tester, server);
      // The client retries a read that found no signal before it fails.
      for (var second = 0; second < 25; second++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.byType(LegalConsentScreen), findsNothing);
      expect(find.byType(AiCoachingConsentScreen), findsOneWidget);
      expect(server.requests, isNot(contains('POST /rest/v1/consent_records')));
    });

    testWidgets('Sign out from the screen goes back to sign-in', (
      tester,
    ) async {
      final server = _Server(legal: () async => _json(200, <Object>[]));
      await openGate(tester, server);
      expect(find.byType(LegalConsentScreen), findsOneWidget);

      await _tapBelow(tester, 'Sign out');
      await settle(tester);
      await settle(tester);

      expect(find.byType(OwnerAuthScreen), findsOneWidget);
      expect(server.inserted, isEmpty);
    });
  });
}
