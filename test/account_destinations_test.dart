import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/coach/coach_repository.dart';

void main() {
  testWidgets('Profile, AI usage, and consent destinations open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
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

    await tester.tap(find.text('Profile and goals'));
    await tester.pumpAndSettle();
    expect(find.text('Your coaching foundation'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('AI service not configured'),
      250,
    );
    await tester.tap(find.text('AI service not configured'));
    await tester.pumpAndSettle();
    expect(find.text('My AI usage'), findsOneWidget);
    expect(find.textContaining('Operational estimates'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Privacy and AI processing'),
      250,
    );
    await tester.tap(find.text('Privacy and AI processing'));
    await tester.pumpAndSettle();
    expect(find.text('Consent ledger'), findsOneWidget);
    expect(find.text('No consent records yet'), findsOneWidget);
  });

  testWidgets('AI usage row shows an honest error state when the RPC fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: AccountScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: 'https://example.supabase.co',
            supabasePublishableKey: 'test-key',
          ),
          coach: _FailingCoachRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('AI usage unavailable'), 250);
    expect(find.text('AI usage unavailable'), findsOneWidget);
    expect(find.text('Open details to retry'), findsOneWidget);
  });
}

class _FailingCoachRepository implements CoachRepository {
  @override
  Future<CoachDecision?> loadLatest() async => null;
  @override
  Future<CoachDecision> generate() => throw StateError('not needed');
  @override
  Future<Map<String, dynamic>> loadUsage() async => throw StateError('offline');
}
