import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/local_health_store.dart';

/// Remembers the Coach conversation the user last had open, so the next
/// launch reopens it instead of whichever thread changed most recently.
abstract interface class CoachThreadMemory {
  Future<String?> lastThreadId();
  Future<void> remember(String threadId);
}

/// Keeps the thread's id in the health store ([LocalHealthStore]), so it stays
/// out of backups with the rest of what the phone caches of a conversation.
class LocalCoachThreadMemory implements CoachThreadMemory {
  const LocalCoachThreadMemory([this._store = const LocalHealthStore()]);

  final LocalHealthStore _store;

  static const storageKey = 'tracend_coach_last_thread_id';

  /// Coach waits for this before it shows any conversation. A store that does
  /// not answer falls back to the newest conversation.
  static const _readTimeout = Duration(seconds: 1);

  @override
  Future<String?> lastThreadId() async {
    try {
      return await _store.getString(storageKey).timeout(_readTimeout);
    } catch (e) {
      logNonCritical(e);
      return null;
    }
  }

  @override
  Future<void> remember(String threadId) async {
    try {
      await _store.setString(storageKey, threadId);
    } catch (e) {
      logNonCritical(e);
    }
  }
}
