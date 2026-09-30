import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/health/health_repository.dart';

void main() {
  const connectionLost = 'Connection lost. Check your internet and try again.';

  test(
    'a request that never reached the server reads as a lost connection',
    () {
      expect(
        healthSyncFailureMessage(
          const FunctionsFetchException(
            details: SocketException('Network is unreachable'),
          ),
        ),
        connectionLost,
      );
      expect(
        healthSyncFailureMessage(const SocketException('Connection reset')),
        connectionLost,
      );
    },
  );

  test('a timeout says so', () {
    expect(
      healthSyncFailureMessage(TimeoutException('slow')),
      'Sync timed out. The server may be starting up. Try again now.',
    );
  });

  test('a server answer keeps its raw text for the beta', () {
    expect(
      healthSyncFailureMessage(
        const FunctionsHttpException(
          status: 422,
          details: {'error': 'invalid_payload'},
        ),
      ),
      'FunctionsHttpException(status: 422, details: {error: invalid_payload}, '
      'reasonPhrase: null)',
    );
  });
}
