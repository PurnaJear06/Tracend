import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/account/notification_repository.dart';

void main() {
  test(
    'restores durable preferences when iOS pending requests are empty',
    () async {
      final device = _DeviceRepository(
        const NotificationPreferences(
          authorizationStatus: 'authorized',
          dailyCheckIn: false,
          weeklyReview: false,
        ),
      );
      final repository = SupabaseNotificationRepository.withStore(
        store: _PreferenceStore(
          const NotificationPreferences(
            authorizationStatus: 'authorized',
            dailyCheckIn: true,
            weeklyReview: true,
          ),
        ),
        device: device,
      );

      final restored = await repository.load();

      expect(restored.dailyCheckIn, isTrue);
      expect(restored.weeklyReview, isTrue);
      expect(device.configureCalls, 1);
    },
  );

  test(
    'does not reschedule reminders after iOS permission is denied',
    () async {
      final device = _DeviceRepository(
        const NotificationPreferences(
          authorizationStatus: 'denied',
          dailyCheckIn: false,
          weeklyReview: false,
        ),
      );
      final repository = SupabaseNotificationRepository.withStore(
        store: _PreferenceStore(
          const NotificationPreferences(
            authorizationStatus: 'authorized',
            dailyCheckIn: true,
            weeklyReview: true,
          ),
        ),
        device: device,
      );

      final loaded = await repository.load();

      expect(loaded.authorizationStatus, 'denied');
      expect(device.configureCalls, 0);
    },
  );
}

class _PreferenceStore implements NotificationPreferenceStore {
  _PreferenceStore(this.preferences);

  final NotificationPreferences? preferences;

  @override
  Future<NotificationPreferences?> load() async => preferences;

  @override
  Future<void> save(NotificationPreferences preferences) async {}
}

class _DeviceRepository implements NotificationRepository {
  _DeviceRepository(this.preferences);

  NotificationPreferences preferences;
  int configureCalls = 0;

  @override
  Future<NotificationPreferences> load() async => preferences;

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
  }) async {
    configureCalls += 1;
    preferences = NotificationPreferences(
      authorizationStatus: preferences.authorizationStatus,
      dailyCheckIn: dailyCheckIn,
      weeklyReview: weeklyReview,
    );
    return preferences;
  }
}
