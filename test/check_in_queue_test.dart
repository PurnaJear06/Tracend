import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tracend/features/today/check_in_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CheckInQueue> buildQueue() async {
    final preferences = await SharedPreferences.getInstance();
    return CheckInQueue(preferences);
  }

  test(
    'enqueue persists the envelope with the answer day, not today',
    () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      final key = await queue.enqueue(
        payload: const {
          'sleep_quality': 4,
          'energy': 3,
          'soreness': 2,
          'hunger': 3,
          'mood': 4,
          'pain_severity': 0,
          'available_to_train': true,
          'note': 'Felt strong',
        },
        localDate: '2026-09-05',
        timezone: 'Asia/Kolkata',
      );
      final stored = (await SharedPreferences.getInstance()).getString(
        'daily_check_in_pending',
      );
      expect(stored, isNotNull);
      final envelope = jsonDecode(stored!) as Map<String, dynamic>;
      expect(envelope['idempotency_key'], key);
      expect(envelope['local_date'], '2026-09-05');
      expect(envelope['timezone'], 'Asia/Kolkata');
      expect((envelope['payload'] as Map)['sleep_quality'], 4);
    },
  );

  test(
    'replay delivers the stored envelope as recorded and clears it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: const {
          'sleep_quality': 3,
          'energy': 3,
          'soreness': 3,
          'hunger': 3,
          'mood': 3,
          'pain_severity': 0,
          'available_to_train': true,
          'note': '',
        },
        localDate: '2026-09-05',
        timezone: 'GMT+5:30',
      );
      final sent = <Map<String, dynamic>>[];
      final outcome = await queue.replay((
        localDate,
        timezone,
        idempotencyKey,
        payload,
      ) async {
        sent.add({
          'local_date': localDate,
          'timezone': timezone,
          'idempotency_key': idempotencyKey,
          'payload': payload,
        });
        return true;
      });
      expect(outcome, CheckInReplayOutcome.delivered);
      expect(sent, hasLength(1));
      // The answer day's date is sent as recorded, never re-dated to today.
      expect(sent.single['local_date'], '2026-09-05');
      expect(sent.single['timezone'], 'GMT+5:30');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'daily_check_in_pending',
        ),
        isNull,
      );
    },
  );

  test('replay retains the envelope when delivery fails', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    await queue.enqueue(
      payload: const {
        'sleep_quality': 2,
        'energy': 2,
        'soreness': 4,
        'hunger': 3,
        'mood': 2,
        'pain_severity': 1,
        'available_to_train': false,
        'note': '',
      },
      localDate: '2026-09-05',
      timezone: 'Asia/Kolkata',
    );
    var attempts = 0;
    final outcome = await queue.replay((
      localDate,
      timezone,
      key,
      payload,
    ) async {
      attempts++;
      return false;
    });
    expect(outcome, CheckInReplayOutcome.retained);
    expect(attempts, 1);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'daily_check_in_pending',
      ),
      isNotNull,
    );
  });

  test('replay retains the envelope when send throws', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    await queue.enqueue(
      payload: const {
        'sleep_quality': 3,
        'energy': 3,
        'soreness': 3,
        'hunger': 3,
        'mood': 3,
        'pain_severity': 0,
        'available_to_train': true,
        'note': '',
      },
      localDate: '2026-09-05',
      timezone: 'Asia/Kolkata',
    );
    final outcome = await queue.replay(
      (localDate, timezone, key, payload) async => throw Exception('offline'),
    );
    expect(outcome, CheckInReplayOutcome.retained);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'daily_check_in_pending',
      ),
      isNotNull,
    );
  });

  test('replay is a no-op when nothing is pending', () async {
    SharedPreferences.setMockInitialValues({});
    final queue = await buildQueue();
    var attempts = 0;
    final outcome = await queue.replay((a, b, c, d) async {
      attempts++;
      return true;
    });
    expect(outcome, CheckInReplayOutcome.none);
    expect(attempts, 0);
  });

  test('replay discards a legacy envelope without date fields', () async {
    // The pre-queue format stored {idempotency_key, payload} only. A user
    // upgrading from that build must not be stuck with an unsendable
    // envelope: it is discarded rather than replayed with a fabricated date.
    SharedPreferences.setMockInitialValues({
      'daily_check_in_pending': jsonEncode({
        'idempotency_key': '7e7d8f27-6d93-4ef7-a331-e0332b16850d',
        'payload': {'energy': 3},
      }),
    });
    final queue = await buildQueue();
    var attempts = 0;
    final outcome = await queue.replay((a, b, c, d) async {
      attempts++;
      return true;
    });
    expect(outcome, CheckInReplayOutcome.none);
    expect(attempts, 0);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'daily_check_in_pending',
      ),
      isNull,
    );
  });

  test(
    'clearDelivered removes the pending envelope after an inline save',
    () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      final key = await queue.enqueue(
        payload: const {
          'sleep_quality': 3,
          'energy': 3,
          'soreness': 3,
          'hunger': 3,
          'mood': 3,
          'pain_severity': 0,
          'available_to_train': true,
          'note': '',
        },
        localDate: '2026-09-06',
        timezone: 'Asia/Kolkata',
      );
      await queue.clearDelivered(key);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'daily_check_in_pending',
        ),
        isNull,
      );
    },
  );

  group('per athlete', () {
    const athleteA = '11111111-1111-4111-8111-111111111111';
    const athleteB = '22222222-2222-4222-8222-222222222222';

    Future<int> replayCount(String userId) async {
      var sent = 0;
      final queue = CheckInQueue(
        await SharedPreferences.getInstance(),
        userId: userId,
      );
      await queue.replay((localDate, timezone, key, payload) async {
        sent++;
        return true;
      });
      return sent;
    }

    test('one athlete\'s pending check-in is never sent for another', () async {
      SharedPreferences.setMockInitialValues({});
      await CheckInQueue(
        await SharedPreferences.getInstance(),
        userId: athleteA,
      ).enqueue(
        payload: const {'energy': 3},
        localDate: '2026-10-02',
        timezone: 'Asia/Kolkata',
      );

      expect(await replayCount(athleteB), 0);
      expect(await replayCount(athleteA), 1);
      expect(await replayCount(athleteA), 0);
    });

    test('an older build\'s envelope goes to the first athlete', () async {
      SharedPreferences.setMockInitialValues({
        CheckInQueue.legacyStorageKey: jsonEncode({
          'idempotency_key': 'legacy-key',
          'local_date': '2026-10-01',
          'timezone': 'Asia/Kolkata',
          'payload': {'energy': 2},
        }),
      });

      expect(await replayCount(athleteA), 1);
      expect(
        (await SharedPreferences.getInstance()).getString(
          CheckInQueue.legacyStorageKey,
        ),
        isNull,
      );
      expect(await replayCount(athleteB), 0);
    });
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

    test('waits, with its pain keys, until it is sent', () async {
      final queue = await queued();
      expect(queue.painState, CheckInPainState.waiting);
      Map<String, dynamic>? sent;
      final outcome = await queue.replay((date, zone, key, payload) async {
        sent = payload;
        return false;
      });
      expect(outcome, CheckInReplayOutcome.retained);
      expect(sent!['pain_red_flags'], ['locks_gives_way']);
      expect(queue.painState, CheckInPainState.waiting);
    });

    test('a refusal (22023) is kept, marked, and not sent again', () async {
      final queue = await queued();
      var calls = 0;
      Future<bool> refuse(
        String date,
        String zone,
        String key,
        Map<String, dynamic> payload,
      ) async {
        calls++;
        throw const PostgrestException(message: 'old', code: '22023');
      }

      expect(await queue.replay(refuse), CheckInReplayOutcome.painRefused);
      expect(queue.painState, CheckInPainState.refused);
      expect(await queue.replay(refuse), CheckInReplayOutcome.painRefused);
      expect(calls, 1, reason: 'a refusal is not retried every launch');
    });

    test('a refusal without pain keys is just retained', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await queue.enqueue(
        payload: const {'energy': 3, 'pain_severity': 0},
        localDate: '2026-10-02',
        timezone: 'Asia/Kolkata',
      );
      final outcome = await queue.replay((date, zone, key, payload) async {
        throw const PostgrestException(message: 'no', code: '22023');
      });
      expect(outcome, CheckInReplayOutcome.retained);
      expect(queue.painState, CheckInPainState.none);
    });

    test(
      'acknowledging sends the rest of the check-in without the pain',
      () async {
        final queue = await queued();
        await queue.replay((date, zone, key, payload) async {
          throw const PostgrestException(message: 'old', code: '22023');
        });
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
        expect(
          (await SharedPreferences.getInstance()).getString(
            'daily_check_in_pending',
          ),
          isNull,
        );
      },
    );

    test(
      'acknowledging keeps the rest queued when it cannot be sent',
      () async {
        final queue = await queued();
        await queue.replay((date, zone, key, payload) async {
          throw const PostgrestException(message: 'old', code: '22023');
        });
        await queue.acknowledgeRefusedPain((date, zone, key, payload) async {
          throw Exception('offline');
        });
        expect(queue.painState, CheckInPainState.none);
        Map<String, dynamic>? sent;
        expect(
          await queue.replay((date, zone, key, payload) async {
            sent = payload;
            return true;
          }),
          CheckInReplayOutcome.delivered,
        );
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
        localDate: '2026-10-23',
        timezone: 'Asia/Kolkata',
      );
      await queue.enqueue(
        payload: {...base, 'pain_severity': 0},
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      expect(queue.painState, CheckInPainState.waiting);

      final sent = <(String, Map<String, dynamic>)>[];
      final outcome = await queue.replay((date, zone, key, payload) async {
        sent.add((date, payload));
        return true;
      });
      expect(outcome, CheckInReplayOutcome.delivered);
      expect(sent.map((e) => e.$1), ['2026-10-23', '2026-10-24']);
      expect(sent.first.$2['pain_red_flags'], ['bladder_bowel_saddle']);
      expect(queue.painState, CheckInPainState.none);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().where((k) => k.contains('pending')),
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
      final outcome = await queue.replay((date, zone, key, payload) async {
        attempts.add(payload);
        return false;
      });
      expect(outcome, CheckInReplayOutcome.retained);
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
      await queue.enqueue(
        payload: {...base, 'pain_severity': 0},
        localDate: '2026-10-23',
        timezone: 'Asia/Kolkata',
      );
      await queue.enqueue(
        payload: {...base, 'pain_severity': 0},
        localDate: '2026-10-24',
        timezone: 'Asia/Kolkata',
      );
      final dates = <String>[];
      await queue.replay((date, zone, key, payload) async {
        dates.add(date);
        return true;
      });
      expect(dates, ['2026-10-24']);
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

      expect(await queue.replay(server), CheckInReplayOutcome.delivered);
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
      expect(await replaying, CheckInReplayOutcome.retained);

      expect(sent, [first, second], reason: 'the earlier one first');
      final preferences = await SharedPreferences.getInstance();
      final waiting =
          jsonDecode(preferences.getString('daily_check_in_pending')!) as Map;
      expect(waiting['idempotency_key'], second, reason: 'not wiped');
      expect(
        preferences.getString('daily_check_in_pending.earlier.'),
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
        final preferences = await SharedPreferences.getInstance();
        final waiting =
            jsonDecode(preferences.getString('daily_check_in_pending')!) as Map;
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
      expect(await one, CheckInReplayOutcome.delivered);
      expect(await two, CheckInReplayOutcome.none);
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

        expect(await queue.replay(refuse), CheckInReplayOutcome.painRefused);
        final second = await save(queue, {'pain_severity': 0});
        final sent = <String>[];
        expect(
          await queue.replay((date, zone, key, payload) async {
            sent.add(key);
            return true;
          }),
          CheckInReplayOutcome.delivered,
        );
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
          preferences.getKeys().where((k) => k.contains('pending')),
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
      final outcome = await queue.replay((date, zone, key, payload) async {
        sent.add(key);
        if (key == first) {
          throw const PostgrestException(
            message: 'too many pain reports today',
            code: 'P0001',
          );
        }
        return true;
      });
      expect(outcome, CheckInReplayOutcome.delivered);
      expect(sent, [first, second]);
      expect(queue.painState, CheckInPainState.refused);
      expect(queue.painRefusedTooOld, isFalse);
    });

    test(
      'another P0001, or one without a pain check, is just retained',
      () async {
        SharedPreferences.setMockInitialValues({});
        final queue = await buildQueue();
        await save(queue, pain);
        expect(
          await queue.replay((date, zone, key, payload) async {
            throw const PostgrestException(message: 'busy', code: 'P0001');
          }),
          CheckInReplayOutcome.retained,
        );
        expect(queue.painState, CheckInPainState.waiting);
      },
    );

    test('a duplicate key means the server has it: delivered', () async {
      SharedPreferences.setMockInitialValues({});
      final queue = await buildQueue();
      await save(queue, {'pain_severity': 0});
      final outcome = await queue.replay((date, zone, key, payload) async {
        throw const PostgrestException(message: 'duplicate', code: '23505');
      });
      expect(outcome, CheckInReplayOutcome.delivered);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('daily_check_in_pending'), isNull);
    });
  });
}
