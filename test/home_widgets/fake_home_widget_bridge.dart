import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tracend/shared/home_widgets/home_widget_bridge.dart';

/// Plays the native side of the widgets: it keeps the one snapshot the app
/// group would hold, and the tab a widget tap asked for.
class FakeHomeWidgetBridge implements HomeWidgetBridge {
  /// Every `write` and `clear`, in order ('clear' for a clear).
  final calls = <String>[];

  /// The snapshot the widgets would read, or null.
  Map<String, dynamic>? stored;

  /// When set, every `write` fails and leaves the stored snapshot as it was.
  bool failWrites = false;

  /// How many of the next `clear` calls fail and leave the snapshot.
  int failClears = 0;

  HomeWidgetTab? pending;
  VoidCallback? _listener;

  int get writes => calls.where((call) => call != 'clear').length;

  @override
  Future<bool> write(String snapshotJson) async {
    calls.add(snapshotJson);
    if (failWrites) return false;
    stored = jsonDecode(snapshotJson) as Map<String, dynamic>;
    return true;
  }

  @override
  Future<bool> clear() async {
    calls.add('clear');
    if (failClears > 0) {
      failClears--;
      return false;
    }
    stored = null;
    return true;
  }

  @override
  Future<HomeWidgetTab?> takePendingTab() async {
    final tab = pending;
    pending = null;
    return tab;
  }

  @override
  void listenForTab(VoidCallback onRequested) => _listener = onRequested;

  @override
  void stopListeningForTab(VoidCallback onRequested) {
    if (_listener == onRequested) _listener = null;
  }

  bool get listening => _listener != null;

  /// A tap on a widget while the app runs.
  void tap(HomeWidgetTab tab) {
    pending = tab;
    _listener?.call();
  }
}
