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

/// Keeps the Supabase session in the Keychain instead of the app's
/// preferences file.
///
/// The first launch after an update moves a session already in preferences
/// into the Keychain, checks it reads back, and only then removes the old
/// copy, so nobody is signed out. If the Keychain cannot be written, that
/// launch keeps using the old copy and the next launch tries again. A launch
/// with no marker and no old session is a fresh install: anything the
/// Keychain still holds from a deleted install is removed, as deleting the app
/// always signed the athlete out.
class KeychainSessionStorage extends LocalStorage {
  KeychainSessionStorage({
    required this.persistSessionKey,
    this.secureStore = const KeychainSecureStore(),
    this.onMigrationFailed,
  });

  /// The key supabase_flutter uses: `sb-<project ref>-auth-token`.
  final String persistSessionKey;
  final SecureStore secureStore;

  /// Told when the move to the Keychain failed; never given the session.
  final void Function(Object error, StackTrace stackTrace)? onMigrationFailed;

  @visibleForTesting
  static const markerKey = 'tracend.session_store';
  static const _keychain = 'keychain';

  late final SharedPreferences _preferences;
  bool _usePreferences = false;

  /// The Supabase session key for [supabaseUrl], as supabase_flutter derives it.
  static String sessionKeyFor(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _preferences = await SharedPreferences.getInstance();
    if (_preferences.getString(markerKey) == _keychain) return;
    final legacy = _preferences.getString(persistSessionKey);
    try {
      if (legacy == null) {
        await secureStore.delete(persistSessionKey);
      } else {
        await secureStore.write(persistSessionKey, legacy);
        if (await secureStore.read(persistSessionKey) != legacy) {
          throw StateError('The Keychain did not return the stored session.');
        }
        await _preferences.remove(persistSessionKey);
      }
      await _preferences.setString(markerKey, _keychain);
    } catch (error, stackTrace) {
      _usePreferences = legacy != null;
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
