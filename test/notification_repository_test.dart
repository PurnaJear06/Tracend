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
          restTimerAlertsEnabled: true,
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
      // The server keeps no rest alert choice; the device's stays.
      expect(device.lastRestTimerAlerts, isTrue);
      expect(restored.restTimerAlertsEnabled, isTrue);
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

  test('a failed server save restores all three device toggles', () async {
    final device = _DeviceRepository(
      const NotificationPreferences(
        authorizationStatus: 'authorized',
        dailyCheckIn: true,
        weeklyReview: false,
        restTimerAlertsEnabled: true,
      ),
    );
    final repository = SupabaseNotificationRepository.withStore(
      store: _PreferenceStore(null, failSave: true),
      device: device,
    );

    await expectLater(
      repository.configure(
        dailyCheckIn: false,
        weeklyReview: true,
        restTimerAlertsEnabled: false,
      ),
      throwsStateError,
    );

    expect(device.preferences.dailyCheckIn, isTrue);
    expect(device.preferences.weeklyReview, isFalse);
    expect(device.preferences.restTimerAlertsEnabled, isTrue);
  });
}

class _PreferenceStore implements NotificationPreferenceStore {
  _PreferenceStore(this.preferences, {this.failSave = false});

  final NotificationPreferences? preferences;
  final bool failSave;

  @override
  Future<NotificationPreferences?> load() async => preferences;

  @override
  Future<void> save(NotificationPreferences preferences) async {
    if (failSave) throw StateError('offline');
  }
}

class _DeviceRepository implements NotificationRepository {
  _DeviceRepository(this.preferences);

  NotificationPreferences preferences;
  int configureCalls = 0;
  bool? lastRestTimerAlerts;

  @override
  Future<NotificationPreferences> load() async => preferences;

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) async {
    configureCalls += 1;
    lastRestTimerAlerts = restTimerAlertsEnabled;
    preferences = NotificationPreferences(
      authorizationStatus: preferences.authorizationStatus,
      dailyCheckIn: dailyCheckIn,
      weeklyReview: weeklyReview,
      restTimerAlertsEnabled: restTimerAlertsEnabled,
    );
    return preferences;
  }
}
