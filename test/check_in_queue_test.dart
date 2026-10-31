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

  test('clear removes the day after an inline save, but not a newer answer '
      'for the same day', () async {
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
    await queue.clear(localDate: '2026-09-06', idempotencyKey: first);
    expect(await queue.pendingDays(), ['2026-09-06']);
    await queue.clear(localDate: '2026-09-06', idempotencyKey: second);
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
