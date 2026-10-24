import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/health/health_repository.dart';

const _configured = AppEnvironment(
  name: 'test',
  supabaseUrl: 'https://tracend-test.supabase.co',
  supabasePublishableKey: 'publishable-test',
);

/// postgrest-dart sorts descending unless told otherwise, and a goal's
/// priority 1 is the top one: both Account reads of the active goal must ask
/// for ascending priority.
void main() {
  testWidgets('both Account reads of the active goal take priority 1 first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final goalOrders = <String?>[];
    await tester.runAsync(
      () => Supabase.initialize(
        url: _configured.supabaseUrl,
        publishableKey: _configured.supabasePublishableKey,
        httpClient: MockClient((request) async {
          if (request.url.path == '/rest/v1/user_goals') {
            goalOrders.add(
              request.url.queryParameters['order']?.replaceAll(
                '.nullslast',
                '',
              ),
            );
          }
          final single =
              request.headers['Accept']?.contains('vnd.pgrst.object') == true;
          return http.Response(
            jsonEncode(single ? <String, Object?>{} : <Object>[]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          localStorage: const EmptyLocalStorage(),
        ),
      ),
    );
    addTearDown(Supabase.instance.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: AccountScreen(
          environment: _configured,
          coach: const FixtureCoachRepository(),
          health: const ManualHealthRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(goalOrders, ['priority.asc']);

    await tester.tap(find.text('Profile and goals'));
    await tester.pumpAndSettle();
    expect(goalOrders, ['priority.asc', 'priority.asc']);
  });
}
