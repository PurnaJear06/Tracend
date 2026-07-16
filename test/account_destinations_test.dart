import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';

void main() {
  testWidgets('Profile and AI usage destinations open', (tester) async {
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

    await tester.scrollUntilVisible(find.textContaining('AI usage'), 250);
    await tester.tap(find.textContaining('AI usage'));
    await tester.pumpAndSettle();
    expect(find.text('Qwen owner test'), findsOneWidget);
    expect(find.textContaining('estimated this month'), findsOneWidget);
  });
}
