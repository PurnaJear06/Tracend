import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/feedback/feedback_rating.dart';

const _decision = '11111111-1111-4111-8111-111111111111';
const _reply = '22222222-2222-4222-8222-222222222222';
const _unrated = '33333333-3333-4333-8333-333333333333';

class _Server {
  final requests = <http.Request>[];

  late final client = SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient((request) async {
      requests.add(request);
      http.Response json(Object value) => http.Response(
        jsonEncode(value),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
      switch (request.url.path) {
        case '/rest/v1/feedback_ratings':
          return json([
            {
              'subject_type': 'daily_decision',
              'subject_id': _decision,
              'rating': 'unclear',
            },
            {
              'subject_type': 'coach_reply',
              'subject_id': _reply,
              'rating': 'unsafe',
            },
          ]);
        case '/rest/v1/rpc/submit_feedback_rating_v1':
          return json({'schema_version': '1.0'});
      }
      return http.Response('not found', 404, request: request);
    }),
  );
}

void main() {
  test('ratings asked for together are read with one query', () async {
    final server = _Server();
    final repository = SupabaseCoachRepository(server.client);

    final ratings = await Future.wait([
      repository.loadRating(FeedbackSubject.dailyDecision, _decision),
      repository.loadRating(FeedbackSubject.coachReply, _reply),
      repository.loadRating(FeedbackSubject.coachReply, _unrated),
    ]);

    expect(ratings, [FeedbackRating.unclear, FeedbackRating.unsafe, null]);
    final reads = server.requests.where(
      (request) => request.url.path == '/rest/v1/feedback_ratings',
    );
    expect(reads, hasLength(1));
    expect(
      reads.single.url.queryParameters['subject_id'],
      'in.("$_decision","$_reply","$_unrated")',
    );
  });

  test('a rating read once is not read again', () async {
    final server = _Server();
    final repository = SupabaseCoachRepository(server.client);

    await Future.wait([
      repository.loadRating(FeedbackSubject.dailyDecision, _decision),
      repository.loadRating(FeedbackSubject.coachReply, _unrated),
    ]);
    final again = await Future.wait([
      repository.loadRating(FeedbackSubject.dailyDecision, _decision),
      repository.loadRating(FeedbackSubject.coachReply, _unrated),
    ]);

    expect(again, [FeedbackRating.unclear, null]);
    expect(
      server.requests.where(
        (request) => request.url.path == '/rest/v1/feedback_ratings',
      ),
      hasLength(1),
      reason: 'even a subject with no rating is remembered',
    );
  });

  test('a rating just given is what is read next', () async {
    final server = _Server();
    final repository = SupabaseCoachRepository(server.client);

    await repository.rate(
      FeedbackSubject.coachReply,
      _unrated,
      FeedbackRating.useful,
    );

    expect(
      await repository.loadRating(FeedbackSubject.coachReply, _unrated),
      FeedbackRating.useful,
    );
    expect(
      server.requests.where(
        (request) => request.url.path == '/rest/v1/feedback_ratings',
      ),
      isEmpty,
    );
  });

  test('a rating is saved through the rating function only', () async {
    final server = _Server();

    await SupabaseCoachRepository(
      server.client,
    ).rate(FeedbackSubject.coachReply, _reply, FeedbackRating.incorrect);

    expect(server.requests, hasLength(1));
    expect(
      server.requests.single.url.path,
      '/rest/v1/rpc/submit_feedback_rating_v1',
    );
    expect(jsonDecode(server.requests.single.body), {
      'subject_type': 'coach_reply',
      'subject_id': _reply,
      'rating': 'incorrect',
    });
  });

  test('the four ratings are the stored values', () {
    expect(FeedbackRating.values.map((rating) => rating.name), [
      'useful',
      'unclear',
      'incorrect',
      'unsafe',
    ]);
    expect(FeedbackSubject.values.map((subject) => subject.wire), [
      'daily_decision',
      'coach_reply',
    ]);
  });
}
