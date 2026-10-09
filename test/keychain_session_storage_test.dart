import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/app/keychain_session_storage.dart';

class _FakeSecureStore implements SecureStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keychain unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _key = 'sb-qsfzzsjenopqqqhvpyaw-auth-token';
const _session = '{"access_token":"a","refresh_token":"r"}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the key matches the one supabase_flutter derives', () {
    expect(
      KeychainSessionStorage.sessionKeyFor(
        'https://qsfzzsjenopqqqhvpyaw.supabase.co',
      ),
      _key,
    );
  });

  test(
    'an existing session moves to the Keychain without signing out',
    () async {
      SharedPreferences.setMockInitialValues({_key: _session});
      final keychain = _FakeSecureStore();
      final storage = KeychainSessionStorage(
        persistSessionKey: _key,
        secureStore: keychain,
      );
      await storage.initialize();

      expect(await storage.accessToken(), _session);
      expect(keychain.values[_key], _session);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(_key), isNull);
      expect(
        preferences.getString(KeychainSessionStorage.markerKey),
        'keychain',
      );
    },
  );

  test('a fresh install clears a session left in the Keychain', () async {
    SharedPreferences.setMockInitialValues({});
    final keychain = _FakeSecureStore()..values[_key] = _session;
    final storage = KeychainSessionStorage(
      persistSessionKey: _key,
      secureStore: keychain,
    );
    await storage.initialize();

    expect(await storage.hasAccessToken(), isFalse);
    expect(keychain.values, isEmpty);
  });

  test('after the move the Keychain is never cleared on launch', () async {
    SharedPreferences.setMockInitialValues({
      KeychainSessionStorage.markerKey: 'keychain',
    });
    final keychain = _FakeSecureStore()..values[_key] = _session;
    final storage = KeychainSessionStorage(
      persistSessionKey: _key,
      secureStore: keychain,
    );
    await storage.initialize();

    expect(await storage.accessToken(), _session);
  });

  test(
    'sessions are written to the Keychain and removed on sign-out',
    () async {
      SharedPreferences.setMockInitialValues({
        KeychainSessionStorage.markerKey: 'keychain',
      });
      final keychain = _FakeSecureStore();
      final storage = KeychainSessionStorage(
        persistSessionKey: _key,
        secureStore: keychain,
      );
      await storage.initialize();

      await storage.persistSession(_session);
      expect(keychain.values[_key], _session);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(_key), isNull);

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
    },
  );

  test(
    'a Keychain failure keeps the old session and tries again later',
    () async {
      SharedPreferences.setMockInitialValues({_key: _session});
      final keychain = _FakeSecureStore()..failWrites = true;
      final failures = <Object>[];
      final storage = KeychainSessionStorage(
        persistSessionKey: _key,
        secureStore: keychain,
        onMigrationFailed: (error, _) => failures.add(error),
      );
      await storage.initialize();

      expect(await storage.accessToken(), _session);
      expect(failures, hasLength(1));
      expect(failures.single.toString(), isNot(contains('access_token')));
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(KeychainSessionStorage.markerKey), isNull);

      await storage.persistSession('{"access_token":"b"}');
      expect(preferences.getString(_key), '{"access_token":"b"}');
    },
  );
}
