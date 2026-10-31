import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/train/offline_safety_notes.dart';
import 'package:tracend/shared/diagnostics.dart';

/// The last training hub that loaded for one athlete (`get_my_training_hub`
/// as the server sent it) and when this phone saved it.
class CachedTrainingHub {
  const CachedTrainingHub({required this.savedAt, required this.hub});

  final DateTime savedAt;
  final Map<String, dynamic> hub;
}

/// Keeps the athlete's last loaded plan on the phone so a cold start with no
/// connection can still show the approved plan and open the workout
/// (ARCHITECTURE §3.1, §10). One entry per athlete, tagged with the athlete's
/// id, so another account never reads it; signing out, a refused session and
/// account deletion remove it.
class TrainingHubCache {
  const TrainingHubCache(this._preferences);

  final SharedPreferencesAsync _preferences;

  /// Where [userId]'s copy lives.
  static String keyFor(String userId) => 'training_hub_cache_$userId';

  /// Where [userId]'s sore-area notes live; they go with the copy.
  static String safetyKeyFor(String userId) => 'training_safety_notes_$userId';

  /// The envelope's version; an entry of another version is not read.
  static const _version = 1;

  /// Replaces [userId]'s copy with [hub], saved at [now]. Never throws: a
  /// plan that cannot be kept only means no offline copy.
  Future<void> save(
    String userId,
    Map<String, dynamic> hub,
    DateTime now,
  ) async {
    try {
      await _preferences.setString(
        keyFor(userId),
        jsonEncode({
          'v': _version,
          'user_id': userId,
          'saved_at': now.toUtc().toIso8601String(),
          'hub': hub,
        }),
      );
    } catch (error) {
      logNonCritical(error, 'training hub not cached');
    }
  }

  /// [userId]'s copy, or null when there is none, it is unreadable, or it
  /// was saved for another athlete.
  Future<CachedTrainingHub?> load(String userId) async {
    try {
      final stored = await _preferences.getString(keyFor(userId));
      if (stored == null) return null;
      final decoded = jsonDecode(stored);
      if (decoded is! Map ||
          decoded['v'] != _version ||
          decoded['user_id'] != userId) {
        return null;
      }
      final savedAt = DateTime.tryParse('${decoded['saved_at']}');
      final hub = decoded['hub'];
      if (savedAt == null || hub is! Map) return null;
      return CachedTrainingHub(
        savedAt: savedAt.toLocal(),
        hub: Map<String, dynamic>.from(hub),
      );
    } catch (error) {
      logNonCritical(error, 'cached training hub not read');
      return null;
    }
  }

  /// Replaces [userId]'s sore-area notes. Never throws: notes that cannot be
  /// kept only mean Train says it cannot check them offline.
  Future<void> saveSafety(String userId, OfflineSafetyNotes notes) async {
    try {
      await _preferences.setString(
        safetyKeyFor(userId),
        jsonEncode({'v': _version, 'user_id': userId, 'notes': notes.toJson()}),
      );
    } catch (error) {
      logNonCritical(error, 'safety notes not cached');
    }
  }

  /// [userId]'s sore-area notes, or null when there are none, they are
  /// unreadable, or they were saved for another athlete.
  Future<OfflineSafetyNotes?> loadSafety(String userId) async {
    try {
      final stored = await _preferences.getString(safetyKeyFor(userId));
      if (stored == null) return null;
      final decoded = jsonDecode(stored);
      if (decoded is! Map ||
          decoded['v'] != _version ||
          decoded['user_id'] != userId) {
        return null;
      }
      return OfflineSafetyNotes.fromJson(decoded['notes']);
    } catch (error) {
      logNonCritical(error, 'cached safety notes not read');
      return null;
    }
  }

  /// Removes [userId]'s copy and sore-area notes. Never throws.
  Future<void> clear(String userId) async {
    try {
      await _preferences.clear(
        allowList: {keyFor(userId), safetyKeyFor(userId)},
      );
    } catch (error) {
      logNonCritical(error, 'cached training hub not removed');
    }
  }
}
