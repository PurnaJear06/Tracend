import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/auth/account_session.dart';

/// Where a deletion stands, as far as the server has confirmed it.
enum AccountDeletionOutcome {
  /// Auth no longer has the account; this device is signed out.
  deleted,

  /// Auth refused the session before the account could be checked; this
  /// device is signed out and the athlete signs in to see whether it remains.
  signedOut,

  /// Not confirmed either way: the request is still running on the server,
  /// or the connection dropped. Checking again settles it.
  unconfirmed,
}

/// The server says the deletion did not run or failed: the account remains.
class AccountDeletionFailed implements Exception {
  const AccountDeletionFailed();

  @override
  String toString() => 'AccountDeletionFailed';
}

abstract interface class AccountDeletionRepository {
  /// Re-authenticates and asks the server to delete the account. Throws
  /// [AuthException] when the password is refused and
  /// [AccountDeletionFailed] when the server reports the account remains.
  Future<AccountDeletionOutcome> delete({
    required String accountPassword,
    required String confirmation,
  });

  /// Asks the server once whether the account is gone, sending no new
  /// request. Throws [AccountDeletionFailed] when the account remains and no
  /// deletion is running.
  Future<AccountDeletionOutcome> confirm();
}

class SupabaseAccountDeletionRepository implements AccountDeletionRepository {
  SupabaseAccountDeletionRepository(
    this._client, {
    LocalAccountData? localData,
    this.requestTimeout = const Duration(seconds: 60),
    this.checkInterval = const Duration(seconds: 5),
    this.checks = 6,
    this.staleAfter = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _localData = localData ?? LocalAccountData(),
       _now = now ?? DateTime.now;

  final SupabaseClient _client;
  final LocalAccountData _localData;
  final DateTime Function() _now;

  /// The longest the app waits for the server's answer. The server keeps
  /// going after the app stops waiting; [confirm] reads where it got to.
  final Duration requestTimeout;

  /// After an unanswered request, the app asks [checks] times, this far
  /// apart, before it hands the choice to check again to the athlete.
  final Duration checkInterval;
  final int checks;

  /// An Edge Function stops long before this, so a request still open after
  /// it is no longer running and may be sent again.
  final Duration staleAfter;

  @override
  Future<AccountDeletionOutcome> delete({
    required String accountPassword,
    required String confirmation,
  }) async {
    // A request the app was closed during may have finished since. Anything
    // short of that (offline, or a request still running) sends again: the
    // server returns a running request instead of starting a second one.
    final before = await confirmOrNull();
    if (before == AccountDeletionOutcome.deleted ||
        before == AccountDeletionOutcome.signedOut) {
      return before!;
    }
    final email = _client.auth.currentUser?.email;
    if (email == null) throw const AuthException('Sign in again to delete.');
    await _client.auth.signInWithPassword(
      email: email,
      password: accountPassword,
    );
    try {
      final result = await _client.functions
          .invoke(
            'privacy-delete-account',
            body: {'confirmation': confirmation},
          )
          .timeout(requestTimeout);
      final body = result.data;
      if (body is Map && body['status'] == 'completed') {
        return _signedOut(
          AccountDeletionOutcome.deleted,
          _client.auth.currentUser?.id,
        );
      }
    } catch (e) {
      // Unanswered or refused: the server's state decides below.
      debugPrint('Non-critical error: account deletion request: $e');
    }
    for (var check = 0; check < checks; check++) {
      if (check > 0) await Future<void>.delayed(checkInterval);
      final outcome = await confirm();
      if (outcome != AccountDeletionOutcome.unconfirmed) return outcome;
    }
    return AccountDeletionOutcome.unconfirmed;
  }

  @override
  Future<AccountDeletionOutcome> confirm() async {
    final outcome = await confirmOrNull();
    if (outcome != null) return outcome;
    throw const AccountDeletionFailed();
  }

  /// Like [confirm], but null when the account remains and no deletion is
  /// running.
  @visibleForTesting
  Future<AccountDeletionOutcome?> confirmOrNull() async {
    // A refused refresh removes the session, and the user id with it.
    final userId = _client.auth.currentUser?.id;
    try {
      if (_client.auth.currentSession?.isExpired ?? false) {
        await _client.auth.refreshSession();
      }
      await _client.auth.getUser();
    } on AuthException catch (error) {
      if (isDeletedUser(error)) {
        return _signedOut(AccountDeletionOutcome.deleted, userId);
      }
      if (isRejectedSession(error)) {
        return _signedOut(AccountDeletionOutcome.signedOut, userId);
      }
      return AccountDeletionOutcome.unconfirmed;
    }
    final List<dynamic> rows;
    try {
      rows = await _client
          .from('deletion_requests')
          .select('status,requested_at,started_at')
          .order('requested_at', ascending: false)
          .limit(1);
    } catch (e) {
      debugPrint('Non-critical error: deletion state not read: $e');
      return AccountDeletionOutcome.unconfirmed;
    }
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    final status = row['status'];
    if (status != 'queued' && status != 'processing') return null;
    final since = DateTime.tryParse(
      (row['started_at'] ?? row['requested_at']) as String? ?? '',
    );
    if (since == null || _now().difference(since) > staleAfter) return null;
    return AccountDeletionOutcome.unconfirmed;
  }

  Future<AccountDeletionOutcome> _signedOut(
    AccountDeletionOutcome outcome,
    String? userId,
  ) async {
    await endRejectedSession(
      _client,
      _localData,
      userId,
      accountDeleted: outcome == AccountDeletionOutcome.deleted,
    );
    return outcome;
  }
}

class FixtureAccountDeletionRepository implements AccountDeletionRepository {
  const FixtureAccountDeletionRepository();

  @override
  Future<AccountDeletionOutcome> delete({
    required String accountPassword,
    required String confirmation,
  }) async => AccountDeletionOutcome.deleted;

  @override
  Future<AccountDeletionOutcome> confirm() async =>
      AccountDeletionOutcome.deleted;
}
