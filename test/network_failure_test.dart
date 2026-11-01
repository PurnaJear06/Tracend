import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/shared/diagnostics.dart';

/// No signal is told apart from a fault: the first is logged, the second is
/// reported (phase_2_gate.dart), or counted toward a load that keeps failing.
void main() {
  test('a lost connection, however it is thrown, is a network failure', () {
    expect(isNetworkFailure(AuthRetryableFetchException()), isTrue);
    expect(isNetworkFailure(const SocketException('no route')), isTrue);
    expect(isNetworkFailure(const HandshakeException('tls')), isTrue);
    expect(isNetworkFailure(TimeoutException('slow')), isTrue);
    expect(isNetworkFailure(http.ClientException('offline')), isTrue);
    expect(
      isNetworkFailure(
        const FunctionsFetchException(details: SocketException('offline')),
      ),
      isTrue,
    );
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
    expect(
      isNetworkFailure(const FunctionsHttpException(status: 503)),
      isFalse,
    );
  });

  group('a load that keeps failing', () {
    late List<NonCriticalFailure> reported;

    setUp(() {
      resetLoadFailures();
      reported = [];
      final previous = failureSink;
      failureSink = (failure, _) => reported.add(failure);
      addTearDown(() {
        failureSink = previous;
        resetLoadFailures();
      });
    });

    const refused = PostgrestException(message: 'row 82.5 kg', code: '42501');

    test('reaches Sentry once, at the third failure in a row, by its code', () {
      for (var i = 0; i < 5; i++) {
        noteLoadFailure(refused, null, 'Today: daily brief');
      }
      expect(reported, hasLength(1));
      expect(
        reported.single.what,
        'Today: daily brief failed 3 times in a row',
      );
      expect(reported.single.detail, 'PostgrestException 42501');
    });

    test('a success starts the count again', () {
      noteLoadFailure(refused, null, 'Train: training hub');
      noteLoadFailure(refused, null, 'Train: training hub');
      noteLoadSuccess('Train: training hub');
      noteLoadFailure(refused, null, 'Train: training hub');
      noteLoadFailure(refused, null, 'Train: training hub');
      expect(reported, isEmpty);
      noteLoadFailure(refused, null, 'Train: training hub');
      expect(reported, hasLength(1));
    });

    test('each load keeps its own count', () {
      noteLoadFailure(refused, null, 'Today: daily brief');
      noteLoadFailure(refused, null, 'Train: training hub');
      noteLoadFailure(refused, null, 'Today: daily brief');
      noteLoadFailure(refused, null, 'Train: training hub');
      expect(reported, isEmpty);
    });

    test('another account starts the count again', () {
      final previous = athleteSink;
      athleteSink = (_) {};
      addTearDown(() {
        athleteSink = previous;
        identifyAthlete(null);
      });
      identifyAthlete('athlete-a');
      noteLoadFailure(refused, null, 'Today: daily brief');
      noteLoadFailure(refused, null, 'Today: daily brief');
      identifyAthlete('athlete-a');
      expect(loadFailuresInARow('Today: daily brief'), 2);

      identifyAthlete('athlete-b');
      expect(loadFailuresInARow('Today: daily brief'), 0);
      noteLoadFailure(refused, null, 'Today: daily brief');
      identifyAthlete(null);
      expect(loadFailuresInARow('Today: daily brief'), 0);
      expect(reported, isEmpty);
    });

    test('no signal is not counted', () {
      for (var i = 0; i < 5; i++) {
        noteLoadFailure(
          const SocketException('offline'),
          null,
          'Apple Health sync',
        );
      }
      noteLoadFailure(refused, null, 'Apple Health sync');
      expect(reported, isEmpty);
    });
  });
}
