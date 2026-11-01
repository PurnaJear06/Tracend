import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/auth_options.dart';

const _url = 'https://tracend-test.supabase.co';
const _athleteId = '11111111-1111-4111-8111-111111111111';
const _otherId = '22222222-2222-4222-8222-222222222222';

/// The channel the links that open the app arrive on (app_links).
const _links = EventChannel('com.llfbandit.app_links/events');

String _accessToken(String userId) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  return [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': userId, 'exp': exp}),
    'test-signature',
  ].join('.');
}

Map<String, Object?> _user(String id) => {
  'id': id,
  'aud': 'authenticated',
  'role': 'authenticated',
  'app_metadata': <String, Object?>{},
  'user_metadata': <String, Object?>{},
  'created_at': '2026-10-01T00:00:00Z',
};

/// A link holding another account's tokens, as a crafted page or QR code
/// would open it.
String _tokenLink() =>
    'tracend://today#access_token=${_accessToken(_otherId)}'
    '&expires_in=3600&refresh_token=other-refresh&token_type=bearer';

void main() {
  late List<String> authRequests;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Starts the app's Supabase client with [options] while a link holding
  /// another account's tokens arrives, as it does when a link opens the app. Auth answers every user lookup
  /// with the other account.
  Future<void> start(
    WidgetTester tester,
    FlutterAuthClientOptions options, {
    String? storedSessionOf,
  }) async {
    authRequests = [];
    await tester.runAsync(() async {
      // Set up in the real zone, where the client's link listener runs.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            _links,
            MockStreamHandler.inline(
              onListen: (arguments, events) => events.success(_tokenLink()),
            ),
          );
      await Supabase.initialize(
        url: _url,
        publishableKey: 'publishable-test',
        httpClient: MockClient((request) async {
          authRequests.add(request.url.path);
          return http.Response(
            jsonEncode(_user(_otherId)),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
        authOptions: options.copyWith(autoRefreshToken: false),
      );
      if (storedSessionOf != null) {
        await Supabase.instance.client.auth.setInitialSession(
          jsonEncode({
            'access_token': _accessToken(storedSessionOf),
            'expires_in': 3600,
            'refresh_token': 'athlete-refresh',
            'token_type': 'bearer',
            'user': _user(storedSessionOf),
          }),
        );
      }
      // The link is handled after the start returns.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    addTearDown(Supabase.instance.dispose);
  }

  testWidgets('with the library default, such a link signs the phone in '
      '(the harness delivers the link)', (tester) async {
    await start(
      tester,
      const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
    );

    expect(authRequests, contains('/auth/v1/user'));
    expect(Supabase.instance.client.auth.currentUser?.id, _otherId);
  });

  testWidgets('the app never takes a session from a link', (tester) async {
    await start(tester, tracendAuthOptions(const EmptyLocalStorage()));

    expect(authRequests, isEmpty);
    expect(Supabase.instance.client.auth.currentSession, isNull);
  });

  testWidgets('a signed-in athlete stays signed in as themselves', (
    tester,
  ) async {
    await start(
      tester,
      tracendAuthOptions(const EmptyLocalStorage()),
      storedSessionOf: _athleteId,
    );

    expect(authRequests, isEmpty);
    expect(Supabase.instance.client.auth.currentUser?.id, _athleteId);
  });
}
