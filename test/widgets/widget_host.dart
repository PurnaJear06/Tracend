import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

/// A themed app around [child] for shared-widget tests.
Widget widgetHost(
  Widget child, {
  ThemeData? theme,
  TracendMotionLevel? motion,
}) {
  final app = MaterialApp(
    theme: theme ?? TracendTheme.dark,
    home: Scaffold(body: child),
  );
  return motion == null ? app : TracendMotionScope(level: motion, child: app);
}
