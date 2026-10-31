import 'package:flutter/widgets.dart';

/// How old a tab's data may get before the app coming back to the front, or
/// the tab being opened again, reloads it.
const staleAfter = Duration(minutes: 10);

/// The phone's calendar day as `YYYY-MM-DD`.
String localDayKey(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}';

/// Whether two moments fall on the same calendar day.
bool isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// When a screen's data was last loaded and for which day, so the screen can
/// tell, on resume or when its tab opens again, whether it is old or belongs
/// to a day that is over.
class LoadStamp {
  LoadStamp(this._clock, {this.maxAge = staleAfter});

  final DateTime Function() _clock;

  /// How long a load stays fresh.
  final Duration maxAge;

  DateTime? _at;
  String? _day;

  /// Records a load that just arrived, for [day] (`YYYY-MM-DD`) or, by
  /// default, the phone's today.
  void mark({String? day}) {
    final now = _clock();
    _at = now;
    _day = day ?? localDayKey(now);
  }

  /// No load has arrived yet.
  bool get isEmpty => _at == null;

  /// The day the last load was for, if one arrived.
  String? get day => _day;

  /// True when nothing has loaded, the load is older than [maxAge], or it
  /// was for another day than [today] (the phone's today by default).
  bool isStale({String? today, Duration? within}) {
    final at = _at;
    if (at == null) return true;
    final now = _clock();
    return now.difference(at) > (within ?? maxAge) ||
        _day != (today ?? localDayKey(now));
  }
}

/// Work that must finish before the screens refresh on resume. The gate holds
/// the time-zone sync here: the server's local dates follow the stored zone,
/// so a screen that refreshed first would read the old `local_today` and mark
/// it fresh. A slow or failed sync never holds a refresh longer than
/// [timeout].
class ResumeGate {
  ResumeGate._();

  /// The longest a refresh waits for held work.
  static const timeout = Duration(seconds: 5);

  static Future<void>? _pending;

  /// The held work, or null when the screens may refresh at once.
  static Future<void>? get pending => _pending;

  /// Holds the resume refresh until [work] completes, fails or times out. Call
  /// it from a lifecycle observer registered before the screens', so it runs
  /// before theirs.
  static void hold(Future<void> work) {
    late final Future<void> held;
    held = work.timeout(timeout).catchError((Object _) {}).whenComplete(() {
      if (identical(_pending, held)) _pending = null;
    });
    _pending = held;
  }
}

/// Calls [onResume] each time the app comes back to the front, once the work
/// the [ResumeGate] holds has finished. The single place a screen listens for
/// it: attach in `initState`, detach in `dispose`.
class ResumeObserver with WidgetsBindingObserver {
  ResumeObserver(this.onResume);

  final VoidCallback onResume;
  bool _attached = false;

  void attach() {
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final pending = ResumeGate.pending;
    if (pending == null) {
      onResume();
      return;
    }
    pending.then((_) {
      if (_attached) onResume();
    });
  }
}
