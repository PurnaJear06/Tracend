import 'package:flutter/foundation.dart';
import 'package:tracend/shared/formatting.dart';

/// Whether the athlete trains today, as the server works it out
/// (`availability` in the daily brief 1.9 and the training hub 1.10). The
/// server decides every part of it: a break the athlete set or approved, and
/// today's check-in. The app only shows it.
enum AvailabilityStatus {
  /// A normal day: the plan applies.
  available,

  /// Today's check-in said the athlete can't train today.
  unavailableToday,

  /// Today falls inside a break.
  paused,
}

/// A break: no session is due from [startDate] through [endDate], its last
/// day. The plan itself never changes and picks up again the day after.
@immutable
class TrainingPause {
  const TrainingPause({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.source,
    required this.running,
    this.note,
  });

  final String id;
  final DateTime startDate;

  /// The last day of the break (inclusive).
  final DateTime endDate;
  final String reason;

  /// `athlete` (set on Today or Train) or `coach` (approved from Coach).
  final String source;

  /// True when today is inside it; false for a break that starts later.
  final bool running;
  final String? note;

  /// The first day the plan applies again.
  DateTime get resumesOn => endDate.add(const Duration(days: 1));

  /// Null unless the payload is exactly a break.
  static TrainingPause? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final start = availabilityDate(json['start_date']);
    final end = availabilityDate(json['end_date']);
    if (id is! String || start == null || end == null || end.isBefore(start)) {
      return null;
    }
    final note = json['note'];
    return TrainingPause(
      id: id,
      startDate: start,
      endDate: end,
      reason: json['reason'] as String? ?? 'rest',
      source: json['source'] as String? ?? 'athlete',
      running: json['running'] as bool? ?? false,
      note: note is String && note.trim().isNotEmpty ? note : null,
    );
  }
}

/// The days right after a break, until the first session is logged.
@immutable
class PauseReturn {
  const PauseReturn({required this.pauseId, required this.lastPausedDay});

  final String pauseId;
  final DateTime lastPausedDay;

  static PauseReturn? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['pause_id'];
    final day = availabilityDate(json['last_paused_day']);
    if (id is! String || day == null) return null;
    return PauseReturn(pauseId: id, lastPausedDay: day);
  }
}

@immutable
class TrainingAvailability {
  const TrainingAvailability({
    this.status = AvailabilityStatus.available,
    this.unavailableToday = false,
    this.paused = false,
    this.pause,
    this.returnFromPause,
    this.offerBreak = false,
  });

  /// What an older payload without `availability` means: a normal day.
  static const available = TrainingAvailability();

  final AvailabilityStatus status;

  /// Today's check-in said the athlete can't train today.
  final bool unavailableToday;

  /// Today is inside [pause].
  final bool paused;

  /// The running break, else the next one; null when there is none.
  final TrainingPause? pause;

  /// Set in the first days back from a break, until a session is logged.
  final PauseReturn? returnFromPause;

  /// Today's and yesterday's check-ins both said the athlete can't train and
  /// no break is set: Today offers one. Nothing is set until the athlete taps.
  final bool offerBreak;

  /// A break that starts on a later day.
  TrainingPause? get upcomingPause {
    final pause = this.pause;
    return pause != null && !pause.running && !paused ? pause : null;
  }

  /// The break today is inside, when there is one.
  TrainingPause? get runningPause {
    final pause = this.pause;
    return pause != null && (pause.running || paused) ? pause : null;
  }

  /// Parses the `availability` object; anything that is not one reads as a
  /// normal day.
  factory TrainingAvailability.fromJson(Object? json) {
    if (json is! Map) return available;
    final paused = json['paused'] == true;
    final unavailable = json['unavailable_today'] == true;
    return TrainingAvailability(
      status: switch (json['status']) {
        'paused' => AvailabilityStatus.paused,
        'unavailable_today' => AvailabilityStatus.unavailableToday,
        _ =>
          paused
              ? AvailabilityStatus.paused
              : unavailable
              ? AvailabilityStatus.unavailableToday
              : AvailabilityStatus.available,
      },
      unavailableToday: unavailable,
      paused: paused,
      pause: TrainingPause.fromJson(json['pause']),
      returnFromPause: PauseReturn.fromJson(json['return_from_pause']),
      offerBreak: json['offer_break'] == true,
    );
  }
}

/// A `YYYY-MM-DD` value as a local calendar day; null for anything else.
DateTime? availabilityDate(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

/// "1–15 Nov", "28 Oct – 3 Nov", or a single day.
String breakRangeLabel(DateTime start, DateTime end, {DateTime? now}) {
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return shortDate(start, now: now);
  }
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${shortDate(end, now: now)}';
  }
  return '${shortDate(start, now: now)} – ${shortDate(end, now: now)}';
}
