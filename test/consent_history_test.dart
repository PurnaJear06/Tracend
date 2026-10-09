import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/widgets/consent_history_screen.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';

Widget _wrap(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? TracendTheme.dark, home: child);

ConsentRecord _record(
  String type,
  String action,
  DateTime createdAt, {
  String version = 'v1',
  String source = 'ios_app',
}) => ConsentRecord(
  consentType: type,
  noticeVersion: version,
  action: action,
  source: source,
  createdAt: createdAt,
);

void main() {
  testWidgets('shows the brand loader while records resolve', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConsentHistoryScreen(
          load: () => Completer<List<ConsentRecord>>().future,
        ),
      ),
    );
    expect(find.byType(TracendLoader), findsOneWidget);
    expect(find.text('Consent history'), findsOneWidget);
  });

  testWidgets('shows the latest choice per purpose with its date first', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ConsentHistoryScreen(
          load: () async => [
            _record('progress_photo_ai', 'granted', DateTime(2026, 8, 1)),
            _record('terms', 'granted', DateTime(2026, 7, 1)),
            _record(
              'privacy',
              'granted',
              DateTime(2026, 7, 1),
              source: 'owner_development',
            ),
            _record(
              'ai_coaching',
              'granted',
              DateTime(2026, 9, 2),
              version: 'ai-coaching-v1',
            ),
            _record('progress_photo_ai', 'withdrawn', DateTime(2026, 8, 20)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('AI coaching'), findsOneWidget);
    expect(find.text('Progress photo storage'), findsOneWidget);
    expect(find.text('Progress photo AI analysis'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);

    // The date reads first; the version id is secondary text.
    expect(
      find.text('Withdrawn 20 Aug 2026\nVersion v1 · iOS app'),
      findsOneWidget,
    );
    expect(
      find.text('Granted 2 Sep 2026\nVersion ai-coaching-v1 · iOS app'),
      findsOneWidget,
    );
    expect(
      find.text('Granted 1 Jul 2026\nVersion v1 · Set up during testing'),
      findsOneWidget,
    );
    expect(find.textContaining('owner development'), findsNothing);
    expect(find.text('Meal photo AI analysis'), findsOneWidget);
    expect(find.text('No choice recorded yet'), findsNWidgets(3));
    expect(find.textContaining('Append-only'), findsNothing);
  });

  testWidgets('empty history shows an honest empty state', (tester) async {
    await tester.pumpWidget(
      _wrap(ConsentHistoryScreen(load: () async => const [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('No consent choices yet'), findsOneWidget);
    expect(find.text('Terms of use'), findsNothing);
  });

  testWidgets('load failure keeps consent unchanged', (tester) async {
    await tester.pumpWidget(_wrap(ConsentHistoryScreen(load: _failingRecords)));
    await tester.pumpAndSettle();

    expect(find.text('Consent history could not load'), findsOneWidget);
    expect(
      find.textContaining('Your saved consent was not changed'),
      findsOneWidget,
    );
  });

  for (final theme in [TracendTheme.dark, TracendTheme.light]) {
    testWidgets('dates lay out at 320pt × 2 text (${theme.brightness.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _wrap(
          theme: theme,
          ConsentHistoryScreen(
            load: () async => [
              _record(
                'progress_photo_storage',
                'granted',
                DateTime(2026, 9, 30),
                version: 'progress-photo-storage-v2',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Granted 30 Sep 2026\nVersion progress-photo-storage-v2 · iOS app',
        ),
        findsOneWidget,
      );
    });
  }
}

Future<List<ConsentRecord>> _failingRecords() async =>
    throw StateError('offline');
