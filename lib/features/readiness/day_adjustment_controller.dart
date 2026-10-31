import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_repository.dart';
import 'package:tracend/shared/diagnostics.dart';

/// Today's same-day adjustment, shared by Today and Train so an answer given
/// on one shows on the other at once.
///
/// The server answers only for the athlete's own local today, and the date
/// sent is always that day as the server named it: the training hub's
/// `local_today`, passed in by Train or fetched through [serverToday]. The
/// phone's date is never sent; it only tells the controller when a day has
/// passed since the server's was learned. An adjustment for any other day than
/// the one the server named is never shown or answered.
class DayAdjustmentController extends ChangeNotifier {
  DayAdjustmentController({
    required this.repository,
    DateTime Function()? clock,
    this.serverToday,
    this.onAnswered,
  }) : _clock = clock ?? DateTime.now;

  final DayAdjustmentRepository repository;
  final DateTime Function() _clock;

  /// Asks the server for its own today (the hub's `local_today`). Null when
  /// there is nothing to ask, as without a backend.
  final Future<DateTime?> Function()? serverToday;

  /// Called with every adjustment the server gave (a read or an answer), so
  /// the phone can keep its sore-area notes for a launch with no connection.
  final void Function(DayAdjustment adjustment)? onAnswered;

  /// An adjustment older than this, or from another day, is read again when
  /// the athlete comes back.
  static const staleAfter = Duration(minutes: 30);

  DayAdjustment? _current;
  DayAdjustmentFailure? _loadFailure;
  DayAdjustmentFailure? _answerFailure;
  bool _loading = false;
  bool _busy = false;
  DateTime? _knownToday;

  /// The phone's day when [_knownToday] was learned.
  DateTime? _learnedOn;
  DateTime? _loadedAt;
  int _reads = 0;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _iso(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// What the server last said about today, or null when nothing has loaded
  /// or what loaded is for a different day than the server's today.
  DayAdjustment? get current {
    final value = _current;
    final today = _knownToday;
    if (value == null || (today != null && value.localDate != _iso(today))) {
      return null;
    }
    return value;
  }

  /// The server's today as `YYYY-MM-DD`, once the hub or the server has named
  /// it; null before that. It is known even when the adjustment itself could
  /// not be read.
  String? get serverDay {
    final day = _knownToday;
    return day == null ? null : _iso(day);
  }

  bool get loading => _loading;

  /// An answer is on its way.
  bool get busy => _busy;

  /// Set when the last read failed. [current] may still hold the earlier one.
  DayAdjustmentFailure? get loadFailure => _loadFailure;

  /// Set when the last answer did not go through.
  DayAdjustmentFailure? get answerFailure => _answerFailure;

  /// When [current] was read; null before the first read.
  DateTime? get loadedAt => _loadedAt;

  /// Reads today's adjustment. Pass the hub's `local_today` as [localToday]
  /// when it is known: it replaces what the controller knew. Without it the
  /// server is asked for its today.
  Future<void> load({DateTime? localToday}) async {
    if (localToday != null) _learn(localToday);
    final read = ++_reads;
    _loading = true;
    _loadFailure = null;
    notifyListeners();
    DayAdjustment? adjustment;
    DayAdjustmentFailure? failure;
    try {
      adjustment = await _read();
    } on DayAdjustmentException catch (error) {
      failure = error.failure;
    } on Exception catch (error) {
      logNonCritical(error, 'day adjustment not read');
      failure = DayAdjustmentFailure.network;
    }
    if (read != _reads) return;
    _loading = false;
    _loadFailure = failure;
    if (adjustment != null) {
      _current = adjustment;
      _loadedAt = _clock();
      _remember(adjustment);
    } else if (failure == DayAdjustmentFailure.wrongDate ||
        failure == DayAdjustmentFailure.unreadable) {
      // What was shown no longer describes today.
      _current = null;
    }
    notifyListeners();
  }

  void _remember(DayAdjustment adjustment) {
    try {
      onAnswered?.call(adjustment);
    } catch (error) {
      logNonCritical(error, 'day adjustment not remembered');
    }
  }

  void _learn(DateTime day) {
    _knownToday = _dateOnly(day);
    _learnedOn = _dateOnly(_clock());
  }

  /// The server's today: what Train's hub gave, or what [serverToday] says.
  /// Asked again when the phone's day has changed since it was learned.
  Future<DateTime?> _today() async {
    final known = _knownToday;
    if (known != null && _learnedOn == _dateOnly(_clock())) return known;
    final ask = serverToday;
    if (ask == null) return known;
    final day = await ask();
    if (day != null) {
      _learn(day);
      // Screens that follow the server's day need not wait for the read.
      notifyListeners();
    }
    return day ?? known;
  }

  Future<DayAdjustment> _read() async {
    final day = await _today();
    if (day == null) {
      throw const DayAdjustmentException(DayAdjustmentFailure.network);
    }
    try {
      return await repository.load(day);
    } on DayAdjustmentException catch (error) {
      final ask = serverToday;
      if (error.failure != DayAdjustmentFailure.wrongDate || ask == null) {
        rethrow;
      }
      // The server's day moved on (midnight where the athlete is).
      final actual = await ask();
      if (actual == null || _dateOnly(actual) == day) rethrow;
      _learn(actual);
      return repository.load(_knownToday!);
    }
  }

  /// Reads again when [current] is old, from another day, or missing.
  Future<void> refreshIfStale() {
    if (_loading || _busy) return Future<void>.value();
    final loaded = _loadedAt;
    final now = _clock();
    final stale =
        loaded == null ||
        now.difference(loaded) > staleAfter ||
        _dateOnly(loaded) != _dateOnly(now);
    return stale ? load() : Future<void>.value();
  }

  /// Answers for the day on screen. [accept] true applies the proposal, or
  /// [chosen] when the athlete picked another kind; false trains as planned,
  /// which is also how an accepted answer is undone. Returns whether the
  /// server took the answer; on a refusal the day is read again, so the card
  /// shows what is true.
  Future<bool> respond({
    required bool accept,
    DayAdjustmentKind? chosen,
  }) async {
    final shown = current;
    if (_busy || shown == null) return false;
    final day = DateTime.tryParse(shown.localDate);
    if (day == null) return false;
    _busy = true;
    _answerFailure = null;
    ++_reads;
    _loading = false;
    notifyListeners();
    var taken = false;
    DayAdjustmentFailure? failure;
    try {
      final answer = await repository.respond(
        day,
        accept: accept,
        chosen: chosen,
      );
      ++_reads;
      _current = answer;
      _loadedAt = _clock();
      _loadFailure = null;
      taken = true;
      _remember(answer);
    } on DayAdjustmentException catch (error) {
      failure = error.failure;
    } on Exception catch (error) {
      logNonCritical(error, 'day adjustment not answered');
      failure = DayAdjustmentFailure.network;
    }
    _busy = false;
    _answerFailure = failure;
    notifyListeners();
    if (!taken &&
        failure != DayAdjustmentFailure.tooMany &&
        failure != DayAdjustmentFailure.network) {
      unawaited(load());
    }
    return taken;
  }
}
