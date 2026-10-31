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
