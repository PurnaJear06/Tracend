import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/widgets/consent_ledger_screen.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: TracendTheme.dark, home: child);

ConsentRecord _record(
  String type,
  String action,
  DateTime createdAt, {
  String version = 'v1',
}) => ConsentRecord(
  consentType: type,
  noticeVersion: version,
  action: action,
  source: 'ios_app',
  createdAt: createdAt,
);

void main() {
  testWidgets('shows a spinner while records resolve', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConsentLedgerScreen(
          load: () => Completer<List<ConsentRecord>>().future,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the latest record per purpose', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConsentLedgerScreen(
          load: () async => [
            _record('progress_photo_ai', 'withdrawn', DateTime(2026, 8, 20)),
            _record('terms', 'granted', DateTime(2026, 7, 1)),
            _record('privacy', 'granted', DateTime(2026, 7, 1)),
            _record('progress_photo_ai', 'granted', DateTime(2026, 8, 1)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Progress photo storage'), findsOneWidget);
    expect(find.text('Progress photo AI analysis'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);

    expect(find.text('Granted'), findsNWidgets(2));
    expect(find.text('Withdrawn'), findsOneWidget);
    expect(find.textContaining('Withdrawn · 20/8/2026 · v1'), findsOneWidget);
    expect(find.text('No record yet'), findsNWidgets(2));
  });

  testWidgets('empty ledger shows an honest empty state', (tester) async {
    await tester.pumpWidget(
      _wrap(ConsentLedgerScreen(load: () async => const [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('No consent records yet'), findsOneWidget);
    expect(find.text('Terms of use'), findsNothing);
  });

  testWidgets('load failure keeps consent unchanged', (tester) async {
    await tester.pumpWidget(_wrap(ConsentLedgerScreen(load: _failingRecords)));
    await tester.pumpAndSettle();

    expect(find.text('Consent records could not load'), findsOneWidget);
    expect(
      find.textContaining('Your saved consent was not changed'),
      findsOneWidget,
    );
  });
}

Future<List<ConsentRecord>> _failingRecords() async =>
    throw StateError('offline');
