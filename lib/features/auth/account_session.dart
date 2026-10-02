import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/coach_thread_memory.dart';
import 'package:tracend/features/health/health_baseline.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/today/check_in_queue.dart';

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
/// month the usual months were sent, a check-in waiting to sync (all kept per
/// athlete), and the Coach thread last open.
///
/// A deleted account takes all of it. A refused session takes only the Coach
/// thread: the account may still exist (signed out on another device, say),
/// and its athlete gets their unsent check-in and sync state back on signing
/// in. Nothing kept is readable by another account.
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
      if (userId != null) {
        final healthPrefix = HealthPreferenceKeys.prefix(userId);
        final historyMonth = SupabaseHealthBaselineSource.historyMonthKey(
          userId,
        );
        final owned = (await _preferences.getKeys())
            .where((key) => key.startsWith(healthPrefix) || key == historyMonth)
            .toSet();
        if (owned.isNotEmpty) await _preferences.clear(allowList: owned);
      }
    } catch (e) {
      debugPrint('Non-critical error: athlete preferences not cleared: $e');
    }
    await _removeLegacy({
      SharedPreferencesCoachThreadMemory.storageKey,
      // An older build's envelope belonged to the last athlete signed in.
      CheckInQueue.legacyStorageKey,
      if (userId != null) CheckInQueue.storageKeyFor(userId),
    });
  }

  /// Forgets what belongs to the session rather than the athlete. Never
  /// throws.
  Future<void> forgetSession() =>
      _removeLegacy({SharedPreferencesCoachThreadMemory.storageKey});

  Future<void> _removeLegacy(Set<String> keys) async {
    try {
      final legacy = await _legacyPreferences();
      for (final key in keys) {
        await legacy.remove(key);
      }
    } catch (e) {
      debugPrint('Non-critical error: athlete preferences not cleared: $e');
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
    await localData.forgetSession();
  }
  try {
    await client.auth.signOut(scope: SignOutScope.local);
  } catch (e) {
    // The stored session is removed before Auth is told; only that call
    // failed.
    debugPrint('Non-critical error: $e');
  }
}
