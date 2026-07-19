import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPreferences {
  const NotificationPreferences({
    required this.authorizationStatus,
    required this.dailyCheckIn,
    required this.weeklyReview,
  });

  final String authorizationStatus;
  final bool dailyCheckIn;
  final bool weeklyReview;

  bool get isAuthorized => const {
    'authorized',
    'provisional',
    'ephemeral',
  }.contains(authorizationStatus);
}

abstract interface class NotificationRepository {
  Future<NotificationPreferences> load();
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
  });
}

class MethodChannelNotificationRepository implements NotificationRepository {
  const MethodChannelNotificationRepository();

  static const _channel = MethodChannel('com.tracend.app/notifications');

  @override
  Future<NotificationPreferences> load() async =>
      _decode(await _channel.invokeMapMethod<String, dynamic>('status'));

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
  }) async => _decode(
    await _channel.invokeMapMethod<String, dynamic>('configure', {
      'daily_check_in': dailyCheckIn,
      'weekly_review': weeklyReview,
    }),
  );

  NotificationPreferences _decode(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Missing notification state');
    }
    final status = value['authorization_status'];
    final daily = value['daily_check_in'];
    final weekly = value['weekly_review'];
    if (status is! String || daily is! bool || weekly is! bool) {
      throw const FormatException('Invalid notification state');
    }
    return NotificationPreferences(
      authorizationStatus: status,
      dailyCheckIn: daily,
      weeklyReview: weekly,
    );
  }
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(
    SupabaseClient client, {
    NotificationRepository device = const MethodChannelNotificationRepository(),
  }) : this._(SupabaseNotificationPreferenceStore(client), device);

  const SupabaseNotificationRepository.withStore({
    required NotificationPreferenceStore store,
    required NotificationRepository device,
  }) : this._(store, device);

  const SupabaseNotificationRepository._(this._store, this._device);

  final NotificationPreferenceStore _store;
  final NotificationRepository _device;

  @override
  Future<NotificationPreferences> load() async {
    final device = await _device.load();
    try {
      final saved = await _store.load();
      if (saved == null || !device.isAuthorized) return device;
      if (saved.dailyCheckIn == device.dailyCheckIn &&
          saved.weeklyReview == device.weeklyReview) {
        return device;
      }
      return _device.configure(
        dailyCheckIn: saved.dailyCheckIn,
        weeklyReview: saved.weeklyReview,
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      return device;
    }
  }

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
  }) async {
    final previous = await _device.load();
    final updated = await _device.configure(
      dailyCheckIn: dailyCheckIn,
      weeklyReview: weeklyReview,
    );
    try {
      await _store.save(updated);
      return updated;
    } catch (e) {
      debugPrint('Non-critical error: $e');
      await _device.configure(
        dailyCheckIn: previous.dailyCheckIn,
        weeklyReview: previous.weeklyReview,
      );
      rethrow;
    }
  }
}

abstract interface class NotificationPreferenceStore {
  Future<NotificationPreferences?> load();
  Future<void> save(NotificationPreferences preferences);
}

class SupabaseNotificationPreferenceStore
    implements NotificationPreferenceStore {
  const SupabaseNotificationPreferenceStore(this._client);

  final SupabaseClient _client;

  @override
  Future<NotificationPreferences?> load() async {
    final row = await _client
        .from('notification_preferences')
        .select('daily_check_in, weekly_review, authorization_status')
        .maybeSingle();
    if (row == null) return null;
    final status = row['authorization_status'];
    final daily = row['daily_check_in'];
    final weekly = row['weekly_review'];
    if (status is! String || daily is! bool || weekly is! bool) {
      throw const FormatException('Invalid saved notification preferences');
    }
    return NotificationPreferences(
      authorizationStatus: status,
      dailyCheckIn: daily,
      weeklyReview: weekly,
    );
  }

  @override
  Future<void> save(NotificationPreferences preferences) => _client.rpc(
    'save_my_notification_preferences',
    params: {
      'daily_check_in_enabled': preferences.dailyCheckIn,
      'weekly_review_enabled': preferences.weeklyReview,
      'ios_authorization_status': preferences.authorizationStatus,
    },
  );
}

class FixtureNotificationRepository implements NotificationRepository {
  const FixtureNotificationRepository();

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
  }) async => NotificationPreferences(
    authorizationStatus: 'authorized',
    dailyCheckIn: dailyCheckIn,
    weeklyReview: weeklyReview,
  );
}
