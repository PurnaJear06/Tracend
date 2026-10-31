import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';
import 'package:tracend/shared/home_widgets/home_widget_eraser.dart';
import 'package:tracend/shared/home_widgets/today_widget_snapshot.dart';
import 'package:tracend/shared/live_activity/workout_activity_bridge.dart';

/// Writes Today's snapshot for the Home Screen and Lock Screen widgets
/// whenever Today loads or changes, and owns the athlete's choice to show
/// health numbers on the Lock Screen.
///
/// The choice is kept on this device for the signed-in athlete only and
/// starts off: the Lock Screen shows a placeholder until the athlete turns
/// numbers on in Account (SECURITY_PRIVACY.md §10). Another athlete signing
/// in on the same phone starts off again, and sign-out forgets the choice
/// (`LocalAccountData.forgetWidgetChoice`). Turning it off removes the
/// numbers from the shared snapshot at once, and the kg and reps from the
/// workout's Live Activity if it is showing them. The widgets are a
/// convenience, so nothing here throws.
class TodayWidgetPublisher {
  TodayWidgetPublisher({
    required HomeWidgetBridge bridge,
    String? userId,
    SharedPreferencesAsync? preferences,
    HomeWidgetEraser? eraser,
    DateTime Function() clock = DateTime.now,
    WorkoutActivityBridge activity = const MethodChannelWorkoutActivityBridge(),
  }) : _bridge = bridge,
       _activity = activity,
       _key = lockScreenNumbersKeyFor(userId),
       _eraser = eraser ?? HomeWidgetEraser(bridge, preferences: preferences),
       _preferences = preferences,
       _clock = clock {
    _eraser.addListener(_republish);
  }

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
  final WorkoutActivityBridge _activity;
  final String _key;
  final HomeWidgetEraser _eraser;
  final SharedPreferencesAsync? _preferences;
  final DateTime Function() _clock;

  ({
    DailyBrief brief,
    NutritionTargets? targets,
    bool checkedIn,
    DateTime loadedAt,
  })?
  _latest;
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
      logNonCritical(e, 'widget setting not read');
    }
    return _lockScreenNumbers ??= stored;
  }

  /// Saves the choice and redraws the widgets with it. The choice is saved
  /// first, so no snapshot written later has numbers the athlete turned off.
  /// Turning numbers off never leaves the old ones readable: without a loaded
  /// Today to rebuild from, or when the rewrite fails, the stored snapshot is
  /// removed instead. False when even that failed: the old numbers may still
  /// be readable, and the removal is retried on every launch and resume
  /// (`HomeWidgetEraser`).
  Future<bool> setLockScreenNumbers(bool shown) async {
    _lockScreenNumbers = shown;
    try {
      await (_preferences ?? SharedPreferencesAsync()).setBool(_key, shown);
    } catch (e) {
      logNonCritical(e, 'widget setting not saved');
    }
    if (!shown) unawaited(_activity.hideNumbers());
    final latest = _latest;
    final written = latest != null && await _write(latest, force: true);
    if (shown || written) return true;
    _writtenKey = null;
    _writtenAt = null;
    return _eraser.erase();
  }

  /// Writes the snapshot of the Today that just loaded. [loadedAt] is when
  /// [brief] arrived (now when null); the snapshot is stamped with it, also
  /// when it is written again later, so its 12-hour and midnight expiry count
  /// from the load and not from the rewrite.
  Future<void> publish({
    required DailyBrief brief,
    required NutritionTargets? targets,
    required bool checkedIn,
    DateTime? loadedAt,
  }) {
    final latest = (
      brief: brief,
      targets: targets,
      checkedIn: checkedIn,
      loadedAt: loadedAt ?? _clock(),
    );
    _latest = latest;
    return _write(latest);
  }

  /// Whether the stored snapshot now matches [latest] and the choice.
  Future<bool> _write(
    ({
      DailyBrief brief,
      NutritionTargets? targets,
      bool checkedIn,
      DateTime loadedAt,
    })
    latest, {
    bool force = false,
  }) async {
    final shown = await lockScreenNumbers();
    // The rest runs without waiting until the snapshot is sent, so a
    // dispose that came while the choice was read is seen here.
    if (_disposed) return true;
    final now = _clock();
    final snapshot = TodayWidgetSnapshot.build(
      brief: latest.brief,
      targets: latest.targets,
      checkedIn: latest.checkedIn,
      lockScreenNumbers: shown,
      now: latest.loadedAt,
    );
    final writtenAt = _writtenAt;
    if (!force &&
        snapshot.contentKey == _writtenKey &&
        writtenAt != null &&
        now.difference(writtenAt) < refreshAfter) {
      return true;
    }
    _writtenKey = snapshot.contentKey;
    _writtenAt = now;
    final erasesAtWrite = _eraser.erases;
    final stored = await _bridge.write(jsonEncode(snapshot.toJson()));
    if (!stored) {
      // Whatever is stored is not this snapshot, so the next load writes.
      _writtenKey = null;
      _writtenAt = null;
    } else if (!_disposed) {
      // The new file replaced whatever an earlier clear could not remove.
      await _eraser.settle(erasesAtWrite);
    }
    return stored;
  }

  /// A clear that failed earlier worked on a retry and took the snapshot
  /// with it: write the last one again.
  void _republish() {
    final latest = _latest;
    if (_disposed || latest == null) return;
    unawaited(_write(latest, force: true));
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
    _eraser.removeListener(_republish);
    _forget();
    await _eraser.erase();
  }
}
