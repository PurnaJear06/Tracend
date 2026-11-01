import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a failure is, with nothing the athlete entered: its type and its
/// code. The text of an exception is never used: a `PostgrestException`
/// carries the failing row (the user id, a weight, a food) in its details.
String describeFailure(Object? error) {
  final String? code = switch (error) {
    PostgrestException(:final code) => code,
    AuthException(:final statusCode, :final code) => code ?? statusCode,
    FunctionException(:final status) => '$status',
    StorageException(:final statusCode) => statusCode,
    PlatformException(:final code) => code,
    _ => null,
  };
  final type = error == null ? 'unknown' : error.runtimeType.toString();
  return code == null || code.isEmpty ? type : '$type $code';
}

/// Whether [error] says the server could not be reached: no signal, a dropped
/// or refused connection, a failed TLS handshake, or a wait that ran out.
/// Auth's retryable failure counts only without a status code, which is how
/// it wraps a lost connection; with one it is a server error (5xx).
bool isNetworkFailure(Object error) => switch (error) {
  AuthRetryableFetchException(:final statusCode) => statusCode == null,
  // An Edge Function request that never reached the server (status 0).
  FunctionsFetchException() ||
  SocketException() ||
  HandshakeException() ||
  TimeoutException() ||
  http.ClientException() => true,
  _ => false,
};

/// Notes a failure the app carries on from. The debug log and the crash
/// report's breadcrumbs get the type and code only (see [describeFailure]),
/// never the exception text.
void logNonCritical(Object error, [String? what]) {
  final prefix = what == null ? '' : '$what: ';
  debugPrint('Non-critical error: $prefix${describeFailure(error)}');
}

/// A failure reported to Sentry by what failed and its code. It stands in for
/// the original exception, whose text may hold health or meal values.
class NonCriticalFailure implements Exception {
  const NonCriticalFailure(this.what, this.detail);

  final String what;
  final String detail;

  @override
  String toString() => 'NonCriticalFailure: $what ($detail)';
}

/// Where [reportNonCritical] sends a failure. Sentry drops it without a DSN.
@visibleForTesting
void Function(NonCriticalFailure failure, StackTrace? stackTrace) failureSink =
    _toSentry;

void _toSentry(NonCriticalFailure failure, StackTrace? stackTrace) {
  Sentry.captureException(failure, stackTrace: stackTrace).ignore();
}

/// [logNonCritical] plus a Sentry event for a failure that should be seen
/// (a refresh that keeps failing), still carrying the type and code only.
void reportNonCritical(Object error, StackTrace? stackTrace, String what) {
  logNonCritical(error, what);
  failureSink(NonCriticalFailure(what, describeFailure(error)), stackTrace);
}

/// Where [identifyAthlete] sends the account id. Sentry drops it without a
/// DSN.
@visibleForTesting
void Function(String? userId) athleteSink = _toSentryUser;

void _toSentryUser(String? userId) {
  unawaited(
    Future.sync(
      () => Sentry.configureScope(
        (scope) =>
            scope.setUser(userId == null ? null : SentryUser(id: userId)),
      ),
    ).catchError((Object _) {}),
  );
}

/// Names the signed-in athlete on the app's Sentry events by their account
/// id (the Supabase user id, never the email), so one tester's failures can
/// be found; null when the session ends. `scrubEvent` keeps the id alone.
void identifyAthlete(String? userId) => athleteSink(userId);

/// How many times in a row each named load has failed.
final _loadFailures = <String, int>{};

/// The failure in a row of one load that reaches Sentry.
const repeatedLoadFailure = 3;

/// Notes that the load named [what] (the daily brief, the training hub, an
/// Apple Health sync, the coaching decision) failed. The third failure in a
/// row sends one Sentry event ([reportNonCritical]: type and code only), so a
/// screen that keeps failing for an athlete is seen without an event for each
/// retry; the others are only logged. No signal is not a fault: a network
/// failure is logged and leaves the count as it was.
void noteLoadFailure(Object error, StackTrace? stackTrace, String what) {
  if (isNetworkFailure(error)) {
    logNonCritical(error, what);
    return;
  }
  final streak = (_loadFailures[what] ?? 0) + 1;
  _loadFailures[what] = streak;
  if (streak == repeatedLoadFailure) {
    reportNonCritical(error, stackTrace, '$what failed $streak times in a row');
  } else {
    logNonCritical(error, what);
  }
}

/// Notes that the load named [what] succeeded, which ends its run of
/// failures.
void noteLoadSuccess(String what) => _loadFailures.remove(what);

/// Forgets every run of failures, between tests.
@visibleForTesting
void resetLoadFailures() => _loadFailures.clear();
