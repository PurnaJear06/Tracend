import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';

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
}
