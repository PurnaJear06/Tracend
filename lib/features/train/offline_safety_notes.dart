import 'package:flutter/foundation.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/safety_copy.dart';

/// What Tracend last said about sore areas for one athlete: the safety route
/// and the lines about areas on hold or eased, as the day card put them. It is
/// kept beside the saved plan so Train can still show them with no
/// connection. It is fixed wording from the rules, never a diagnosis, and it
/// is only what was known on [localDate]: it cannot know about a report made
/// since.
@immutable
class OfflineSafetyNotes {
  const OfflineSafetyNotes({
    required this.localDate,
    required this.safetyRoute,
    required this.lines,
  });

  /// The notes of [adjustment], the server's answer for one day.
  factory OfflineSafetyNotes.from(DayAdjustment adjustment) {
    final lines = <String>[];
    for (final state in adjustment.jointStates) {
      final line = switch (state.state) {
        JointStateKind.held when state.isReminderHold => holdReminderLine(
          state,
        ),
        JointStateKind.held || JointStateKind.limited => jointStateLine(state),
        JointStateKind.watch => null,
      };
      if (line != null && !lines.contains(line)) lines.add(line);
    }
    return OfflineSafetyNotes(
      localDate: adjustment.localDate,
      safetyRoute: adjustment.safetyRoute,
      lines: List.unmodifiable(lines),
    );
  }

  /// "2026-10-24": the day the server answered for.
  final String localDate;

  /// The route the day sent the athlete to a professional by, when it did.
  final String? safetyRoute;

  /// One sentence per area on hold or eased.
  final List<String> lines;

  /// Nothing to show: no route and no area on hold or eased.
  bool get isEmpty => safetyRoute == null && lines.isEmpty;

  Map<String, Object?> toJson() => {
    'local_date': localDate,
    'safety_route': safetyRoute,
    'lines': lines,
  };

  /// Null when [raw] is not what [toJson] wrote.
  static OfflineSafetyNotes? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final date = raw['local_date'];
    final route = raw['safety_route'];
    final lines = raw['lines'];
    if (date is! String ||
        DateTime.tryParse(date) == null ||
        (route != null && route is! String) ||
        lines is! List ||
        lines.any((line) => line is! String)) {
      return null;
    }
    return OfflineSafetyNotes(
      localDate: date,
      safetyRoute: route as String?,
      lines: List.unmodifiable(lines.cast<String>()),
    );
  }
}

/// Said on Train with no connection when there is nothing saved to say.
const offlinePainHoldsUnknown =
    "Pain holds can't be checked offline. Skip any area on hold.";
