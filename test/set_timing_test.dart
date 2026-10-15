import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/train/rest_timer.dart';
import 'package:tracend/features/train/set_timing.dart';
import 'package:tracend/features/train/workout_draft.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 15, 9);
  const timingKeys = [
    'started_at',
    'completed_at',
    'rest_before_seconds',
    'rir',
    'timing_source',
  ];
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  group('restTakenSeconds', () {
    test('counts from the latest end at or before the start', () {
      expect(restTakenSeconds(at(200), [at(10), at(110), at(300)]), 90);
      expect(restTakenSeconds(at(110), [at(110)]), 0);
    });

    test('is unknown without a start, an earlier end, or past an hour', () {
      expect(restTakenSeconds(null, [at(0)]), isNull);
      expect(restTakenSeconds(at(10), const []), isNull);
      expect(restTakenSeconds(at(10), [at(20)]), isNull);
      expect(restTakenSeconds(at(3600), [at(0)]), 3600);
      expect(restTakenSeconds(at(3601), [at(0)]), isNull);
    });
  });

  group('SetTimingRecorder', () {
    late SetTimingRecorder timing;
    late WorkoutSetDraft first;
    late WorkoutSetDraft second;

    setUp(() {
      timing = SetTimingRecorder();
      first = WorkoutSetDraft();
      second = WorkoutSetDraft();
    });

    void tick(WorkoutSetDraft set, DateTime now, {bool resting = false}) {
      set.completed = true;
      timing.completed(
        set,
        now: now,
        resting: resting,
        otherEnds: [
          for (final other in [first, second])
            if (!identical(other, set) && other.completedAt != null)
              other.completedAt!,
        ],
      );
    }

    test('a first set ticked untouched has an end but no start', () {
      tick(first, at(40));
      expect(first.startedAt, isNull);
      expect(first.completedAt, at(40));
      expect(first.restBeforeSeconds, isNull);
      expect(first.timingSource, SetTimingSource.app);
    });

    test('a first edit outside a rest starts the set', () {
      expect(timing.touched(first, now: at(5), resting: false), at(5));
      expect(timing.touched(first, now: at(9), resting: false), isNull);
      tick(first, at(40));
      expect(first.startedAt, at(5));
    });

    test('the end of the rest starts the next set; rest is end to start', () {
      tick(first, at(40));
      timing
        ..restStarted()
        ..restEnded(at(130));
      tick(second, at(170));
      expect(second.startedAt, at(130));
      expect(second.completedAt, at(170));
      expect(second.restBeforeSeconds, 90);
    });

    test('editing during a rest is getting ready, not starting', () {
      tick(first, at(40));
      timing.restStarted();
      expect(timing.touched(second, now: at(60), resting: true), isNull);
      timing.restEnded(at(130));
      expect(timing.touched(second, now: at(150), resting: false), at(130));
      tick(second, at(170));
      expect(second.startedAt, at(130));
    });

    test('a set ticked while its rest still runs has no start or rest', () {
      tick(first, at(40));
      timing.restStarted();
      tick(second, at(100), resting: true);
      expect(second.startedAt, isNull);
      expect(second.restBeforeSeconds, isNull);
      expect(second.completedAt, at(100));
    });

    test('a new rest drops the end of an earlier one', () {
      timing
        ..restEnded(at(10))
        ..restStarted();
      tick(first, at(40));
      expect(first.startedAt, isNull);
    });

    test('a start after the tick (the clock moved back) is dropped', () {
      timing.touched(first, now: at(100), resting: false);
      tick(first, at(50));
      expect(first.startedAt, isNull);
      expect(first.completedAt, at(50));
    });
  });

  group('across app backgrounding', () {
    test('a rest that ran out in the pocket ended at its stored end', () {
      // Set 1 is ticked and a 90 s rest starts; the app is suspended and the
      // athlete comes back four minutes later. The draft still holds the
      // timer, so the rest ended at 90 s, however late the app notices.
      final timing = SetTimingRecorder();
      final first = WorkoutSetDraft(completed: true);
      timing.completed(first, now: at(40), resting: false, otherEnds: []);
      timing.restStarted();
      final stored = jsonDecode(
        jsonEncode(RestTimer.start(90, now: at(40)).toJson()),
      );

      final resumedAt = at(40 + 240);
      final timer = RestTimer.fromJson(stored)!;
      expect(timer.isExpired(resumedAt), isTrue);
      timing.restEnded(timer.endsAt);

      final second = WorkoutSetDraft(completed: true);
      timing.completed(
        second,
        now: at(40 + 270),
        resting: false,
        otherEnds: [first.completedAt!],
      );
      expect(second.startedAt, at(130));
      expect(second.restBeforeSeconds, 90);
      expect(second.completedAt, at(310));
    });

    test('a waiting start survives a relaunch through the draft', () {
      final timing = SetTimingRecorder()..restEnded(at(130));
      final draft =
          jsonDecode(
                jsonEncode({
                  SetTimingRecorder.draftKey: timing.pendingStart!
                      .toUtc()
                      .toIso8601String(),
                }),
              )
              as Map<String, dynamic>;
      final restored = SetTimingRecorder()
        ..pendingStart = DateTime.tryParse(
          draft[SetTimingRecorder.draftKey] as String,
        );
      final set = WorkoutSetDraft(completed: true);
      restored.completed(set, now: at(150), resting: false, otherEnds: []);
      expect(set.startedAt, at(130));
    });
  });

  group('WorkoutSetDraft timing', () {
    test('reads the server set and writes it back', () {
      final set = WorkoutSetDraft.fromMap({
        'number': 2,
        'repetitions': 7,
        'load_kg': 60.0,
        'rpe': 9.0,
        'completed': true,
        'started_at': '2026-10-15T09:02:10+00:00',
        'completed_at': '2026-10-15T09:02:50.5+00:00',
        'rest_before_seconds': 90,
        'rir': 1,
        'timing_source': 'watch',
      });
      expect(set.startedAt, DateTime.utc(2026, 10, 15, 9, 2, 10));
      expect(set.completedAt, DateTime.utc(2026, 10, 15, 9, 2, 50, 500));
      expect(set.restBeforeSeconds, 90);
      expect(set.rir, 1);
      expect(set.timingSource, SetTimingSource.watch);
      expect(set.toMap(), {
        'load_kg': '60',
        'repetitions': '7',
        'rpe': '9',
        'completed': true,
        'started_at': '2026-10-15T09:02:10.000Z',
        'rest_before_seconds': 90,
        'completed_at': '2026-10-15T09:02:50.500Z',
        'rir': 1,
        'timing_source': 'watch',
      });
    });

    test('an older set without timing reads as unknown and clears nothing', () {
      final set = WorkoutSetDraft.fromMap({
        'repetitions': 8,
        'completed': true,
        'rir': 9,
        'rest_before_seconds': -4,
        'timing_source': 'phone',
      });
      expect(set.startedAt, isNull);
      expect(set.rir, isNull);
      expect(set.restBeforeSeconds, isNull);
      expect(set.timingSource, isNull);
      for (final key in timingKeys) {
        expect(set.toMap().containsKey(key), isFalse, reason: key);
      }
    });

    test('a set from a draft without timing keys leaves the server alone', () {
      final set = WorkoutSetDraft.fromMap({
        'load_kg': '60',
        'repetitions': '8',
        'rpe': '8',
        'completed': true,
      });
      for (final sent in [set.toMap(), set.toMap(notBefore: at(0))]) {
        for (final key in timingKeys) {
          expect(sent.containsKey(key), isFalse, reason: key);
        }
        expect(sent['rpe'], '8');
      }
    });

    test('logging on an older set sends only what it changed', () {
      final reps = WorkoutSetDraft.fromMap({'completed': true})..setRir(2);
      expect(reps.toMap(), {
        'load_kg': '',
        'repetitions': '',
        'rpe': '8',
        'completed': true,
        'rir': 2,
      });
      final cleared = WorkoutSetDraft.fromMap({'completed': true})
        ..setRir(null);
      expect(cleared.toMap()['rir'], isNull);
      expect(cleared.toMap().containsKey('rir'), isTrue);

      final ticked = WorkoutSetDraft.fromMap({'completed': false})
        ..completed = true;
      SetTimingRecorder().completed(
        ticked,
        now: at(60),
        resting: false,
        otherEnds: [at(0)],
      );
      final sent = ticked.toMap();
      expect(sent['completed_at'], at(60).toIso8601String());
      expect(sent.containsKey('rest_before_seconds'), isTrue);
      expect(sent['timing_source'], 'app');
      expect(sent.containsKey('started_at'), isFalse);
      expect(sent.containsKey('rir'), isFalse);
    });

    test('un-ticking an older set clears every timing key', () {
      final set = WorkoutSetDraft.fromMap({'rpe': '8', 'completed': true})
        ..completed = false
        ..startedAt = null
        ..completedAt = null
        ..restBeforeSeconds = null
        ..timingSource = null
        ..setRir(null);
      final sent = set.toMap();
      for (final key in timingKeys) {
        expect(sent.containsKey(key), isTrue, reason: key);
        expect(sent[key], isNull, reason: key);
      }
      expect(sent['rpe'], '');
    });

    test('a draft saved by this build keeps its keys, nulls included', () {
      Map<String, dynamic> roundTrip(WorkoutSetDraft set) =>
          WorkoutSetDraft.fromMap(
            jsonDecode(jsonEncode(set.toMap())) as Map<String, dynamic>,
          ).toMap();

      final fresh = roundTrip(WorkoutSetDraft(completed: true));
      for (final key in timingKeys) {
        expect(fresh.containsKey(key), isTrue, reason: key);
        expect(fresh[key], isNull, reason: key);
      }

      final timed = WorkoutSetDraft(
        completed: true,
        startedAt: at(10),
        completedAt: at(50),
        restBeforeSeconds: 40,
        timingSource: SetTimingSource.app,
      )..setRir(1);
      expect(roundTrip(timed), timed.toMap());

      final older = WorkoutSetDraft.fromMap({'completed': true})..setRir(3);
      final again = roundTrip(older);
      expect(again['rir'], 3);
      expect(again.containsKey('started_at'), isFalse);
      expect(again.containsKey('timing_source'), isFalse);
    });

    test('an older RPE reads as the reps left it meant', () {
      int? shown(String rpe) => WorkoutSetDraft(rpe: rpe).shownRir;
      expect(shown('8'), 2);
      expect(shown('8.5'), 2);
      expect(shown('10'), 0);
      expect(shown('5'), 5);
      expect(shown('3'), 5);
      expect(shown(''), isNull);
      final answered = WorkoutSetDraft(rpe: '8')..setRir(4);
      expect(answered.shownRir, 4);
      // Shown only: an older set sends no reps left it was not given.
      final older = WorkoutSetDraft.fromMap({'rpe': 7.0, 'completed': true});
      expect(older.shownRir, 3);
      expect(older.rir, isNull);
      expect(older.toMap().containsKey('rir'), isFalse);
    });

    test('reps left writes the effort it meant on the 1–10 picker', () {
      final set = WorkoutSetDraft()..setRir(2);
      expect((set.rir, set.rpe), (2, '8'));
      set.setRir(0);
      expect(set.rpe, '10');
      set.setRir(5);
      expect(set.rpe, '5');
      set.setRir(null);
      expect((set.rir, set.rpe), (null, ''));
    });

    test('times before the server session began stay on the phone', () {
      final set = WorkoutSetDraft(
        completed: true,
        startedAt: at(10),
        completedAt: at(60),
        restBeforeSeconds: 70,
        timingSource: SetTimingSource.app,
      );
      final early = set.toMap(notBefore: at(30));
      expect(early.containsKey('started_at'), isFalse);
      expect(early.containsKey('rest_before_seconds'), isFalse);
      expect(early['completed_at'], at(60).toIso8601String());
      final late = set.toMap(notBefore: at(90));
      expect(late.containsKey('completed_at'), isFalse);
      expect(set.toMap(notBefore: at(10))['started_at'], isNotNull);
    });
  });
}
