import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/coach/coach_repository.dart';
import 'package:tracend/features/nutrition/nutrition_repository.dart';
import 'package:tracend/shared/shared_reads.dart';

/// A Supabase server that holds every request until the test answers it, so a
/// test decides which reads overlap. Requests are counted by path.
class _Server {
  final requests = <String>[];
  final _pending = <Completer<http.Response>>[];

  int count(String path) => requests.where((r) => r == path).length;

  /// Answers every held request with an empty list (or `{}` for RPCs).
  void answerAll() {
    for (final waiting in _pending) {
      if (!waiting.isCompleted) waiting.complete(http.Response('', 200));
    }
    _pending.clear();
  }

  late final client = SupabaseClient(
    'https://tracend-test.supabase.co',
    'publishable-test',
    httpClient: MockClient((request) {
      final path = request.url.path.replaceFirst('/rest/v1/', '');
      requests.add(path);
      final held = Completer<http.Response>();
      _pending.add(held);
      return held.future.then(
        (_) => http.Response(
          path.startsWith('rpc/') ? '{"items":[]}' : '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  group('SharedReads', () {
    test('a second caller joins the read in flight', () async {
      final reads = SharedReads();
      final gate = Completer<int>();
      var started = 0;
      Future<int> read() {
        started++;
        return gate.future;
      }

      final first = reads.join('k', read);
      final second = reads.join('k', read);
      expect(started, 1);
      gate.complete(7);
      expect(await Future.wait([first, second]), [7, 7]);
    });

    test('a finished read is never reused', () async {
      final reads = SharedReads();
      var started = 0;
      Future<int> read() async => ++started;

      expect(await reads.join('k', read), 1);
      expect(await reads.join('k', read), 2);
    });

    test('another key is its own read', () async {
      final reads = SharedReads();
      var started = 0;
      Future<int> read() async => ++started;

      await Future.wait([reads.join('a', read), reads.join('b', read)]);
      expect(started, 2);
    });

    test('a failed read is shared, then forgotten', () async {
      final reads = SharedReads();
      var started = 0;
      Future<int> read() async {
        started++;
        throw StateError('offline');
      }

      final first = reads.join('k', read);
      final second = reads.join('k', read);
      expect(started, 1);
      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      await expectLater(reads.join('k', read), throwsStateError);
      expect(started, 2);
    });

    test('a write ends the sharing of reads that began before it', () async {
      final reads = SharedReads();
      final gate = Completer<int>();
      var started = 0;
      Future<int> read() {
        started++;
        return started == 1 ? gate.future : Future.value(started);
      }

      final before = reads.join('k', read);
      await reads.afterWrite(() async {});
      expect(await reads.join('k', read), 2);
      gate.complete(1);
      expect(await before, 1);
    });

    test('a failed write still ends the sharing', () async {
      final reads = SharedReads();
      final gate = Completer<int>();
      var started = 0;
      Future<int> read() {
        started++;
        return gate.future;
      }

      unawaited(reads.join('k', read));
      await expectLater(
        reads.afterWrite<void>(() async => throw StateError('rejected')),
        throwsStateError,
      );
      unawaited(reads.join('k', read));
      expect(started, 2);
      gate.complete(0);
    });
  });

  group('SupabaseCoachRepository', () {
    test('Today, Train and Nutrition share one latest-decision read', () async {
      final server = _Server();
      final coach = SupabaseCoachRepository(server.client);

      final reads = [
        coach.loadLatest(),
        coach.loadLatest(),
        coach.loadLatest(),
      ];
      await _turn();
      expect(server.count('coach_decisions'), 1);
      server.answerAll();
      expect(await Future.wait(reads), [null, null, null]);

      final later = coach.loadLatest();
      await _turn();
      expect(server.count('coach_decisions'), 2, reason: 'no cache');
      server.answerAll();
      await later;
    });
  });

  group('SupabaseNutritionRepository', () {
    test('Today and Nutrition share targets, meals and schedule', () async {
      final server = _Server();
      final nutrition = SupabaseNutritionRepository(server.client);
      final day = DateTime(2026, 10, 17);

      final reads = <Future<Object?>>[
        for (var caller = 0; caller < 2; caller++) ...[
          nutrition.loadTargets(),
          nutrition.loadMeals(day),
          nutrition.loadSchedule(day),
        ],
      ];
      await _turn();
      expect(server.count('nutrition_target_sets'), 1);
      expect(server.count('meals'), 1);
      expect(server.count('rpc/get_my_nutrition_schedule'), 1);
      server.answerAll();
      await Future.wait(reads);
    });

    test('another day is its own read', () async {
      final server = _Server();
      final nutrition = SupabaseNutritionRepository(server.client);

      final reads = [
        nutrition.loadMeals(DateTime(2026, 10, 17)),
        nutrition.loadMeals(DateTime(2026, 10, 16)),
      ];
      await _turn();
      expect(server.count('meals'), 2);
      server.answerAll();
      await Future.wait(reads);
    });

    test('a read after a write is never served from before it', () async {
      final server = _Server();
      final nutrition = SupabaseNutritionRepository(server.client);
      final day = DateTime(2026, 10, 17);

      final stale = nutrition.loadMeals(day);
      await _turn();
      final deletion = nutrition.deleteMeal('meal-1');
      await _turn();
      server.answerAll();
      await Future.wait([stale, deletion]);

      final fresh = nutrition.loadMeals(day);
      await _turn();
      expect(server.count('meals'), 2);
      server.answerAll();
      await fresh;
    });
  });
}
