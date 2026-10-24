import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tracend/features/train/guidance/training_guidance.dart';
import 'package:tracend/features/train/guidance/training_guidance_repository.dart';

/// Today's training guidance for Train: whether a lighter week could help and
/// how the week's cardio stands.
///
/// The server answers only for the athlete's own local today, and the date
/// sent is always that day as the server named it: the training hub's
/// `local_today`, passed in by Train after each hub load, or [serverToday]
/// (the same function the readiness adjustment uses). The phone's date is
/// never sent. Guidance for any other day than the server's is never shown.
class TrainingGuidanceController extends ChangeNotifier {
  TrainingGuidanceController({
    required this.repository,
    this.serverToday,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TrainingGuidanceRepository repository;

  /// Asks the server for its own today. Null when there is nothing to ask.
  final Future<DateTime?> Function()? serverToday;
  final DateTime Function() _clock;

  TrainingGuidance? _current;
  TrainingGuidanceFailure? _loadFailure;
  TrainingGuidanceFailure? _prepareFailure;
  String? _prepareCode;
  bool _loading = false;
  bool _preparing = false;
  DateTime? _knownToday;
  DateTime? _learnedOn;
  int _reads = 0;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _iso(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// What the server last said about today, or null when nothing has loaded
  /// or what loaded is for a different day than the server's today.
  TrainingGuidance? get current {
    final value = _current;
    final today = _knownToday;
    if (value == null || (today != null && value.localDate != _iso(today))) {
      return null;
    }
    return value;
  }

  bool get loading => _loading;

  /// A lighter week is being prepared.
  bool get preparing => _preparing;

  /// Set when the last read failed. [current] may still hold the earlier one.
  TrainingGuidanceFailure? get loadFailure => _loadFailure;

  /// Set when the last request to prepare a lighter week did not go through.
  TrainingGuidanceFailure? get prepareFailure => _prepareFailure;

  /// The rule that turned the request down, when one did.
  String? get prepareCode => _prepareCode;

  /// Reads today's guidance. Pass the hub's `local_today` as [localToday]
  /// when it is known; without it the server is asked for its today.
  Future<void> load({DateTime? localToday}) async {
    if (localToday != null) _learn(localToday);
    final read = ++_reads;
    _loading = true;
    _loadFailure = null;
    notifyListeners();
    TrainingGuidance? guidance;
    TrainingGuidanceFailure? failure;
    try {
      guidance = await _read();
    } on TrainingGuidanceException catch (error) {
      failure = error.failure;
    } on Object catch (error) {
      debugPrint('Non-critical error: training guidance not read: $error');
      failure = TrainingGuidanceFailure.network;
    }
    if (read != _reads) return;
    _loading = false;
    _loadFailure = failure;
    if (guidance != null) {
      _current = guidance;
    } else if (failure == TrainingGuidanceFailure.wrongDate ||
        failure == TrainingGuidanceFailure.unreadable) {
      // What was shown no longer describes today.
      _current = null;
    }
    notifyListeners();
  }

  void _learn(DateTime day) {
    _knownToday = _dateOnly(day);
    _learnedOn = _dateOnly(_clock());
  }

  Future<DateTime?> _today() async {
    final known = _knownToday;
    if (known != null && _learnedOn == _dateOnly(_clock())) return known;
    final ask = serverToday;
    if (ask == null) return known;
    final day = await ask();
    if (day != null) _learn(day);
    return day ?? known;
  }

  Future<TrainingGuidance> _read() async {
    final day = await _today();
    if (day == null) {
      throw const TrainingGuidanceException(TrainingGuidanceFailure.network);
    }
    try {
      return await repository.load(day);
    } on TrainingGuidanceException catch (error) {
      final ask = serverToday;
      if (error.failure != TrainingGuidanceFailure.wrongDate || ask == null) {
        rethrow;
      }
      // The server's day moved on (midnight where the athlete is).
      final actual = await ask();
      if (actual == null || _dateOnly(actual) == day) rethrow;
      _learn(actual);
      return repository.load(_knownToday!);
    }
  }

  /// Stores the lighter week the rules suggest and returns its proposal id, or
  /// null when it could not be prepared (see [prepareFailure]). Nothing is
  /// applied: the athlete answers the proposal. Guidance is read again after,
  /// so the card shows what is true.
  Future<String?> prepareDeload() async {
    // Taken before anything is awaited, so a second tap while the first is on
    // its way sends nothing.
    if (_preparing) return null;
    _preparing = true;
    _prepareFailure = null;
    _prepareCode = null;
    notifyListeners();
    String? id;
    TrainingGuidanceFailure? failure;
    String? code;
    try {
      // The server's today, asked again when the phone's day has changed since
      // it was learned.
      final day = await _today();
      if (day == null) {
        throw const TrainingGuidanceException(TrainingGuidanceFailure.network);
      }
      id = await repository.prepareDeload(day);
    } on TrainingGuidanceException catch (error) {
      failure = error.failure;
      code = error.code;
    } on Object catch (error) {
      // Anything else, an Error included, still ends the request: the card
      // must never be left waiting on a tap that cannot finish.
      debugPrint('Non-critical error: lighter week not prepared: $error');
      failure = TrainingGuidanceFailure.network;
    } finally {
      _preparing = false;
      _prepareFailure = failure;
      _prepareCode = code;
      notifyListeners();
    }
    if (id == null &&
        failure != TrainingGuidanceFailure.network &&
        failure != TrainingGuidanceFailure.otherProposalPending) {
      unawaited(load());
    }
    return id;
  }
}
