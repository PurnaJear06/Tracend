import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/account_screen.dart';

void main() {
  testWidgets(
    'account deletion requires password and exact destructive phrase',
    (tester) async {
      final repository = _DeletionRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: AccountScreen(
            environment: const AppEnvironment(
              name: 'test',
              supabaseUrl: '',
              supabasePublishableKey: '',
            ),
            deletion: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Delete account'), 300);
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot be undone'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'account-password');
      await tester.enterText(find.byType(TextField).at(1), 'DELETE');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Permanently delete account'),
      );
      await tester.pumpAndSettle();

      expect(repository.deleted, isTrue);
    },
  );
}

class _DeletionRepository implements AccountDeletionRepository {
  bool deleted = false;

  @override
  Future<void> delete({
    required String accountPassword,
    required String confirmation,
  }) async {
    expect(accountPassword, 'account-password');
    expect(confirmation, 'DELETE');
    deleted = true;
  }
}
