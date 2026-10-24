import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/proposals/coach_proposal.dart';
import 'package:tracend/features/coach/proposals/coach_proposal_repository.dart';

const _connection =
    'Could not reach Tracend. Check your connection and try again.';

CoachProposalRepository _repository(
  Future<http.Response> Function(http.Request request) answer,
) => SupabaseCoachProposalRepository(
  SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient(answer),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  ),
);

http.Response _error(http.Request request, int status, String code) =>
    http.Response(
      jsonEncode({'code': code, 'message': 'refused'}),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  final failures = <String, Future<http.Response> Function(http.Request)>{
    'a dropped socket': (_) async => throw const SocketException('offline'),
    'a client error': (_) async => throw http.ClientException('offline'),
    'a timeout': (_) async => throw TimeoutException('slow'),
    'a server error': (request) async => _error(request, 500, 'XX000'),
  };

  for (final entry in failures.entries) {
    group(entry.key, () {
      test('on approve is a connection message', () async {
        await expectLater(
          _repository(entry.value).respond('p1', CoachProposalAction.approve),
          throwsA(
            isA<CoachProposalException>().having(
              (e) => e.message,
              'message',
              _connection,
            ),
          ),
        );
      });

      test('on undo is a connection message', () async {
        await expectLater(
          _repository(entry.value).undo('p1'),
          throwsA(
            isA<CoachProposalException>().having(
              (e) => e.message,
              'message',
              _connection,
            ),
          ),
        );
      });

      test('on load is a connection message', () async {
        await expectLater(
          _repository(entry.value).load(id: 'p1'),
          throwsA(isA<CoachProposalException>()),
        );
      });
    });
  }

  test('55000 says the change can no longer be applied', () async {
    await expectLater(
      _repository(
        (request) async => _error(request, 400, '55000'),
      ).respond('p1', CoachProposalAction.approve),
      throwsA(
        isA<CoachProposalException>().having(
          (e) => e.message,
          'message',
          contains('can no longer be applied'),
        ),
      ),
    );
  });
}
