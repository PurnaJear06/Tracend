import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/shared/diagnostics.dart';

/// No signal is told apart from a fault: the first is logged, the second is
/// reported (phase_2_gate.dart).
void main() {
  test('a lost connection, however it is thrown, is a network failure', () {
    expect(isNetworkFailure(AuthRetryableFetchException()), isTrue);
    expect(isNetworkFailure(const SocketException('no route')), isTrue);
    expect(isNetworkFailure(const HandshakeException('tls')), isTrue);
    expect(isNetworkFailure(TimeoutException('slow')), isTrue);
    expect(isNetworkFailure(http.ClientException('offline')), isTrue);
  });

  test('a server error or anything else is not', () {
    expect(
      isNetworkFailure(AuthRetryableFetchException(statusCode: '502')),
      isFalse,
    );
    expect(
      isNetworkFailure(AuthApiException('bad', statusCode: '400')),
      isFalse,
    );
    expect(
      isNetworkFailure(const PostgrestException(message: 'x', code: '42501')),
      isFalse,
    );
    expect(isNetworkFailure(StateError('bug')), isFalse);
  });
}
