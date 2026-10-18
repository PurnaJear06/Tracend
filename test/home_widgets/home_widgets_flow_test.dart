import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/shell/app_shell.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';

import 'fake_home_widget_bridge.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late FakeHomeWidgetBridge bridge;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    bridge = FakeHomeWidgetBridge();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    _phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: AppShell(environment: _environment, homeWidgets: bridge),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Today feeds the widgets', () {
    testWidgets('the loaded brief is written with the check-in state', (
      tester,
    ) async {
      await pumpShell(tester);

      final snapshot = bridge.stored!;
      expect(snapshot['schema_version'], 1);
      final session = snapshot['session'] as Map<String, dynamic>;
      expect(session['name'], 'Push day');
      expect(session['state'], 'planned');
      expect(snapshot['check_in_done'], isTrue);
      expect(snapshot['lock'], isNull);
    });

    testWidgets('a Today without a publisher writes nothing', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: const Scaffold(body: TodayScreen(environment: _environment)),
        ),
      );
      await tester.pumpAndSettle();

      expect(bridge.calls, isEmpty);
    });

    testWidgets('leaving the app screens clears what the widgets read', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(bridge.stored, isNotNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(bridge.stored, isNull);
    });
  });

  group('A tapped widget opens a tab', () {
    testWidgets('Train opens while the app runs', (tester) async {
      await pumpShell(tester);
      expect(find.byKey(const ValueKey('tab_train')), findsNothing);

      bridge.tap(HomeWidgetTab.train);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tab_train')), findsOneWidget);
    });

    testWidgets('a tap that launched the app opens Train at the start', (
      tester,
    ) async {
      bridge.pending = HomeWidgetTab.train;

      await pumpShell(tester);

      expect(find.byKey(const ValueKey('tab_train')), findsOneWidget);
      expect(bridge.pending, isNull);
    });

    testWidgets('Today stays when that is what the widget asked for', (
      tester,
    ) async {
      bridge.pending = HomeWidgetTab.today;

      await pumpShell(tester);

      expect(find.byKey(const ValueKey('tab_train')), findsNothing);
    });

    testWidgets('the shell stops listening when it goes', (tester) async {
      await pumpShell(tester);
      expect(bridge.listening, isTrue);

      await tester.pumpWidget(const SizedBox());

      expect(bridge.listening, isFalse);
    });
  });

  group('Account › Widgets', () {
    Future<TodayWidgetPublisher> pumpAccount(WidgetTester tester) async {
      _phone(tester);
      final publisher = TodayWidgetPublisher(
        bridge: bridge,
        preferences: SharedPreferencesAsync(),
      );
      await tester.pumpWidget(
        TracendThemeScope(
          notifier: TracendThemeController(ThemeMode.dark),
          child: MaterialApp(
            theme: TracendTheme.dark,
            home: AccountScreen(
              environment: _environment,
              widgetPublisher: publisher,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return publisher;
    }

    testWidgets('Lock Screen numbers are off by default and say what shows', (
      tester,
    ) async {
      await pumpAccount(tester);
      await tester.scrollUntilVisible(
        find.text('Health numbers on the Lock Screen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Widgets'), findsOneWidget);
      expect(
        find.textContaining('Lock Screen widgets show Tracend and nothing'),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    });

    testWidgets('turning the switch on saves the choice for the widgets', (
      tester,
    ) async {
      final publisher = await pumpAccount(tester);
      await tester.scrollUntilVisible(
        find.text('Health numbers on the Lock Screen'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.ensureVisible(find.byType(Switch).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      expect(await publisher.lockScreenNumbers(), isTrue);
      expect(find.textContaining('show while the phone is locked'), findsOne);
    });

    testWidgets(
      'a removal that fails leaves the switch off and says what is happening',
      (tester) async {
        final publisher = await pumpAccount(tester);
        await publisher.publish(
          brief: DailyBrief(localDate: '2026-10-18'),
          targets: null,
          checkedIn: true,
        );
        await publisher.setLockScreenNumbers(true);
        await tester.scrollUntilVisible(
          find.text('Health numbers on the Lock Screen'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);

        bridge
          ..failWrites = true
          ..failClears = 2;
        await tester.ensureVisible(find.byType(Switch).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch).last);
        await tester.pumpAndSettle();

        expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
        expect(find.textContaining('Numbers are off'), findsOneWidget);
        expect(await publisher.lockScreenNumbers(), isFalse);
      },
    );

    testWidgets('without widgets there is no Widgets section', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        TracendThemeScope(
          notifier: TracendThemeController(ThemeMode.dark),
          child: MaterialApp(
            theme: TracendTheme.dark,
            home: const AccountScreen(environment: _environment),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Widgets'), findsNothing);
    });
  });
}
