import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';
import 'package:tracend/shared/home_widgets/today_widget_snapshot.dart';

/// Writes Today's snapshot for the Home Screen and Lock Screen widgets
/// whenever Today loads or changes, and owns the athlete's choice to show
/// health numbers on the Lock Screen.
///
/// The choice is kept on this device for the signed-in athlete only and
/// starts off: the Lock Screen shows a placeholder until the athlete turns
/// numbers on in Account (SECURITY_PRIVACY.md §10). Another athlete signing
/// in on the same phone starts off again, and sign-out forgets the choice
/// (`LocalAccountData.forgetWidgetChoice`). Turning it off removes the
/// numbers from the shared snapshot at once. The widgets are a convenience,
/// so nothing here throws.
class TodayWidgetPublisher {
  TodayWidgetPublisher({
    required HomeWidgetBridge bridge,
    String? userId,
    SharedPreferencesAsync? preferences,
    DateTime Function() clock = DateTime.now,
  }) : _bridge = bridge,
       _key = lockScreenNumbersKeyFor(userId),
       _preferences = preferences,
       _clock = clock;

  /// The key an earlier build kept one choice under for the whole phone. It
  /// is never read for a signed-in athlete; sign-out removes it.
  static const lockScreenNumbersKey = 'home_widgets_lock_screen_numbers';

  /// The preference key for [userId]'s Lock Screen choice. Without a
  /// backend there is no athlete, and the build's one choice is kept.
  static String lockScreenNumbersKeyFor(String? userId) =>
      userId == null ? lockScreenNumbersKey : '$lockScreenNumbersKey.$userId';

  /// A snapshot whose content did not change is written again only after
  /// this long, so its time stamp stays fresh without a write per load.
  static const refreshAfter = Duration(minutes: 5);

  final HomeWidgetBridge _bridge;
  final String _key;
  final SharedPreferencesAsync? _preferences;
  final DateTime Function() _clock;

  ({DailyBrief brief, NutritionTargets? targets, bool checkedIn})? _latest;
  String? _writtenKey;
  DateTime? _writtenAt;
  bool? _lockScreenNumbers;
  bool _disposed = false;

  /// Whether Lock Screen widgets show health numbers. Off until chosen.
  Future<bool> lockScreenNumbers() async {
    final known = _lockScreenNumbers;
    if (known != null) return known;
    var stored = false;
    try {
      stored =
          await (_preferences ?? SharedPreferencesAsync()).getBool(_key) ??
          false;
    } catch (e) {
      debugPrint('Non-critical error: widget setting not read: $e');
    }
    return _lockScreenNumbers ??= stored;
  }

  /// Saves the choice and redraws the widgets with it. Without a loaded
  /// Today to rebuild from, turning numbers off removes the stored snapshot,
  /// so none stays readable.
  Future<void> setLockScreenNumbers(bool shown) async {
    _lockScreenNumbers = shown;
    try {
      await (_preferences ?? SharedPreferencesAsync()).setBool(_key, shown);
    } catch (e) {
      debugPrint('Non-critical error: widget setting not saved: $e');
    }
    final latest = _latest;
    if (latest != null) {
      await _write(latest, force: true);
    } else if (!shown) {
      _forget();
      await _bridge.clear();
    }
  }

  /// Writes the snapshot of the Today that just loaded.
  Future<void> publish({
    required DailyBrief brief,
    required NutritionTargets? targets,
    required bool checkedIn,
  }) {
    final latest = (brief: brief, targets: targets, checkedIn: checkedIn);
    _latest = latest;
    return _write(latest);
  }

  Future<void> _write(
    ({DailyBrief brief, NutritionTargets? targets, bool checkedIn}) latest, {
    bool force = false,
  }) async {
    final shown = await lockScreenNumbers();
    if (_disposed) return;
    final now = _clock();
    final snapshot = TodayWidgetSnapshot.build(
      brief: latest.brief,
      targets: latest.targets,
      checkedIn: latest.checkedIn,
      lockScreenNumbers: shown,
      now: now,
    );
    final writtenAt = _writtenAt;
    if (!force &&
        snapshot.contentKey == _writtenKey &&
        writtenAt != null &&
        now.difference(writtenAt) < refreshAfter) {
      return;
    }
    _writtenKey = snapshot.contentKey;
    _writtenAt = now;
    await _bridge.write(jsonEncode(snapshot.toJson()));
  }

  void _forget() {
    _latest = null;
    _writtenKey = null;
    _writtenAt = null;
  }

  /// Stops publishing and removes the snapshot: the athlete left the app's
  /// screens (sign-out, account deletion), so no widget keeps their day.
  Future<void> dispose() async {
    _disposed = true;
    _forget();
    await _bridge.clear();
  }
}
