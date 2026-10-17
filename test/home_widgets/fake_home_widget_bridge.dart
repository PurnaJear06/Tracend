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

  HomeWidgetTab? pending;
  VoidCallback? _listener;

  int get writes => calls.where((call) => call != 'clear').length;

  @override
  Future<void> write(String snapshotJson) async {
    calls.add(snapshotJson);
    stored = jsonDecode(snapshotJson) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    stored = null;
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
