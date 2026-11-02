import 'package:tracend/shared/local_health_store.dart';

/// Which referral sheets the athlete has acknowledged, per athlete, so a
/// referral that must be acknowledged is shown until it has been, and then
/// once for that day and route rather than at every launch.
class SafetyAcknowledgements {
  SafetyAcknowledgements(this._store, {String? userId})
    : _key = userId == null ? storageKey : storageKeyFor(userId);

  final LocalHealthStore _store;
  final String _key;

  static const storageKey = 'safety_acknowledged';
  static const kept = 14;

  static String storageKeyFor(String userId) => '$storageKey.$userId';

  /// The key of one referral: its day and route.
  static String keyOf(String localDate, String route) => '$localDate:$route';

  Future<bool> isAcknowledged(String key) async =>
      (await _store.getStringList(_key) ?? const []).contains(key);

  Future<void> acknowledge(String key) async {
    final keys = [...?await _store.getStringList(_key)];
    if (keys.contains(key)) return;
    keys.add(key);
    await _store.setStringList(
      _key,
      keys.length > kept ? keys.sublist(keys.length - kept) : keys,
    );
  }
}
