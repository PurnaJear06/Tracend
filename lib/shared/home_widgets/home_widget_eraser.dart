import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';

/// Empties the widgets' snapshot and does not forget a failure.
///
/// A clear is tried twice. When both fail, old data may still be readable,
/// so a flag is kept on the phone (for the phone, not for an athlete: a
/// signed-out athlete's snapshot is the next person's problem too) and the
/// clear is tried again on every launch and resume until it works. While the
/// flag is set nothing new is published (`TodayWidgetPublisher`).
class HomeWidgetEraser {
  HomeWidgetEraser(this._bridge, {SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  /// The preference that says a clear failed and has not succeeded since.
  static const pendingKey = 'home_widgets_clear_pending';

  final HomeWidgetBridge _bridge;
  final SharedPreferencesAsync? _preferences;

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
  Future<void> retryPending() async {
    if (await isPending()) await erase();
  }
}
