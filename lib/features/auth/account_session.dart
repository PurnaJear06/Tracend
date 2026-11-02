import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/safety_acknowledgements.dart';
import 'package:tracend/features/today/check_in_marks.dart';
import 'package:tracend/features/today/check_in_queue.dart';
import 'package:tracend/features/train/training_hub_cache.dart';
import 'package:tracend/features/train/workout_repository.dart';
import 'package:tracend/features/workout_hr/set_heart_rate_recorder.dart';
import 'package:tracend/features/workout_hr/sleeping_heart_rate_recorder.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/home_widgets/today_widget_publisher.dart';
import 'package:tracend/shared/local_health_store.dart';

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
/// the day marks that say the athlete checked in or chose "Not today", the
/// workouts waiting for their heart rate to be read, and the last loaded plan
/// that opens the app with no connection.
///
/// What is health data (the check-in queue, pain reports, workout drafts,
/// the saved plan, referrals read, the Coach thread) lives in the health store
/// ([LocalHealthStore]); the rest is in preferences.
///
/// A deleted account takes all of it. A refused session takes the Coach
/// thread, the saved plan, the day marks, the heart rate jobs and the Lock
/// Screen choice, and signing out takes the saved plan, the day marks, the
/// heart rate jobs and the Lock Screen choice: the account may still exist
/// (signed out on another device, say), and its athlete gets their unsent
/// check-in and sync state back on signing in, but health numbers on the Lock
/// Screen are chosen again and the plan is loaded again. Nothing kept is
/// readable by another account.
class LocalAccountData {
  LocalAccountData({
    SharedPreferencesAsync? preferences,
    Future<SharedPreferences> Function()? legacyPreferences,
    LocalHealthStore? store,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _legacyPreferences = legacyPreferences ?? SharedPreferences.getInstance,
       _store = store ?? const LocalHealthStore();

  final SharedPreferencesAsync _preferences;
  final Future<SharedPreferences> Function() _legacyPreferences;
  final LocalHealthStore _store;

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
            (key) => key.startsWith(healthPrefix) || key == historyMonth,
          ),
        );
        owned.add(SleepingHeartRateRecorder.finalKeyFor(userId));
      }
      owned.add(SetHeartRateRecorder.pendingKey);
      await _preferences.clear(allowList: owned);
    } catch (e) {
      logNonCritical(e, 'athlete preferences not cleared');
    }
    await forgetCheckInMarks(userId);
    try {
      await _store.removeAll({
        LocalCoachThreadMemory.storageKey,
        // An older build's envelope belonged to the last athlete signed in.
        CheckInQueue.singleSlotKey,
        if (userId != null) ...{
          CheckInQueue.singleSlotKeyFor(userId),
          CheckInQueue.queueStorageKeyFor(userId),
          CheckInQueue.earlierKeyFor(userId),
          SafetyAcknowledgements.storageKeyFor(userId),
          ...(await _store.getKeys()).where(
            (key) => WorkoutLocalKeys.owns(userId, key),
          ),
        },
      });
    } catch (e) {
      logNonCritical(e, 'athlete health cache not cleared');
    }
    if (userId != null) await _clearPainReports(userId);
  }

  /// Empties the pain reports kept for [userId], behind the same lock as every
  /// other change to them, so a send that is still waiting on the network
  /// cannot write them back.
  Future<void> _clearPainReports(String userId) async {
    try {
      await PainReportQueue.clearFor(_store, userId);
    } catch (e) {
      logNonCritical(e, 'pain reports not cleared');
    }
  }

  /// Forgets what belongs to the session rather than the athlete: the open
  /// Coach thread, the day marks and the Lock Screen choice. Never throws.
  Future<void> forgetSession(String? userId) async {
    await forgetWidgetChoice(userId);
    await forgetSavedPlan(userId);
    await forgetCheckInMarks(userId);
    await forgetHeartRateJobs();
    try {
      await _store.remove(LocalCoachThreadMemory.storageKey);
    } catch (e) {
      logNonCritical(e, 'coach thread not cleared');
    }
  }

  /// Forgets the plan this phone saved for [userId], so no one signed in
  /// afterwards can open it offline. Never throws.
  Future<void> forgetSavedPlan(String? userId) async {
    if (userId == null) return;
    await TrainingHubCache(_store).clear(userId);
  }

  /// Forgets that [userId] checked in today or chose "Not today", and the
  /// marks an earlier build kept for the whole phone, so the next athlete on
  /// this phone is asked for the morning check-in. Never throws.
  Future<void> forgetCheckInMarks(String? userId) async {
    try {
      final legacy = await _legacyPreferences();
      for (final key in {
        CheckInMarks.savedOnKey,
        CheckInMarks.skippedOnKey,
        CheckInMarks.savedOnKeyFor(userId),
        CheckInMarks.skippedOnKeyFor(userId),
      }) {
        await legacy.remove(key);
      }
    } catch (e) {
      logNonCritical(e, 'check-in marks not cleared');
    }
  }

  /// Forgets the workouts waiting for their heart rate to be read. The list is
  /// kept for the whole phone, and the next athlete's account does not own
  /// those workouts. Never throws.
  Future<void> forgetHeartRateJobs() async {
    try {
      await _preferences.remove(SetHeartRateRecorder.pendingKey);
    } catch (e) {
      logNonCritical(e, 'heart rate jobs not cleared');
    }
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
/// Screen choice, the saved plan and the day marks are forgotten first, so the
/// next athlete on this phone never inherits any of them. When Auth cannot be
/// reached, the session is removed from this device alone.
Future<void> signOutAthlete(
  SupabaseClient client,
  LocalAccountData localData,
  String? userId,
) async {
  await localData.forgetWidgetChoice(userId);
  await localData.forgetSavedPlan(userId);
  await localData.forgetCheckInMarks(userId);
  await localData.forgetHeartRateJobs();
  try {
    await client.auth.signOut();
  } catch (e) {
    logNonCritical(e);
    await client.auth.signOut(scope: SignOutScope.local);
  }
}
