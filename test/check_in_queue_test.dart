import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/today/check_in_queue.dart';

const _payload = {
  'sleep_quality': 4,
  'energy': 3,
  'soreness': 2,
  'hunger': 3,
  'mood': 4,
  'pain_severity': 0,
  'available_to_train': true,
  'note': 'Felt strong',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CheckInQueue> buildQueue({String? userId}) async {
    final preferences = await SharedPreferences.getInstance();
    return CheckInQueue(preferences, userId: userId);
  }

  Future<Map<String, dynamic>> stored({String? userId}) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(
      userId == null
          ? CheckInQueue.queueStorageKey
          : CheckInQueue.queueStorageKeyFor(userId),
    );
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// A sender that records what it was given and answers with [answer].
  CheckInSend recording(
    List<String> days, {
    Future<bool> Function(String day)? answer,
  }) {
    return (localDate, timezone, key, payload) async {
      days.add(localDate);
      return answer == null ? true : answer(localDate);
    };
  }

  test(
    'enqueue persists the envelope with the answer day, not today',
    () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      final key = await queue.enqueue(
        payload: _payload,
        localDate: '2026-09-05',
        timezone: 'Asia/Kolkata',
      );
      final envelope = (await stored())['2026-09-05'] as Map<String, dynamic>;
      expect(envelope['idempotency_key'], key);
      expect(envelope['local_date'], '2026-09-05');
      expect(envelope['timezone'], 'Asia/Kolkata');
      expect((envelope['payload'] as Map)['sleep_quality'], 4);
    },
  );

  test('two days wait side by side, and answering a day again replaces '
      'that day only', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    await queue.enqueue(
      payload: _payload,
      localDate: '2026-10-26',
      timezone: 'Asia/Kolkata',
    );
    final tuesdayFirst = await queue.enqueue(
      payload: _payload,
      localDate: '2026-10-27',
      timezone: 'Asia/Kolkata',
    );
    final tuesdayAgain = await queue.enqueue(
      payload: _payload,
      localDate: '2026-10-27',
      timezone: 'Asia/Kolkata',
    );
    expect(tuesdayAgain, isNot(tuesdayFirst));
    expect(await queue.pendingDays(), ['2026-10-26', '2026-10-27']);
    final tuesday = (await stored())['2026-10-27'] as Map<String, dynamic>;
    expect(tuesday['idempotency_key'], tuesdayAgain);
  });

  test('replay delivers every pending day as recorded, oldest first, and '
      'clears them', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    await queue.enqueue(
      payload: _payload,
      localDate: '2026-10-27',
      timezone: 'GMT+5:30',
    );
    await queue.enqueue(
      payload: _payload,
      localDate: '2026-10-26',
      timezone: 'GMT+5:30',
    );
    final days = <String>[];
    final zones = <String>[];
    final replay = await queue.replay((date, zone, key, payload) async {
      days.add(date);
      zones.add(zone);
      return true;
    });
    // The answer day's date is sent as recorded, never re-dated to today.
    expect(days, ['2026-10-26', '2026-10-27']);
    expect(zones, everyElement('GMT+5:30'));
    expect(replay.delivered, ['2026-10-26', '2026-10-27']);
    expect(replay.deliveredAny, isTrue);
    expect(await stored(), isEmpty);
  });

  test(
    'replay retains an envelope when delivery fails and stops there',
    () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      for (final day in ['2026-10-26', '2026-10-27']) {
        await queue.enqueue(
          payload: _payload,
          localDate: day,
          timezone: 'Asia/Kolkata',
        );
      }
      final days = <String>[];
      final replay = await queue.replay(
        recording(days, answer: (_) async => false),
      );
      expect(days, ['2026-10-26']);
      expect(replay.retained, ['2026-10-26', '2026-10-27']);
      expect(replay.deliveredAny, isFalse);
      expect(await queue.pendingDays(), ['2026-10-26', '2026-10-27']);
    },
  );

  test(
    'replay retains the envelope when send throws a transient error',
    () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: _payload,
        localDate: '2026-09-05',
        timezone: 'Asia/Kolkata',
      );
      final replay = await queue.replay(
        (localDate, timezone, key, payload) async => throw Exception('offline'),
      );
      expect(replay.retained, ['2026-09-05']);
      expect(replay.refused, isEmpty);
      expect(await queue.pendingDays(), ['2026-09-05']);
    },
  );

  test('a lapsed sign-in or a server error is not a final refusal', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    await queue.enqueue(
      payload: _payload,
      localDate: '2026-09-05',
      timezone: 'Asia/Kolkata',
    );
    for (final code in ['42501', '57014', null]) {
      final replay = await queue.replay(
        (a, b, c, d) async =>
            throw PostgrestException(message: 'nope', code: code),
      );
      expect(replay.refused, isEmpty, reason: '$code');
      expect(replay.retained, ['2026-09-05'], reason: '$code');
    }
  });

  test('a final refusal drops that day, reports it, and the rest still '
      'go through', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    for (final day in ['2026-10-25', '2026-10-27']) {
      await queue.enqueue(
        payload: _payload,
        localDate: day,
        timezone: 'Asia/Kolkata',
      );
    }
    final days = <String>[];
    final replay = await queue.replay((date, zone, key, payload) async {
      days.add(date);
      if (date == '2026-10-25') {
        throw PostgrestException(
          message: 'a pain check is for today or yesterday',
          code: '22023',
        );
      }
      return true;
    });
    expect(days, ['2026-10-25', '2026-10-27']);
    expect(replay.refused.single.localDate, '2026-10-25');
    expect(replay.refused.single.error.code, '22023');
    expect(replay.delivered, ['2026-10-27']);
    expect(await stored(), isEmpty);
  });

  test('replay is a no-op when nothing is pending', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    final days = <String>[];
    final replay = await queue.replay(recording(days));
    expect(days, isEmpty);
    expect(replay.deliveredAny, isFalse);
    expect(replay.retained, isEmpty);
  });

  test('replay discards an envelope from the first format, without date '
      'fields', () async {
    SharedPreferences.setMockInitialValues({
      CheckInQueue.singleSlotKey: jsonEncode({
        'idempotency_key': '7e7d8f27-6d93-4ef7-a331-e0332b16850d',
        'payload': {'energy': 3},
      }),
    });
    final queue = await buildQueue();
    final days = <String>[];
    await queue.replay(recording(days));
    expect(days, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(CheckInQueue.singleSlotKey), isNull);
    expect(await stored(), isEmpty);
  });

  test('clearDelivered removes the envelope with that key, but not a newer '
      'answer for the same day', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    final first = await queue.enqueue(
      payload: _payload,
      localDate: '2026-09-06',
      timezone: 'Asia/Kolkata',
    );
    final second = await queue.enqueue(
      payload: _payload,
      localDate: '2026-09-06',
      timezone: 'Asia/Kolkata',
    );
    await queue.clearDelivered(first);
    expect(await queue.pendingDays(), ['2026-09-06']);
    await queue.clearDelivered(second);
    expect(await queue.pendingDays(), isEmpty);
  });

  group('the single slot earlier builds kept', () {
    const athleteA = '11111111-1111-4111-8111-111111111111';
    const athleteB = '22222222-2222-4222-8222-222222222222';

    String envelope(String day, String key) => jsonEncode({
      'idempotency_key': key,
      'local_date': day,
      'timezone': 'Asia/Kolkata',
      'payload': {'energy': 2},
    });

    test(
      'moves into the keyed list, so nothing queued today is lost',
      () async {
        SharedPreferences.setMockInitialValues({
          CheckInQueue.singleSlotKeyFor(athleteA): envelope(
            '2026-10-30',
            'old-key',
          ),
        });
        final queue = await buildQueue(userId: athleteA);
        // Today's own answer arrives next to the migrated one.
        await queue.enqueue(
          payload: _payload,
          localDate: '2026-10-31',
          timezone: 'Asia/Kolkata',
        );
        expect(await queue.pendingDays(), ['2026-10-30', '2026-10-31']);
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getString(CheckInQueue.singleSlotKeyFor(athleteA)),
          isNull,
        );
        final migrated =
            (await stored(userId: athleteA))['2026-10-30']
                as Map<String, dynamic>;
        expect(migrated['idempotency_key'], 'old-key');
      },
    );

    test('is replayed with its recorded key', () async {
      SharedPreferences.setMockInitialValues({
        CheckInQueue.singleSlotKeyFor(athleteA): envelope(
          '2026-10-30',
          'old-key',
        ),
      });
      final queue = await buildQueue(userId: athleteA);
      String? sentKey;
      final replay = await queue.replay((date, zone, key, payload) async {
        sentKey = key;
        return true;
      });
      expect(sentKey, 'old-key');
      expect(replay.delivered, ['2026-10-30']);
    });

    test('the device-wide slot of the oldest builds goes to the first '
        'athlete only', () async {
      SharedPreferences.setMockInitialValues({
        CheckInQueue.singleSlotKey: envelope('2026-10-01', 'legacy-key'),
      });
      var sent = 0;
      Future<void> replayAs(String userId) async {
        final queue = await buildQueue(userId: userId);
        await queue.replay((a, b, c, d) async {
          sent++;
          return true;
        });
      }

      await replayAs(athleteA);
      expect(sent, 1);
      expect(
        (await SharedPreferences.getInstance()).getString(
          CheckInQueue.singleSlotKey,
        ),
        isNull,
      );
      await replayAs(athleteB);
      expect(sent, 1);
    });
  });

  test('one athlete\'s pending check-in is never sent for another', () async {
    const athleteA = '11111111-1111-4111-8111-111111111111';
    const athleteB = '22222222-2222-4222-8222-222222222222';
    SharedPreferences.setMockInitialValues({});
    await (await buildQueue(userId: athleteA)).enqueue(
      payload: const {'energy': 3},
      localDate: '2026-10-02',
      timezone: 'Asia/Kolkata',
    );
    Future<int> replayCount(String userId) async {
      var sent = 0;
      await (await buildQueue(userId: userId)).replay((a, b, c, d) async {
        sent++;
        return true;
      });
      return sent;
    }

    expect(await replayCount(athleteB), 0);
    expect(await replayCount(athleteA), 1);
    expect(await replayCount(athleteA), 0);
  });

  group('moving the single slot into the keyed list', () {
    const legacy = {
      'idempotency_key': 'legacy-key',
      'local_date': '2026-10-01',
      'timezone': 'Asia/Kolkata',
      'payload': {'energy': 3},
    };

    test('a write that fails keeps the old entry for the next read', () async {
      SharedPreferences.setMockInitialValues({
        CheckInQueue.singleSlotKey: jsonEncode(legacy),
      });
      final real = await SharedPreferences.getInstance();

      final failing = CheckInQueue(_FailingWrites(real));
      await failing.pendingDays();
      expect(real.getString(CheckInQueue.singleSlotKey), isNotNull);
      expect(real.getString(CheckInQueue.queueStorageKey), isNull);

      final healthy = CheckInQueue(real);
      expect(await healthy.pendingDays(), ['2026-10-01']);
      expect(real.getString(CheckInQueue.singleSlotKey), isNull);
      expect(await stored(), contains('2026-10-01'));
    });

    test(
      'an interruption after the write repeats without a duplicate',
      () async {
        SharedPreferences.setMockInitialValues({
          CheckInQueue.singleSlotKey: jsonEncode(legacy),
          CheckInQueue.queueStorageKey: jsonEncode({'2026-10-01': legacy}),
        });
        final queue = await buildQueue();
        expect(await queue.pendingDays(), ['2026-10-01']);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString(CheckInQueue.singleSlotKey), isNull);
        expect((await stored()).keys, ['2026-10-01']);
      },
    );
  });

  group('a check-in with a pain check', () {
    const withPain = {
      'sleep_quality': 3,
      'energy': 3,
      'soreness': 3,
      'hunger': 3,
      'mood': 3,
      'pain_severity': 6,
      'pain_area': 'knee',
      'pain_red_flags': <String>['locks_gives_way'],
      'available_to_train': true,
      'note': '',
    };

    Future<CheckInQueue> queued() async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: withPain,
        localDate: '2026-10-02',
        timezone: 'Asia/Kolkata',
      );
      return queue;
    }

    Future<bool> refuse(
      String date,
      String zone,
      String key,
      Map<String, dynamic> payload,
    ) async {
      throw const PostgrestException(message: 'old', code: '22023');
    }

    test('waits, with its pain keys, until it is sent', () async {
      final queue = await queued();
      expect(queue.painState, CheckInPainState.waiting);
      Map<String, dynamic>? sent;
      final replay = await queue.replay((date, zone, key, payload) async {
        sent = payload;
        return false;
      });
      expect(replay.retained, ['2026-10-02']);
      expect(sent!['pain_red_flags'], ['locks_gives_way']);
      expect(queue.painState, CheckInPainState.waiting);
    });

    test('a refusal (22023) is kept, marked, and not sent again', () async {
      final queue = await queued();
      var calls = 0;
      Future<bool> counting(
        String date,
        String zone,
        String key,
        Map<String, dynamic> payload,
      ) {
        calls++;
        return refuse(date, zone, key, payload);
      }

      final first = await queue.replay(counting);
      expect(first.fates.values, [CheckInFate.painRefused]);
      expect(first.refused, isEmpty, reason: 'told by the notice, not dropped');
      expect(queue.painState, CheckInPainState.refused);
      await queue.replay(counting);
      expect(calls, 1, reason: 'a refusal is not retried every launch');
      expect(await queue.pendingDays(), ['2026-10-02']);
    });

    test('a refusal without pain keys is dropped and reported', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: const {'energy': 3, 'pain_severity': 0},
        localDate: '2026-10-02',
        timezone: 'Asia/Kolkata',
      );
      final replay = await queue.replay(refuse);
      expect(replay.refused.single.localDate, '2026-10-02');
      expect(queue.painState, CheckInPainState.none);
      expect(await queue.pendingDays(), isEmpty);
    });

    test(
      'acknowledging sends the rest of the check-in without the pain',
      () async {
        final queue = await queued();
        await queue.replay(refuse);
        Map<String, dynamic>? sent;
        await queue.acknowledgeRefusedPain((date, zone, key, payload) async {
          sent = payload;
          return true;
        });
        expect(sent!['energy'], 3);
        expect(sent!.keys.where((key) => key.startsWith('pain_')), [
          'pain_severity',
        ]);
        expect(queue.painState, CheckInPainState.none);
        expect(await stored(), isEmpty);
      },
    );

    test(
      'acknowledging keeps the rest queued when it cannot be sent',
      () async {
        final queue = await queued();
        await queue.replay(refuse);
        await queue.acknowledgeRefusedPain((date, zone, key, payload) async {
          throw Exception('offline');
        });
        expect(queue.painState, CheckInPainState.none);
        Map<String, dynamic>? sent;
        final replay = await queue.replay((date, zone, key, payload) async {
          sent = payload;
          return true;
        });
        expect(replay.delivered, ['2026-10-02']);
        expect(sent!.containsKey('pain_area'), isFalse);
      },
    );
  });

  group('a second check-in while the first waits', () {
    const base = {
      'sleep_quality': 3,
      'energy': 3,
      'soreness': 3,
      'hunger': 3,
      'mood': 3,
      'available_to_train': true,
      'note': '',
    };

    test('does not overwrite a red flag: both go, the earlier first', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: {
          ...base,
          'pain_severity': 3,
          'pain_area': 'back',
          'pain_red_flags': ['bladder_bowel_saddle'],
        },
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      await queue.enqueue(
        payload: {...base, 'pain_severity': 0},
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      expect(queue.painState, CheckInPainState.waiting);

      final sent = <Map<String, dynamic>>[];
      final replay = await queue.replay((date, zone, key, payload) async {
        sent.add(payload);
        return true;
      });
      expect(replay.delivered, ['2026-10-24', '2026-10-24']);
      expect(sent.first['pain_red_flags'], ['bladder_bowel_saddle']);
      expect(sent.last.containsKey('pain_area'), isFalse);
      expect(queue.painState, CheckInPainState.none);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().where((k) => k.contains('check_in')),
        isEmpty,
      );
    });

    test('the later one waits while the earlier cannot be sent', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: {
          ...base,
          'pain_severity': 6,
          'pain_area': 'knee',
          'pain_red_flags': <String>[],
        },
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      await queue.enqueue(
        payload: {...base, 'pain_severity': 0},
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      final attempts = <Map<String, dynamic>>[];
      final replay = await queue.replay((date, zone, key, payload) async {
        attempts.add(payload);
        return false;
      });
      expect(replay.retained, ['2026-10-24', '2026-10-24']);
      expect(
        attempts,
        hasLength(1),
        reason: 'the later one would supersede it',
      );
      expect(attempts.single['pain_area'], 'knee');
      expect(queue.painState, CheckInPainState.waiting);
    });

    test('a check-in without a pain check is replaced as before', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      for (final energy in [1, 5]) {
        await queue.enqueue(
          payload: {...base, 'energy': energy, 'pain_severity': 0},
          localDate: '2026-10-24',
          timezone: 'Asia/Kolkata',
        );
      }
      final sent = <int>[];
      await queue.replay((date, zone, key, payload) async {
        sent.add(payload['energy'] as int);
        return true;
      });
      expect(sent, [5]);
    });

    test('an earlier refusal is told and its check-in still goes', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: {
          ...base,
          'energy': 1,
          'pain_severity': 6,
          'pain_area': 'knee',
          'pain_red_flags': <String>[],
        },
        localDate: '2026-10-20',
        timezone: 'Asia/Kolkata',
      );
      await queue.enqueue(
        payload: {...base, 'pain_severity': 0},
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      final sent = <(String, Map<String, dynamic>)>[];
      Future<bool> server(
        String date,
        String zone,
        String key,
        Map<String, dynamic> payload,
      ) async {
        if (payload.containsKey('pain_area')) {
          throw const PostgrestException(
            message: 'a pain check is for today or yesterday',
            code: '22023',
          );
        }
        sent.add((date, payload));
        return true;
      }

      final replay = await queue.replay(server);
      expect(replay.delivered, ['2026-10-24']);
      expect(sent.map((e) => e.$1), ['2026-10-24']);
      expect(queue.painState, CheckInPainState.refused);
      expect(queue.painRefusedTooOld, isTrue);

      await queue.acknowledgeRefusedPain(server);
      expect(queue.painState, CheckInPainState.none);
      expect(sent.map((e) => e.$1), ['2026-10-24', '2026-10-20']);
      expect(sent.last.$2['energy'], 1, reason: 'the rest of it was sent');
      expect(sent.last.$2.containsKey('pain_area'), isFalse);
    });

    test('a refusal that is not about the date is said so', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      final key = await queue.enqueue(
        payload: {
          ...base,
          'pain_severity': 6,
          'pain_area': 'knee',
          'pain_red_flags': <String>[],
        },
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      await queue.markPainRefused(key, tooOld: false);
      expect(queue.painState, CheckInPainState.refused);
      expect(queue.painRefusedTooOld, isFalse);
    });
  });

  group('while a replay waits on the network', () {
    const base = {
      'sleep_quality': 3,
      'energy': 3,
      'soreness': 3,
      'hunger': 3,
      'mood': 3,
      'available_to_train': true,
      'note': '',
    };
    const pain = {
      'pain_severity': 6,
      'pain_area': 'knee',
      'pain_red_flags': <String>[],
    };

    Future<String> save(CheckInQueue queue, Map<String, dynamic> extra) =>
        queue.enqueue(
          payload: {...base, ...extra},
          localDate: '2026-10-24',
          timezone: 'Asia/Kolkata',
        );

    test('a check-in saved meanwhile survives when the first lands', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      final first = await save(queue, pain);
      final gate = Completer<void>();
      final sent = <String>[];
      final replaying = queue.replay((date, zone, key, payload) async {
        sent.add(key);
        if (key == first) await gate.future;
        return key == first;
      });
      await Future<void>.delayed(Duration.zero);

      final second = await save(queue, {'pain_severity': 0});
      gate.complete();
      expect((await replaying).retained, ['2026-10-24']);

      expect(sent, [first, second], reason: 'the earlier one first');
      final waiting = (await stored())['2026-10-24'] as Map;
      expect(waiting['idempotency_key'], second, reason: 'not wiped');
      expect(
        (await SharedPreferences.getInstance()).getString(
          CheckInQueue.earlierKeyFor(''),
        ),
        isNull,
        reason: 'the first one was delivered and went',
      );
    });

    test(
      'a check-in saved meanwhile survives when the first is refused',
      () async {
        SharedPreferences.setMockInitialValues({});
        final queue = await buildQueue();
        final first = await save(queue, pain);
        final gate = Completer<void>();
        final sent = <String>[];
        final replaying = queue.replay((date, zone, key, payload) async {
          sent.add(key);
          if (key == first) {
            await gate.future;
            throw const PostgrestException(message: 'no', code: '22023');
          }
          return false;
        });
        await Future<void>.delayed(Duration.zero);

        final second = await save(queue, {'pain_severity': 0});
        gate.complete();
        await replaying;

        expect(sent, [first, second]);
        final waiting = (await stored())['2026-10-24'] as Map;
        expect(waiting['idempotency_key'], second);
        expect(waiting.containsKey('pain_refused'), isFalse);
        expect(queue.painState, CheckInPainState.refused, reason: 'the first');
      },
    );

    test('replays run one after the other, each envelope once', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      final key = await save(queue, pain);
      final gate = Completer<void>();
      var calls = 0;
      Future<bool> send(
        String date,
        String zone,
        String id,
        Map<String, dynamic> payload,
      ) async {
        calls++;
        await gate.future;
        return true;
      }

      final one = queue.replay(send);
      final two = (await buildQueue()).replay(send);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expect((await one).delivered, ['2026-10-24']);
      expect((await two).fates, isEmpty);
      expect(calls, 1);
      expect(key, isNotEmpty);
    });

    test(
      'a refused check-in that a newer one replaced is not sent later',
      () async {
        SharedPreferences.setMockInitialValues({});
        final queue = await buildQueue();
        await save(queue, {...pain, 'energy': 1});
        Future<bool> refuse(
          String date,
          String zone,
          String id,
          Map<String, dynamic> payload,
        ) async {
          throw const PostgrestException(message: 'no', code: '22023');
        }

        expect((await queue.replay(refuse)).fates.values, [
          CheckInFate.painRefused,
        ]);
        final second = await save(queue, {'pain_severity': 0});
        final sent = <String>[];
        final replay = await queue.replay((date, zone, key, payload) async {
          sent.add(key);
          return true;
        });
        expect(replay.delivered, ['2026-10-24']);
        expect(sent, [second]);
        expect(queue.painState, CheckInPainState.refused, reason: 'still told');

        await queue.acknowledgeRefusedPain((date, zone, key, payload) async {
          sent.add(key);
          return true;
        });
        expect(sent, [second], reason: 'the older one would become the last');
        expect(queue.painState, CheckInPainState.none);
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getKeys().where((k) => k.contains('check_in')),
          isEmpty,
        );
      },
    );

    test('the day\'s limit on pain reports is a refusal: told, and the later '
        'check-in goes on', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      final first = await save(queue, pain);
      final second = await save(queue, {'pain_severity': 0});
      final sent = <String>[];
      final replay = await queue.replay((date, zone, key, payload) async {
        sent.add(key);
        if (key == first) {
          throw const PostgrestException(
            message: 'too many pain reports today',
            code: 'P0001',
          );
        }
        return true;
      });
      expect(replay.delivered, ['2026-10-24']);
      expect(sent, [first, second]);
      expect(queue.painState, CheckInPainState.refused);
      expect(queue.painRefusedTooOld, isFalse);
    });

    test('another P0001 is just retained', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await save(queue, pain);
      final replay = await queue.replay((date, zone, key, payload) async {
        throw const PostgrestException(message: 'busy', code: 'P0001');
      });
      expect(replay.retained, ['2026-10-24']);
      expect(queue.painState, CheckInPainState.waiting);
    });

    test('a duplicate key means the server has it: delivered', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await save(queue, {'pain_severity': 0});
      final replay = await queue.replay((date, zone, key, payload) async {
        throw const PostgrestException(message: 'duplicate', code: '23505');
      });
      expect(replay.delivered, ['2026-10-24']);
      expect(await stored(), isEmpty);
    });
  });
}

/// Preferences whose writes fail, as when the disk is full.
class _FailingWrites implements SharedPreferences {
  _FailingWrites(this._inner);

  final SharedPreferences _inner;

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  Future<bool> remove(String key) => _inner.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
