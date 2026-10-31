import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tracend/app/breadcrumbs.dart';
import 'package:tracend/shared/diagnostics.dart';

/// The native channel for the Home Screen and Lock Screen widgets
/// (`ios/Runner/Native/HomeWidgetBridge.swift`). The app calls `write`,
/// `clear` and `takePendingTab`; iOS calls `tabRequested` when a widget was
/// tapped.
const homeWidgetChannel = MethodChannel('tracend/home_widgets');

/// What a tap on a widget or on the workout's Live Activity asks the app to
/// open: a tab (`tracend://today`, `tracend://train`) or the workout in
/// progress (`tracend://workout`).
enum HomeWidgetTab {
  today('today'),
  train('train'),
  workout('workout');

  const HomeWidgetTab(this.key);

  /// The name the native side sends.
  final String key;

  static HomeWidgetTab? fromKey(Object? key) {
    for (final tab in values) {
      if (tab.key == key) return tab;
    }
    return null;
  }
}

/// The Today and Lock Screen widgets, which read a snapshot of Today from the
/// app group's shared storage and never call the network. The widgets are a
/// convenience: the app works without them, so failures are logged and never
/// thrown. `write` and `clear` answer whether the stored snapshot is now what
/// was asked for, because an opt-out or a sign-out must know when old data
/// could still be readable.
///
/// The snapshot is `TodayWidgetSnapshot`'s JSON (SECURITY_PRIVACY.md §10): no
/// free text, and no Lock Screen numbers unless the athlete chose them.
abstract interface class HomeWidgetBridge {
  /// Stores [snapshotJson] for the widgets and asks iOS to redraw them.
  /// False when it could not be stored: the snapshot before it is still
  /// there.
  Future<bool> write(String snapshotJson);

  /// Removes the stored snapshot and redraws the widgets (sign-out, account
  /// deletion, the app going away). False when old data may still be
  /// readable.
  Future<bool> clear();

  /// The tab a widget tap asked for, once: it is cleared as it is read. Null
  /// when nothing was asked or the request is older than a minute.
  Future<HomeWidgetTab?> takePendingTab();

  /// Calls [onRequested] whenever a widget tap arrived while the app runs,
  /// replacing any earlier listener. The tab itself comes from
  /// [takePendingTab].
  void listenForTab(VoidCallback onRequested);

  /// Stops calling [onRequested] (when it is still the listener).
  void stopListeningForTab(VoidCallback onRequested);
}

class MethodChannelHomeWidgetBridge implements HomeWidgetBridge {
  const MethodChannelHomeWidgetBridge();

  @override
  Future<bool> write(String snapshotJson) async =>
      await _invoke<bool>('write', {'snapshot': snapshotJson}) ?? false;

  @override
  Future<bool> clear() async => await _invoke<bool>('clear', null) ?? false;

  @override
  Future<HomeWidgetTab?> takePendingTab() async =>
      HomeWidgetTab.fromKey(await _invoke<String>('takePendingTab', null));

  static VoidCallback? _onRequested;

  @override
  void listenForTab(VoidCallback onRequested) {
    _onRequested = onRequested;
    homeWidgetChannel.setMethodCallHandler(_handle);
  }

  @override
  void stopListeningForTab(VoidCallback onRequested) {
    if (_onRequested != onRequested) return;
    _onRequested = null;
    homeWidgetChannel.setMethodCallHandler(null);
  }

  static Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'tabRequested') {
      throw MissingPluginException('No ${call.method} on home widgets');
    }
    _onRequested?.call();
    return null;
  }

  /// Calls the native side and leaves a breadcrumb with the method only,
  /// never the snapshot. A native error carries a fixed code only
  /// (`invalid_snapshot`, `no_app_group`, `write_failed`, `clear_failed`), and only the code is logged.
  Future<T?> _invoke<T>(String method, Map<String, Object>? arguments) async {
    T? result;
    try {
      result = await homeWidgetChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      logNonCritical(e, 'home widgets $method failed');
    } on MissingPluginException {
      debugPrint('Non-critical error: home widgets $method unavailable');
    }
    AppBreadcrumbs.homeWidgets('Home widgets $method');
    return result;
  }
}
