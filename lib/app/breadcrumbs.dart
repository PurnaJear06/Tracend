import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Breadcrumbs that give a crash report its recent steps. Only what happened
/// goes in (an action and plain facts such as `replayed`); never a health
/// value, an effort, a load, a duration, or an exercise name.
abstract final class AppBreadcrumbs {
  /// Where breadcrumbs go. Sentry drops them when it has no DSN.
  @visibleForTesting
  static void Function(Breadcrumb crumb) sink = _toSentry;

  static void _toSentry(Breadcrumb crumb) =>
      unawaited(Sentry.addBreadcrumb(crumb));

  static void workout(String message, {Map<String, Object> data = const {}}) =>
      sink(
        Breadcrumb(
          category: 'workout',
          message: message,
          level: SentryLevel.info,
          data: data.isEmpty ? null : Map<String, dynamic>.of(data),
        ),
      );
}
