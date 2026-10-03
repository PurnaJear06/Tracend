import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/notification_repository.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

Future<void> _pumpAccount(
  WidgetTester tester,
  NotificationRepository repository, {
  ThemeData? theme,
  Size size = const Size(390, 844),
  double textScale = 1,
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
      home: AccountScreen(environment: _environment, notifications: repository),
    ),
  );
  await tester.pumpAndSettle();
}

/// The switch inside the row titled [title].
Finder _switchFor(String title) => find.descendant(
  of: find.ancestor(
    of: find.text(title),
    matching: find.byType(MergeSemantics),
  ),
  matching: find.byType(Switch),
);

Future<void> _toggle(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    _switchFor(title),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(_switchFor(title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'reminder switches apply at once and keep lock-screen copy generic',
    (tester) async {
      final repository = _NotificationRepository();
      await _pumpAccount(tester, repository);

      await tester.scrollUntilVisible(
        find.textContaining('Lock-screen text stays generic'),
        200,
      );
      expect(
        find.textContaining('Lock-screen text stays generic'),
        findsOneWidget,
      );

      await _toggle(tester, 'Daily check-in reminder');
      expect(repository.calls, 1);
      await _toggle(tester, 'Weekly review reminder');
      expect(repository.calls, 2);

      expect(repository.dailyCheckIn, isTrue);
      expect(repository.weeklyReview, isTrue);
      expect(repository.restTimerAlerts, isFalse);
      expect(
        tester.widget<Switch>(_switchFor('Weekly review reminder')).value,
        isTrue,
      );
    },
  );

  testWidgets(
    'rest timer alerts show the lock-screen text before iOS asks, at 320pt × 2',
    (tester) async {
      final repository = _NotificationRepository();
      await _pumpAccount(
        tester,
        repository,
        theme: TracendTheme.dark,
        size: const Size(320, 844),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);

      // The row itself names the lock-screen text.
      await tester.scrollUntilVisible(
        find.textContaining('“Rest timer finished”'),
        200,
      );
      expect(find.text('Rest timer alerts'), findsOneWidget);

      // Not now: nothing is asked and the timer stays in the app.
      await _toggle(tester, 'Rest timer alerts');
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CupertinoActionSheet),
          matching: find.textContaining('“Rest timer finished”'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(repository.calls, 0);
      expect(
        tester.widget<Switch>(_switchFor('Rest timer alerts')).value,
        isFalse,
      );

      // Continue: only then is permission requested, through configure.
      await _toggle(tester, 'Rest timer alerts');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(repository.restTimerAlerts, isTrue);
      expect(
        tester.widget<Switch>(_switchFor('Rest timer alerts')).value,
        isTrue,
      );

      // Once iOS allows notifications, turning it off and on asks nothing.
      await _toggle(tester, 'Rest timer alerts');
      expect(repository.restTimerAlerts, isFalse);
      await _toggle(tester, 'Rest timer alerts');
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(repository.restTimerAlerts, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('denied permission keeps the rest timer in the app', (
    tester,
  ) async {
    final repository = _NotificationRepository(deny: true);
    await _pumpAccount(tester, repository);

    await _toggle(tester, 'Rest timer alerts');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('so the rest timer stays in the app'),
      findsOneWidget,
    );
    expect(
      tester.widget<Switch>(_switchFor('Rest timer alerts')).value,
      isFalse,
    );
  });
}

class _NotificationRepository implements NotificationRepository {
  _NotificationRepository({this.deny = false});

  final bool deny;
  int calls = 0;
  bool dailyCheckIn = false;
  bool weeklyReview = false;
  bool restTimerAlerts = false;

  @override
  Future<NotificationPreferences> load() async => const NotificationPreferences(
    authorizationStatus: 'not_determined',
    dailyCheckIn: false,
    weeklyReview: false,
  );

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) async {
    calls += 1;
    if (deny) throw PlatformException(code: 'permission_denied');
    this.dailyCheckIn = dailyCheckIn;
    this.weeklyReview = weeklyReview;
    restTimerAlerts = restTimerAlertsEnabled;
    return NotificationPreferences(
      authorizationStatus: 'authorized',
      dailyCheckIn: dailyCheckIn,
      weeklyReview: weeklyReview,
      restTimerAlertsEnabled: restTimerAlertsEnabled,
    );
  }
}
