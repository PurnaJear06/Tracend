import 'package:shared_preferences/shared_preferences.dart';

/// Which referral sheets the athlete has acknowledged, per athlete, so a
/// referral that must be acknowledged is shown until it has been, and then
/// once for that day and route rather than at every launch.
class SafetyAcknowledgements {
  SafetyAcknowledgements(this._preferences, {String? userId})
    : _key = userId == null ? _anonymousKey : storageKeyFor(userId);

  final SharedPreferences _preferences;
  final String _key;

  static const _anonymousKey = 'safety_acknowledged';
  static const _kept = 14;

  static String storageKeyFor(String userId) => '$_anonymousKey.$userId';

  /// The key of one referral: its day and route.
  static String keyOf(String localDate, String route) => '$localDate:$route';

  bool isAcknowledged(String key) =>
      (_preferences.getStringList(_key) ?? const []).contains(key);

  Future<void> acknowledge(String key) async {
    final keys = [...?_preferences.getStringList(_key)];
    if (keys.contains(key)) return;
    keys.add(key);
    await _preferences.setStringList(
      _key,
      keys.length > _kept ? keys.sublist(keys.length - _kept) : keys,
    );
  }
}
