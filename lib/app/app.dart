import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/auth/phase_2_gate.dart';

class TracendApp extends StatefulWidget {
  const TracendApp({required this.environment, this.themeMode, super.key});
  final AppEnvironment environment;
  final ThemeMode? themeMode;
  @override
  State<TracendApp> createState() => _TracendAppState();
}

class _TracendAppState extends State<TracendApp> {
  late final TracendThemeController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TracendThemeController(widget.themeMode ?? ThemeMode.dark);
    if (widget.themeMode == null) unawaited(_restoreTheme());
  }

  Future<void> _restoreTheme() async {
    try {
      final stored = await SharedPreferencesAsync().getString(
        'tracend_theme_mode',
      );
      if (stored == null) return;
      await _controller.setMode(_modeFromName(stored), persist: false);
    } catch (e) {
      debugPrint('Non-critical error: $e');
      // Preferences are unavailable in some widget-test hosts.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TracendThemeScope(
    notifier: _controller,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => MaterialApp(
        title: 'Tracend',
        debugShowCheckedModeBanner: false,
        theme: TracendTheme.light,
        darkTheme: TracendTheme.dark,
        themeMode: _controller.mode,
        home: Phase2Gate(environment: widget.environment),
      ),
    ),
  );
}

ThemeMode _modeFromName(String value) => switch (value) {
  'light' => ThemeMode.light,
  'system' => ThemeMode.system,
  _ => ThemeMode.dark,
};

class TracendThemeController extends ChangeNotifier {
  TracendThemeController(this._mode);
  ThemeMode _mode;
  ThemeMode get mode => _mode;
  Future<void> setMode(ThemeMode value, {bool persist = true}) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    if (persist) {
      try {
        await SharedPreferencesAsync().setString(
          'tracend_theme_mode',
          value.name,
        );
      } catch (e) {
        debugPrint('Non-critical error: $e');
        // The selected mode still applies for the current process.
      }
    }
  }
}

class TracendThemeScope extends InheritedNotifier<TracendThemeController> {
  const TracendThemeScope({
    required super.notifier,
    required super.child,
    super.key,
  });
  static TracendThemeController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TracendThemeScope>()!
      .notifier!;
  static TracendThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TracendThemeScope>()?.notifier;
}
