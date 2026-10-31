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

/// Calls [onResume] each time the app comes back to the front. The single
/// place a screen listens for it: attach in `initState`, detach in `dispose`.
class ResumeObserver with WidgetsBindingObserver {
  ResumeObserver(this.onResume);

  final VoidCallback onResume;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
