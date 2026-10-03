import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_deletion_repository.dart';
import 'package:tracend/features/account/account_screen.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

Future<void> _openDeletion(
  WidgetTester tester,
  _DeletionRepository repository, {
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? TracendTheme.light,
      home: AccountScreen(environment: _environment, deletion: repository),
    ),
  );
  await tester.pumpAndSettle();
  final row = find.text('Delete account');
  await tester.scrollUntilVisible(row, 300);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'account-password');
  await tester.enterText(find.byType(TextField).at(1), 'DELETE');
  final submit = find.widgetWithText(
    FilledButton,
    'Permanently delete account',
  );
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Finder _confirmAction(String label) => find.descendant(
  of: find.byType(CupertinoAlertDialog),
  matching: find.text(label),
);

void main() {
  testWidgets(
    'account deletion requires password, the exact phrase and a destructive confirm',
    (tester) async {
      final repository = _DeletionRepository();
      await _openDeletion(tester, repository);

      expect(find.textContaining('cannot be undone'), findsOneWidget);
      await _fillAndSubmit(tester);

      // The destructive confirm names the outcome; nothing is sent yet.
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(repository.deleted, isFalse);
      await tester.tap(_confirmAction('Delete account'));
      await tester.pumpAndSettle();

      expect(repository.deleted, isTrue);
      expect(find.text('Your account was deleted'), findsOneWidget);
    },
  );

  testWidgets('cancelling the confirm sends nothing', (tester) async {
    final repository = _DeletionRepository();
    await _openDeletion(tester, repository);
    await _fillAndSubmit(tester);

    await tester.tap(_confirmAction('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isFalse);
    expect(find.text('Delete your account?'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Permanently delete account'),
      findsOneWidget,
    );
  });

  testWidgets('a wrong phrase never reaches the confirm', (tester) async {
    final repository = _DeletionRepository();
    await _openDeletion(tester, repository);
    await tester.enterText(find.byType(TextField).at(0), 'account-password');
    await tester.enterText(find.byType(TextField).at(1), 'delete me');
    final submit = find.widgetWithText(
      FilledButton,
      'Permanently delete account',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(
      find.text('Enter your password and type DELETE exactly.'),
      findsOneWidget,
    );
  });

  for (final theme in [TracendTheme.dark, TracendTheme.light]) {
    testWidgets(
      'the deletion sheet and confirm lay out at 320pt × 2 (${theme.brightness.name})',
      (tester) async {
        final repository = _DeletionRepository();
        await _openDeletion(
          tester,
          repository,
          size: const Size(320, 844),
          textScale: 2,
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        await _fillAndSubmit(tester);
        expect(find.text('Delete your account?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _DeletionRepository implements AccountDeletionRepository {
  bool deleted = false;

  @override
  Future<AccountDeletionOutcome> delete({
    required String accountPassword,
    required String confirmation,
  }) async {
    expect(accountPassword, 'account-password');
    expect(confirmation, 'DELETE');
    deleted = true;
    return AccountDeletionOutcome.deleted;
  }

  @override
  Future<AccountDeletionOutcome> confirm() async =>
      AccountDeletionOutcome.deleted;
}
