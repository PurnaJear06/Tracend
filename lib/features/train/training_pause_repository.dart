import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/shared/diagnostics.dart';
import 'package:tracend/shared/training_availability.dart';

/// The longest break, in days counting the first and the last.
const maxBreakDays = 42;

/// How many days ahead a break may start (0 is today).
const maxBreakStartAhead = 2;

/// Why the server refused a break; each has plain words in
/// [pauseRefusalText].
enum PauseRefusal {
  datesInvalid('dates_invalid'),
  tooLong('pause_too_long'),
  startPast('pause_start_past'),
  startTooFar('pause_start_too_far'),
  overlaps('pause_overlaps'),
  noteTooLong('note_too_long'),
  unknown('');

  const PauseRefusal(this.wire);
  final String wire;

  static PauseRefusal parse(Object? value) => PauseRefusal.values.firstWhere(
    (refusal) => refusal.wire.isNotEmpty && refusal.wire == value,
    orElse: () => PauseRefusal.unknown,
  );
}

String pauseRefusalText(PauseRefusal refusal) => switch (refusal) {
  PauseRefusal.datesInvalid =>
    'The last day has to be on or after the first day.',
  PauseRefusal.tooLong =>
    'A break can last up to $maxBreakDays days. Pick an earlier last day.',
  PauseRefusal.startPast => "A break can't start on a day that has passed.",
  PauseRefusal.startTooFar =>
    'A break can start today, tomorrow or the day after.',
  PauseRefusal.overlaps => 'A break already covers some of those days.',
  PauseRefusal.noteTooLong => 'Keep the note to 140 characters.',
  PauseRefusal.unknown => "Tracend couldn't set that break. Try again.",
};

/// What `start_training_pause_v1` answered.
class PauseStartResult {
  const PauseStartResult.started({
    required String this.pauseId,
    required this.startDate,
    required this.endDate,
  }) : refusal = null;

  const PauseStartResult.refused(
    PauseRefusal this.refusal, {
    required this.startDate,
    required this.endDate,
  }) : pauseId = null;

  final String? pauseId;
  final DateTime startDate;
  final DateTime endDate;
  final PauseRefusal? refusal;

  bool get started => pauseId != null;
}

/// What `end_training_pause_v1` answered: `ended` (today is a normal day
/// again), `cancelled` (it had not started) or `not_running`.
class PauseEndResult {
  const PauseEndResult({required this.status, this.endedOn});

  final String status;
  final DateTime? endedOn;
}

/// A break request that did not reach the server or came back unreadable.
class TrainingPauseException implements Exception {
  const TrainingPauseException(this.message);
  final String message;
  @override
  String toString() => 'TrainingPauseException: $message';
}

const _connectionMessage =
    'Could not reach Tracend. Check your connection and try again.';

/// Sets and ends breaks. Each call is the athlete's own tap: no model answer
/// reaches it, and the server checks every date.
abstract interface class TrainingPauseRepository {
  Future<PauseStartResult> start({
    required DateTime startDate,
    required DateTime endDate,
    String? note,
  });

  /// Ends a running break today, or cancels one that has not started. Also
  /// the Undo right after a break was set.
  Future<PauseEndResult> end(String pauseId);
}

String _day(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class SupabaseTrainingPauseRepository implements TrainingPauseRepository {
  const SupabaseTrainingPauseRepository(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>> _call(
    String function,
    Map<String, dynamic> params,
  ) async {
    final Object? value;
    try {
      value = await _client.rpc(function, params: params);
    } on Exception catch (error) {
      logNonCritical(error);
      throw const TrainingPauseException(_connectionMessage);
    }
    if (value is! Map || value['status'] is! String) {
      throw const TrainingPauseException(
        'Tracend sent an answer this version cannot read. Update the app and '
        'try again.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<PauseStartResult> start({
    required DateTime startDate,
    required DateTime endDate,
    String? note,
  }) async {
    final trimmed = note?.trim();
    final value = await _call('start_training_pause_v1', {
      'p_start_date': _day(startDate),
      'p_end_date': _day(endDate),
      if (trimmed != null && trimmed.isNotEmpty) 'p_note': trimmed,
    });
    return parsePauseStart(value, startDate: startDate, endDate: endDate);
  }

  @override
  Future<PauseEndResult> end(String pauseId) async {
    final value = await _call('end_training_pause_v1', {'p_pause_id': pauseId});
    return PauseEndResult(
      status: value['status'] as String,
      endedOn: availabilityDate(value['ended_on']),
    );
  }
}

/// Reads a `start_training_pause_v1` answer; the dates asked for stand in
/// when the answer leaves them out.
PauseStartResult parsePauseStart(
  Map<String, dynamic> value, {
  required DateTime startDate,
  required DateTime endDate,
}) {
  final start = availabilityDate(value['start_date']) ?? startDate;
  final end = availabilityDate(value['end_date']) ?? endDate;
  final id = value['pause_id'];
  if (value['status'] == 'started' && id is String) {
    return PauseStartResult.started(
      pauseId: id,
      startDate: start,
      endDate: end,
    );
  }
  return PauseStartResult.refused(
    PauseRefusal.parse(value['refusal']),
    startDate: start,
    endDate: end,
  );
}

/// Without a backend: every break is accepted and nothing is stored.
class FixtureTrainingPauseRepository implements TrainingPauseRepository {
  const FixtureTrainingPauseRepository();

  @override
  Future<PauseStartResult> start({
    required DateTime startDate,
    required DateTime endDate,
    String? note,
  }) async => PauseStartResult.started(
    pauseId: 'fixture-pause',
    startDate: startDate,
    endDate: endDate,
  );

  @override
  Future<PauseEndResult> end(String pauseId) async =>
      const PauseEndResult(status: 'ended');
}
