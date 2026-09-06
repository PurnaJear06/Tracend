import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracend/features/today/check_in_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CheckInQueue> buildQueue() async {
    final preferences = await SharedPreferences.getInstance();
    return CheckInQueue(preferences);
  }

  test('enqueue persists the envelope with the answer day, not today', () async {
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
    final stored = (await SharedPreferences.getInstance())
        .getString('daily_check_in_pending');
    expect(stored, isNotNull);
    final envelope = jsonDecode(stored!) as Map<String, dynamic>;
    expect(envelope['idempotency_key'], key);
    expect(envelope['local_date'], '2026-09-05');
    expect(envelope['timezone'], 'Asia/Kolkata');
    expect((envelope['payload'] as Map)['sleep_quality'], 4);
  });

  test('replay delivers the stored envelope as recorded and clears it', () async {
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
    final outcome = await queue.replay(
      (localDate, timezone, idempotencyKey, payload) async {
        sent.add({
          'local_date': localDate,
          'timezone': timezone,
          'idempotency_key': idempotencyKey,
          'payload': payload,
        });
        return true;
      },
    );
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
  });

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
    final outcome = await queue.replay((localDate, timezone, key, payload) async {
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

  test('clear removes the pending envelope after an inline save', () async {
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
      localDate: '2026-09-06',
      timezone: 'Asia/Kolkata',
    );
    await queue.clear();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'daily_check_in_pending',
      ),
      isNull,
    );
  });
}
