import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/app/breadcrumbs.dart';

class NotificationPreferences {
  const NotificationPreferences({
    required this.authorizationStatus,
    required this.dailyCheckIn,
    required this.weeklyReview,
    this.restTimerAlertsEnabled = false,
  });

  final String authorizationStatus;
  final bool dailyCheckIn;
  final bool weeklyReview;

  /// A lock-screen alert when a workout rest timer ends. Kept on this device
  /// only: the server stores the two reminder choices, not this one.
  final bool restTimerAlertsEnabled;

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
    required bool restTimerAlertsEnabled,
  });
}

/// The native channel for local notifications (`ios/Runner/SceneDelegate.swift`).
const notificationChannel = MethodChannel('com.tracend.app/notifications');

class MethodChannelNotificationRepository implements NotificationRepository {
  const MethodChannelNotificationRepository();

  @override
  Future<NotificationPreferences> load() async => _decode(
    await notificationChannel.invokeMapMethod<String, dynamic>('status'),
  );

  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) async {
    final preferences = _decode(
      await notificationChannel.invokeMapMethod<String, dynamic>('configure', {
        'daily_check_in': dailyCheckIn,
        'weekly_review': weeklyReview,
        'rest_timer_alerts': restTimerAlertsEnabled,
      }),
    );
    if (!preferences.restTimerAlertsEnabled) {
      await const MethodChannelRestAlertScheduler().cancelRestAlert();
    }
    return preferences;
  }

  NotificationPreferences _decode(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Missing notification state');
    }
    final status = value['authorization_status'];
    final daily = value['daily_check_in'];
    final weekly = value['weekly_review'];
    final rest = value['rest_timer_alerts'];
    if (status is! String ||
        daily is! bool ||
        weekly is! bool ||
        rest is! bool) {
      throw const FormatException('Invalid notification state');
    }
    return NotificationPreferences(
      authorizationStatus: status,
      dailyCheckIn: daily,
      weeklyReview: weekly,
      restTimerAlertsEnabled: rest,
    );
  }
}

/// The lock-screen alert at the end of a workout rest, identifier
/// `tracend.rest-timer`, text "Rest timer finished". It is a convenience: the
/// in-app timer works without it, so failures are logged and never thrown.
abstract interface class RestAlertScheduler {
  /// Schedules the alert [seconds] from now, replacing an earlier one.
  /// Returns whether an alert is pending: false when rest alerts are off,
  /// iOS does not allow alerts, or the platform failed.
  Future<bool> scheduleRestAlert(int seconds);

  /// Removes the alert, pending or shown. Safe to call when there is none.
  Future<void> cancelRestAlert();
}

class MethodChannelRestAlertScheduler implements RestAlertScheduler {
  const MethodChannelRestAlertScheduler();

  /// The longest rest the native side accepts, in seconds.
  static const maxSeconds = 3600;

  @override
  Future<bool> scheduleRestAlert(int seconds) async {
    if (seconds < 1) {
      await cancelRestAlert();
      return false;
    }
    var scheduled = false;
    try {
      scheduled =
          await notificationChannel.invokeMethod<bool>('scheduleRestAlert', {
            'seconds': seconds > maxSeconds ? maxSeconds : seconds,
          }) ==
          true;
    } on PlatformException catch (e) {
      debugPrint('Non-critical error: rest alert not scheduled: ${e.code}');
    } on MissingPluginException catch (e) {
      debugPrint('Non-critical error: rest alert not scheduled: $e');
    }
    AppBreadcrumbs.workout(
      'Rest alert scheduled',
      data: {'scheduled': scheduled},
    );
    return scheduled;
  }

  @override
  Future<void> cancelRestAlert() async {
    try {
      await notificationChannel.invokeMethod<void>('cancelRestAlert');
    } on PlatformException catch (e) {
      debugPrint('Non-critical error: rest alert not cancelled: ${e.code}');
    } on MissingPluginException catch (e) {
      debugPrint('Non-critical error: rest alert not cancelled: $e');
    }
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
        restTimerAlertsEnabled: device.restTimerAlertsEnabled,
      );
    } catch (e) {
      debugPrint('Non-critical error: $e');
      return device;
    }
  }

  /// Applies the choices on the device, then saves the two reminder choices
  /// on the server when one of them changed. The rest alert is device-only,
  /// so a rest-only change never waits for the server, and a failed server
  /// save rolls back the reminders but keeps the rest choice as applied.
  @override
  Future<NotificationPreferences> configure({
    required bool dailyCheckIn,
    required bool weeklyReview,
    required bool restTimerAlertsEnabled,
  }) async {
    final previous = await _device.load();
    final updated = await _device.configure(
      dailyCheckIn: dailyCheckIn,
      weeklyReview: weeklyReview,
      restTimerAlertsEnabled: restTimerAlertsEnabled,
    );
    if (dailyCheckIn == previous.dailyCheckIn &&
        weeklyReview == previous.weeklyReview) {
      if (updated.authorizationStatus != previous.authorizationStatus) {
        unawaited(_syncPermission(updated));
      }
      return updated;
    }
    try {
      await _store.save(updated);
      return updated;
    } catch (e) {
      debugPrint('Non-critical error: $e');
      await _device.configure(
        dailyCheckIn: previous.dailyCheckIn,
        weeklyReview: previous.weeklyReview,
        restTimerAlertsEnabled: updated.restTimerAlertsEnabled,
      );
      rethrow;
    }
  }

  /// Records a permission change made by the rest toggle (iOS asked for the
  /// first time). Best effort: the next reminder save sends it again.
  Future<void> _syncPermission(NotificationPreferences preferences) async {
    try {
      await _store.save(preferences);
    } catch (e) {
      debugPrint('Non-critical error: notification permission not synced: $e');
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
    required bool restTimerAlertsEnabled,
  }) async => NotificationPreferences(
    authorizationStatus: 'authorized',
    dailyCheckIn: dailyCheckIn,
    weeklyReview: weeklyReview,
    restTimerAlertsEnabled: restTimerAlertsEnabled,
  );
}
