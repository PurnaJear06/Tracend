import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/app_lifecycle.dart';

void main() {
  group('LoadStamp', () {
    late DateTime now;
    late LoadStamp stamp;

    setUp(() {
      now = DateTime(2026, 10, 2, 23, 55);
      stamp = LoadStamp(() => now);
    });

    test('nothing loaded is stale', () {
      expect(stamp.isEmpty, isTrue);
      expect(stamp.isStale(), isTrue);
    });

    test('stays fresh for ten minutes of the same day', () {
      stamp.mark();
      now = now.add(const Duration(minutes: 4));
      expect(stamp.isStale(), isFalse);
      expect(stamp.day, '2026-10-02');
    });

    test('goes stale after ten minutes, or its own limit', () {
      now = DateTime(2026, 10, 2, 9);
      stamp.mark();
      now = DateTime(2026, 10, 2, 9, 11);
      expect(stamp.isStale(), isTrue);
      expect(stamp.isStale(within: const Duration(minutes: 30)), isFalse);
    });

    test('a load from another day is stale at once', () {
      stamp.mark();
      now = DateTime(2026, 10, 3, 0, 1);
      expect(stamp.isStale(), isTrue);
    });

    test('a load marked for a day is compared with that day', () {
      stamp.mark(day: '2026-10-01');
      expect(stamp.isStale(today: '2026-10-01'), isFalse);
      expect(stamp.isStale(today: '2026-10-02'), isTrue);
    });
  });

  test('dates are keyed by the phone\'s calendar day', () {
    expect(localDayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    expect(
      isSameLocalDay(DateTime(2026, 1, 5, 1), DateTime(2026, 1, 5, 23)),
      isTrue,
    );
    expect(isSameLocalDay(DateTime(2026, 1, 5), DateTime(2026, 1, 6)), isFalse);
  });

  testWidgets('ResumeObserver calls back on resume only, and stops on detach', (
    tester,
  ) async {
    var resumes = 0;
    final observer = ResumeObserver(() => resumes++)..attach();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(resumes, 1);
    observer.detach();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(resumes, 1);
  });

  testWidgets('ResumeObserver waits for the work the gate holds', (
    tester,
  ) async {
    var resumes = 0;
    final observer = ResumeObserver(() => resumes++)..attach();
    addTearDown(observer.detach);
    final sync = Completer<void>();
    ResumeGate.hold(sync.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(resumes, 0);

    sync.complete();
    await tester.pump();
    expect(resumes, 1);
  });

  testWidgets('a sync that never ends holds a refresh no longer than the '
      'timeout', (tester) async {
    var resumes = 0;
    final observer = ResumeObserver(() => resumes++)..attach();
    addTearDown(observer.detach);
    ResumeGate.hold(Completer<void>().future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(ResumeGate.timeout - const Duration(seconds: 1));
    expect(resumes, 0);

    await tester.pump(const Duration(seconds: 2));
    expect(resumes, 1);
  });

  testWidgets('a failed sync still lets the refresh run, and a detached '
      'observer is not called', (tester) async {
    var resumes = 0;
    final observer = ResumeObserver(() => resumes++)..attach();
    final failing = Completer<void>();
    ResumeGate.hold(failing.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    observer.detach();
    failing.completeError(StateError('offline'));
    await tester.pump();
    expect(resumes, 0);

    final second = ResumeObserver(() => resumes++)..attach();
    addTearDown(second.detach);
    final other = Completer<void>();
    ResumeGate.hold(other.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    other.completeError(StateError('offline'));
    await tester.pump();
    expect(resumes, 1);
  });

  group('a sync that finishes after the timeout', () {
    testWidgets('refreshes the attached observers a second time', (
      tester,
    ) async {
      var resumes = 0;
      final observer = ResumeObserver(() => resumes++)..attach();
      addTearDown(observer.detach);
      final detached = ResumeObserver(() => resumes += 100)..attach();
      final sync = Completer<void>();
      ResumeGate.hold(sync.future);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      detached.detach();
      await tester.pump(ResumeGate.timeout + const Duration(seconds: 1));
      expect(resumes, 1, reason: 'the first refresh, with the old zone');

      sync.complete();
      await tester.pump();
      expect(resumes, 2, reason: 'again, now the zone is stored');
    });

    testWidgets('does not refresh again when it failed, or finished in time', (
      tester,
    ) async {
      var resumes = 0;
      final observer = ResumeObserver(() => resumes++)..attach();
      addTearDown(observer.detach);

      final failing = Completer<void>();
      ResumeGate.hold(failing.future);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(ResumeGate.timeout + const Duration(seconds: 1));
      failing.completeError(StateError('offline'));
      await tester.pump();
      expect(resumes, 1);

      final prompt = Completer<void>();
      ResumeGate.hold(prompt.future);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      prompt.complete();
      await tester.pump();
      expect(resumes, 2, reason: 'one refresh, after the sync');
    });
  });
}
