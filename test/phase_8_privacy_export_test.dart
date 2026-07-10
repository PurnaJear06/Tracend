import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/privacy_export_repository.dart';

void main() {
  testWidgets(
    'export requires reauthentication and a separate strong password',
    (tester) async {
      final repository = _ExportRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.light,
          home: AccountScreen(
            environment: const AppEnvironment(
              name: 'test',
              supabaseUrl: '',
              supabasePublishableKey: '',
            ),
            exports: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Export data'), 300);
      await tester.tap(find.text('Export data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('JSON and CSV'), findsOneWidget);
      expect(
        find.textContaining('seven days or three downloads'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(0), 'account-password');
      await tester.enterText(
        find.byType(TextField).at(1),
        'export-password-strong',
      );
      await tester.tap(find.text('Authenticate and prepare'));
      await tester.pumpAndSettle();

      expect(repository.requested, isTrue);
      expect(find.text('Ready · 0 of 3 downloads used'), findsOneWidget);
      await tester.tap(find.text('Open secure download'));
      await tester.pumpAndSettle();
      expect(repository.downloaded, isTrue);
    },
  );
}

class _ExportRepository implements PrivacyExportRepository {
  bool requested = false;
  bool downloaded = false;

  @override
  Future<PrivacyExport?> load() async => null;

  @override
  Future<PrivacyExport> request({
    required String accountPassword,
    required String exportPassword,
  }) async {
    requested = true;
    expect(accountPassword, 'account-password');
    expect(exportPassword, 'export-password-strong');
    return const PrivacyExport(id: 'export-id', status: 'ready', byteSize: 42);
  }

  @override
  Future<void> download(String exportId) async {
    downloaded = true;
    expect(exportId, 'export-id');
  }
}
