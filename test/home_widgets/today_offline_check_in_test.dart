import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/today/check_in_gate.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/features/today/today_screen.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';

import 'fake_home_widget_bridge.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

/// The first load answers a day with no check-in; every load after it fails,
/// as it does in the outage that keeps a check-in queued.
class _BriefsThenOutage implements DailyBriefRepository {
  int loads = 0;

  @override
  Future<DailyBrief> load(DateTime date) async {
    loads++;
    if (loads > 1) throw Exception('offline');
    return const DailyBrief(
      localDate: '2026-10-18',
      workout: {'name': 'Push day'},
      nutrition: {'calories': 1000, 'protein_g': 40},
    );
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'a check-in queued offline marks the widgets done without a new brief',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bridge = FakeHomeWidgetBridge();
      final briefs = _BriefsThenOutage();
      final gate = CheckInGate();
      addTearDown(gate.dispose);
      final now = DateTime(2026, 10, 18, 7, 30);
      await tester.pumpWidget(
        MaterialApp(
          theme: TracendTheme.dark,
          home: Scaffold(
            body: TodayScreen(
              environment: _environment,
              brief: briefs,
              clock: () => now,
              checkInGate: gate,
              // Not delivered: the check-in stays queued on the phone.
              checkInSender: (localDate, timezone, key, payload) async => false,
              widgetPublisher: TodayWidgetPublisher(
                bridge: bridge,
                preferences: SharedPreferencesAsync(),
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(bridge.stored!['check_in_done'], isFalse);
      expect(gate.required, isTrue);

      gate.checkIn();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Check-in saved on this device. It will sync when you are online.',
        ),
        findsOneWidget,
      );
      expect(briefs.loads, 2);
      expect(bridge.stored!['check_in_done'], isTrue);
      expect(gate.required, isFalse);
    },
  );
}
