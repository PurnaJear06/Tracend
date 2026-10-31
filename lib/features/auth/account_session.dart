import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';

/// Auth's codes for a session that can never be used again: its user was
/// deleted, it was revoked, or its refresh token is gone.
const _rejectedSessionCodes = {
  'bad_jwt',
  'refresh_token_already_used',
  'refresh_token_not_found',
  'session_expired',
  'session_not_found',
  'user_banned',
  'user_not_found',
};

/// Whether Auth refused this device's session for good. Lost connections,
/// server errors and rate limits are not refusals: the session is kept and
/// the athlete retries.
bool isRejectedSession(Object error) {
  if (error is AuthSessionMissingException) return true;
  if (error is! AuthApiException) return false;
  if (_rejectedSessionCodes.contains(error.code)) return true;
  return error.statusCode == '401' || error.statusCode == '403';
}

/// Whether Auth says the session's user no longer exists.
bool isDeletedUser(Object error) =>
    error is AuthApiException && error.code == 'user_not_found';

/// What this device keeps for one athlete: Apple Health sync state, the
/// month the usual months were sent, a check-in waiting to sync, the Lock
/// Screen widget choice (all kept per athlete), the Coach thread last open,
/// and the last loaded plan that opens the app with no connection.
///
/// A deleted account takes all of it. A refused session takes the Coach
/// thread, the saved plan and the Lock Screen choice, and signing out takes
/// the saved plan and the Lock Screen choice: the account may still exist
/// (signed out on another device, say), and its athlete gets their unsent
/// check-in and sync state back on signing in, but health numbers on the
/// Lock Screen are chosen again and the plan is loaded again. Nothing kept
/// is readable by another account.
class LocalAccountData {
  LocalAccountData({
    SharedPreferencesAsync? preferences,
    Future<SharedPreferences> Function()? legacyPreferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _legacyPreferences = legacyPreferences ?? SharedPreferences.getInstance;

  final SharedPreferencesAsync _preferences;
  final Future<SharedPreferences> Function() _legacyPreferences;

  /// Removes everything this device holds for a deleted account. Never
  /// throws: a store that cannot be read leaves its keys, and signing out
  /// still goes ahead.
  Future<void> clear(String? userId) async {
    try {
      final owned = _widgetChoiceKeys(userId);
      if (userId != null) {
        final healthPrefix = HealthPreferenceKeys.prefix(userId);
        final historyMonth = SupabaseHealthBaselineSource.historyMonthKey(
          userId,
        );
        owned.addAll(
          (await _preferences.getKeys()).where(
            (key) =>
                key.startsWith(healthPrefix) ||
                key == historyMonth ||
                WorkoutLocalKeys.owns(userId, key),
          ),
        );
      }
      await _preferences.clear(allowList: owned);
    } catch (e) {
      logNonCritical(e, 'athlete preferences not cleared');
    }
    await _removeLegacy({
      SharedPreferencesCoachThreadMemory.storageKey,
      // An older build's envelope belonged to the last athlete signed in.
      CheckInQueue.singleSlotKey,
      if (userId != null) ...{
        CheckInQueue.singleSlotKeyFor(userId),
        CheckInQueue.queueStorageKeyFor(userId),
        CheckInQueue.earlierKeyFor(userId),
        SafetyAcknowledgements.storageKeyFor(userId),
      },
    });
    if (userId != null) await _clearPainReports(userId);
  }

  /// Empties the pain reports kept for [userId], behind the same lock as every
  /// other change to them, so a send that is still waiting on the network
  /// cannot write them back.
  Future<void> _clearPainReports(String userId) async {
    try {
      await PainReportQueue.clearFor(await _legacyPreferences(), userId);
    } catch (e) {
      logNonCritical(e, 'pain reports not cleared');
    }
  }

  /// Forgets what belongs to the session rather than the athlete: the open
  /// Coach thread and the Lock Screen choice. Never throws.
  Future<void> forgetSession(String? userId) async {
    await forgetWidgetChoice(userId);
    await forgetSavedPlan(userId);
    await _removeLegacy({SharedPreferencesCoachThreadMemory.storageKey});
  }

  /// Forgets the plan this phone saved for [userId], so no one signed in
  /// afterwards can open it offline. Never throws.
  Future<void> forgetSavedPlan(String? userId) async {
    if (userId == null) return;
    await TrainingHubCache(_preferences).clear(userId);
  }

  /// Forgets [userId]'s choice to show health numbers on the Lock Screen,
  /// and the one choice an earlier build kept for the whole phone, so the
  /// next athlete on this phone starts with numbers off. Never throws.
  Future<void> forgetWidgetChoice(String? userId) async {
    try {
      await _preferences.clear(allowList: _widgetChoiceKeys(userId));
    } catch (e) {
      logNonCritical(e, 'widget setting not cleared');
    }
  }

  static Set<String> _widgetChoiceKeys(String? userId) => {
    TodayWidgetPublisher.lockScreenNumbersKey,
    TodayWidgetPublisher.lockScreenNumbersKeyFor(userId),
  };

  Future<void> _removeLegacy(Set<String> keys) async {
    try {
      final legacy = await _legacyPreferences();
      for (final key in keys) {
        await legacy.remove(key);
      }
    } catch (e) {
      logNonCritical(e, 'athlete preferences not cleared');
    }
  }
}

/// Ends a session Auth refused, on this device only, so the next launch
/// starts at sign-in. When Auth says the account no longer exists, its local
/// data goes too.
Future<void> endRejectedSession(
  SupabaseClient client,
  LocalAccountData localData,
  String? userId, {
  required bool accountDeleted,
}) async {
  if (accountDeleted) {
    await localData.clear(userId);
  } else {
    await localData.forgetSession(userId);
  }
  try {
    await client.auth.signOut(scope: SignOutScope.local);
  } catch (e) {
    // The stored session is removed before Auth is told; only that call
    // failed.
    logNonCritical(e);
  }
}

/// Signs the athlete out, the end of an account deletion included. The Lock
/// Screen choice and the saved plan are forgotten first, so the next athlete
/// on this phone never inherits either. When Auth cannot be reached, the session is removed from
/// this device alone.
Future<void> signOutAthlete(
  SupabaseClient client,
  LocalAccountData localData,
  String? userId,
) async {
  await localData.forgetWidgetChoice(userId);
  await localData.forgetSavedPlan(userId);
  try {
    await client.auth.signOut();
  } catch (e) {
    logNonCritical(e);
    await client.auth.signOut(scope: SignOutScope.local);
  }
}
