import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/today/daily_brief_repository.dart';

class _CountingRepository implements DailyBriefRepository {
  final calls = <DateTime>[];
  final pending = <Completer<DailyBrief>>[];

  @override
  Future<DailyBrief> load(DateTime date) {
    calls.add(date);
    final completer = Completer<DailyBrief>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  group('SharedDailyBriefRepository', () {
    test('tabs loading the same day at once share one request', () async {
      final inner = _CountingRepository();
      final shared = SharedDailyBriefRepository(inner);
      final morning = DateTime(2026, 10, 4, 9);

      final today = shared.load(morning);
      final train = shared.load(DateTime(2026, 10, 4, 9, 0, 1));
      final progress = shared.load(morning);
      expect(inner.calls, hasLength(1));

      inner.pending.single.complete(DailyBrief(localDate: '2026-10-04'));
      final briefs = await Future.wait([today, train, progress]);
      expect(briefs.map((brief) => brief.localDate).toSet(), {'2026-10-04'});
    });

    test('a finished load is never reused', () async {
      final inner = _CountingRepository();
      final shared = SharedDailyBriefRepository(inner);
      final first = shared.load(DateTime(2026, 10, 4));
      inner.pending.single.complete(DailyBrief(localDate: '2026-10-04'));
      await first;

      unawaited(shared.load(DateTime(2026, 10, 4)));
      expect(inner.calls, hasLength(2));
    });

    test('another day is its own request', () {
      final inner = _CountingRepository();
      final shared = SharedDailyBriefRepository(inner);
      unawaited(shared.load(DateTime(2026, 10, 4)));
      unawaited(shared.load(DateTime(2026, 10, 3)));
      expect(inner.calls, hasLength(2));
    });

    test('a failure reaches every caller and the next load retries', () async {
      final inner = _CountingRepository();
      final shared = SharedDailyBriefRepository(inner);
      final a = shared.load(DateTime(2026, 10, 4));
      final b = shared.load(DateTime(2026, 10, 4));
      inner.pending.single.completeError(StateError('statement timeout'));
      await expectLater(a, throwsStateError);
      await expectLater(b, throwsStateError);

      unawaited(shared.load(DateTime(2026, 10, 4)));
      expect(inner.calls, hasLength(2));
    });
  });
}
