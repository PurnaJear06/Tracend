import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';

/// Empties the widgets' snapshot and does not forget a failure.
///
/// A clear is tried twice. When both fail, old data may still be readable,
/// so a flag is kept on the phone (for the phone, not for an athlete: a
/// signed-out athlete's snapshot is the next person's problem too) and the
/// clear is tried again on every launch and resume until it works. A retry
/// that works tells its listeners (the publisher, which writes its last
/// snapshot again), and a snapshot written over the old file settles the
/// flag too ([settle]).
class HomeWidgetEraser extends ChangeNotifier {
  HomeWidgetEraser(this._bridge, {SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  /// The preference that says a clear failed and has not succeeded since.
  static const pendingKey = 'home_widgets_clear_pending';

  final HomeWidgetBridge _bridge;
  final SharedPreferencesAsync? _preferences;
  bool _disposed = false;

  /// How many clears have started. A snapshot written before the latest one
  /// started did not replace what that clear is removing ([settle]).
  int _erases = 0;
  int get erases => _erases;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  SharedPreferencesAsync get _store => _preferences ?? SharedPreferencesAsync();

  /// Whether the last clear failed for good and is still to be done.
  Future<bool> isPending() async {
    try {
      return await _store.getBool(pendingKey) ?? false;
    } catch (e) {
      debugPrint('Non-critical error: widget clear flag not read: $e');
      return false;
    }
  }

  /// Clears the snapshot, once more if the first try fails, and records a
  /// failure that survives both. True when no old data is left readable.
  Future<bool> erase() async {
    _erases++;
    final cleared = await _bridge.clear() || await _bridge.clear();
    try {
      if (cleared) {
        await _store.remove(pendingKey);
      } else {
        await _store.setBool(pendingKey, true);
      }
    } catch (e) {
      debugPrint('Non-critical error: widget clear flag not saved: $e');
    }
    return cleared;
  }

  /// Tries a clear that failed earlier; does nothing when none is pending.
  /// Listeners hear when it worked, so the widgets get a snapshot again.
  Future<void> retryPending() async {
    if (!await isPending()) return;
    if (await erase() && !_disposed) notifyListeners();
  }

  /// A snapshot was written over the old file, so nothing old is left to
  /// clear. [erasesAtWrite] is [erases] when the write began: if a clear
  /// started since, its outcome stands.
  Future<void> settle(int erasesAtWrite) async {
    if (erasesAtWrite != _erases || !await isPending()) return;
    if (erasesAtWrite != _erases) return;
    try {
      await _store.remove(pendingKey);
    } catch (e) {
      debugPrint('Non-critical error: widget clear flag not saved: $e');
    }
  }
}
