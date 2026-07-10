import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/account/account_screen.dart';
import 'package:tracend/features/account/notification_repository.dart';

void main() {
  testWidgets('notification controls disclose private lock-screen copy', (
    tester,
  ) async {
    final repository = _NotificationRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: AccountScreen(
          environment: const AppEnvironment(
            name: 'test',
            supabaseUrl: '',
            supabasePublishableKey: '',
          ),
          notifications: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Lock-screen text stays generic'),
      findsOneWidget,
    );

    await tester.tap(find.text('Daily check-in reminder'));
    await tester.tap(find.text('Weekly review reminder'));
    await tester.tap(find.text('Save reminders'));
    await tester.pumpAndSettle();

    expect(repository.dailyCheckIn, isTrue);
    expect(repository.weeklyReview, isTrue);
    expect(find.text('2 reminder types enabled'), findsOneWidget);
  });
}

class _NotificationRepository implements NotificationRepository {
  bool dailyCheckIn = false;
  bool weeklyReview = false;

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
  }) async {
    this.dailyCheckIn = dailyCheckIn;
    this.weeklyReview = weeklyReview;
    return NotificationPreferences(
      authorizationStatus: 'authorized',
      dailyCheckIn: dailyCheckIn,
      weeklyReview: weeklyReview,
    );
  }
}
