import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the session string is kept: the iOS Keychain in the app, a fake in
/// tests.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The Keychain, readable after the first unlock since boot (so background
/// work still finds the session) and never synced to other devices or backups.
class KeychainSecureStore implements SecureStore {
  const KeychainSecureStore();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The app's preferences file, behind an interface so tests can make a write
/// or a removal fail.
abstract interface class SessionPreferences {
  String? getString(String key);
  bool containsKey(String key);
  Future<bool> setString(String key, String value);
  Future<bool> remove(String key);
}

class _SharedSessionPreferences implements SessionPreferences {
  const _SharedSessionPreferences(this._preferences);
  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  bool containsKey(String key) => _preferences.containsKey(key);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);
}

Future<SessionPreferences> _sharedPreferences() async =>
    _SharedSessionPreferences(await SharedPreferences.getInstance());

/// Keeps the Supabase session in the Keychain instead of the app's
/// preferences file.
///
/// The first launch after an update copies a session already in preferences
/// into the Keychain and checks it reads back. Only then is the marker saved,
/// and only after the marker is saved is the old copy removed, so a failure
/// at any step leaves a launch that still has its session and a next launch
/// that tries again. Until the marker is saved, sessions keep being written to
/// preferences. A launch with no marker and no old session is a fresh install:
/// anything the Keychain still holds from a deleted install is removed, as
/// deleting the app always signed the athlete out.
class KeychainSessionStorage extends LocalStorage {
  KeychainSessionStorage({
    required this.persistSessionKey,
    this.secureStore = const KeychainSecureStore(),
    this.preferences = _sharedPreferences,
    this.onMigrationFailed,
  });

  /// The key supabase_flutter uses: `sb-<project ref>-auth-token`.
  final String persistSessionKey;
  final SecureStore secureStore;
  final Future<SessionPreferences> Function() preferences;

  /// Told when the move to the Keychain failed; never given the session.
  final void Function(Object error, StackTrace stackTrace)? onMigrationFailed;

  @visibleForTesting
  static const markerKey = 'tracend.session_store';
  static const _keychain = 'keychain';

  late final SessionPreferences _preferences;
  bool _usePreferences = false;

  /// The Supabase session key for [supabaseUrl], as supabase_flutter derives it.
  static String sessionKeyFor(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _preferences = await preferences();
    if (_preferences.getString(markerKey) == _keychain) {
      await _removeLegacyCopy();
      return;
    }
    final legacy = _preferences.getString(persistSessionKey);
    try {
      if (legacy == null) {
        await secureStore.delete(persistSessionKey);
      } else {
        await secureStore.write(persistSessionKey, legacy);
        if (await secureStore.read(persistSessionKey) != legacy) {
          throw StateError('The Keychain did not return the stored session.');
        }
      }
      if (!await _preferences.setString(markerKey, _keychain)) {
        throw StateError('The session store marker was not saved.');
      }
    } catch (error, stackTrace) {
      // Nothing was removed: this launch keeps using preferences, and the
      // next one tries the move again.
      _usePreferences = true;
      onMigrationFailed?.call(error, stackTrace);
      return;
    }
    await _removeLegacyCopy();
  }

  /// Removes the preferences copy once the Keychain holds the session. A
  /// failed removal is reported and tried again on the next launch.
  Future<void> _removeLegacyCopy() async {
    if (!_preferences.containsKey(persistSessionKey)) return;
    try {
      if (!await _preferences.remove(persistSessionKey)) {
        throw StateError('The old session copy was not removed.');
      }
    } catch (error, stackTrace) {
      onMigrationFailed?.call(error, stackTrace);
    }
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() async => _usePreferences
      ? _preferences.getString(persistSessionKey)
      : secureStore.read(persistSessionKey);

  @override
  Future<void> removePersistedSession() async {
    await _preferences.remove(persistSessionKey);
    await secureStore.delete(persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_usePreferences) {
      await _preferences.setString(persistSessionKey, persistSessionString);
    } else {
      await secureStore.write(persistSessionKey, persistSessionString);
    }
  }
}
