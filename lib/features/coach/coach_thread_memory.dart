import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the Coach conversation the user last had open, so the next
/// launch reopens it instead of whichever thread changed most recently.
abstract interface class CoachThreadMemory {
  Future<String?> lastThreadId();
  Future<void> remember(String threadId);
}

class SharedPreferencesCoachThreadMemory implements CoachThreadMemory {
  const SharedPreferencesCoachThreadMemory();

  static const _key = 'tracend_coach_last_thread_id';

  /// Coach waits for this before it shows any conversation. A store that does
  /// not answer (as in hosts without the plugin) falls back to the newest one.
  static const _readTimeout = Duration(seconds: 1);

  @override
  Future<String?> lastThreadId() async {
    try {
      final preferences = await SharedPreferences.getInstance().timeout(
        _readTimeout,
      );
      return preferences.getString(_key);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      return null;
    }
  }

  @override
  Future<void> remember(String threadId) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, threadId);
    } catch (e) {
      debugPrint('Non-critical error: $e');
    }
  }
}
