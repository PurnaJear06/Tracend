import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AccountDeletionRepository {
  Future<void> delete({
    required String accountPassword,
    required String confirmation,
  });
}

class SupabaseAccountDeletionRepository implements AccountDeletionRepository {
  const SupabaseAccountDeletionRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> delete({
    required String accountPassword,
    required String confirmation,
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) throw const AuthException('Sign in again to delete.');
    await _client.auth.signInWithPassword(
      email: email,
      password: accountPassword,
    );
    final result = await _client.functions.invoke(
      'privacy-delete-account',
      body: {'confirmation': confirmation},
    );
    final body = result.data;
    if (result.status != 200 || body is! Map || body['status'] != 'completed') {
      throw StateError('Account deletion did not complete.');
    }
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}

class FixtureAccountDeletionRepository implements AccountDeletionRepository {
  const FixtureAccountDeletionRepository();

  @override
  Future<void> delete({
    required String accountPassword,
    required String confirmation,
  }) async {}
}
