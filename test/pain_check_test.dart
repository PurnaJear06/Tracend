import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracend/features/readiness/day_adjustment.dart';
import 'package:tracend/features/readiness/day_adjustment_controller.dart';
import 'package:tracend/features/readiness/pain_check.dart';
import 'package:tracend/features/readiness/pain_report_queue.dart';
import 'package:tracend/features/readiness/pain_reporting.dart';
import 'package:tracend/features/readiness/safety_copy.dart';

import 'day_adjustment_fixtures.dart';
import 'pain_fakes.dart';

PainReport _report({
  String key = 'key-1',
  int severity = 3,
  List<String> flags = const [],
  PainArea area = PainArea.knee,
  String day = '2026-10-24',
}) => PainReport(
  localDate: day,
  area: area,
  severity: severity,
  redFlags: flags,
  idempotencyKey: key,
);

/// The database's own table, read from the migration that defines it.
Map<String, dynamic> _sqlRules() {
  final sql = File(
    'supabase/migrations/20261024060025_pain_checks.sql',
  ).readAsStringSync();
  final match = RegExp(
    r'''select '(\{"version":"pain-v1".*?\})'::jsonb;''',
  ).firstMatch(sql)!;
  return jsonDecode(match.group(1)!) as Map<String, dynamic>;
}

/// A server that answers each report when its gate opens, so a test can do
/// something else while one is on its way.
class _GatedRepository implements PainCheckRepository {
  final sent = <String>[];
  final gates = <String, Completer<void>>{};
  final failing = <String>{};

  Completer<void> gate(String key) => gates.putIfAbsent(key, Completer.new);

  @override
  Future<PainCheckResult> record(PainReport report) async {
    sent.add(report.idempotencyKey);
    await gates[report.idempotencyKey]?.future;
    if (failing.contains(report.idempotencyKey)) {
      throw const PainCheckException(PainCheckFailure.retry);
    }
    return PainCheckResult(
      id: 'id',
      outcome: report.outcome,
      areaState: 'watch',
    );
  }
}

/// Refuses the report when its gate opens.
class _RefusingRepository implements PainCheckRepository {
  _RefusingRepository(this.gate);
  final Completer<void> gate;

  @override
  Future<PainCheckResult> record(PainReport report) async {
    await gate.future;
    throw const PainCheckException(PainCheckFailure.refused, tooOld: true);
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('the outcome of a pain report', () {
    test('is the table the database keeps (private.pain_rules)', () {
      final rules = _sqlRules();
      final flags = Map<String, dynamic>.from(rules['red_flags'] as Map);
      expect(redFlagRules.keys.toSet(), flags.keys.toSet());
      for (final entry in redFlagRules.entries) {
        expect(entry.value.outcome.wire, flags[entry.key], reason: entry.key);
      }
      // The bands the severity falls into.
      expect(rules['clinician_today_from'], 7);
      expect(rules['modify_from'], 4);
      expect(rules['watch_from'], 1);
    });

    test('asks the questions the server side asks, in its words', () {
      final source = File(
        'supabase/functions/_shared/training/joints/red_flags.ts',
      ).readAsStringSync();
      final entries = RegExp(
        r'(\w+): \{\s*areas: (\[[^\]]*\]|everyArea),\s*question:\s*"((?:[^"\\]|\\.)*)"',
      ).allMatches(source).toList();
      expect(entries, hasLength(10));
      for (final entry in entries) {
        final code = entry.group(1)!;
        final areas = entry.group(2) == 'everyArea'
            ? PainArea.values.toSet()
            : {
                for (final match in RegExp(
                  r'"(\w+)"',
                ).allMatches(entry.group(2)!))
                  PainArea.fromWire(match.group(1))!,
              };
        expect(redFlagRules[code]!.areas, areas, reason: code);
        expect(redFlagQuestion(code), entry.group(3), reason: code);
      }
    });

    test('says the range cues the server side says', () {
      final source = File(
        'supabase/functions/_shared/training/joints/rules.ts',
      ).readAsStringSync();
      final cues = RegExp(
        r'code: "(\w+)",\s*joint: [^,]+,\s*pattern: [^,]+,\s*cue: "((?:[^"\\]|\\.)*)"',
      ).allMatches(source).toList();
      expect(cues, hasLength(13));
      for (final cue in cues) {
        expect(
          rangeNoteText(cue.group(1)!),
          cue.group(2),
          reason: cue.group(1),
        );
      }
    });

    for (final (severity, flags, outcome) in [
      (0, <String>[], PainOutcome.clear),
      (1, <String>[], PainOutcome.watch),
      (3, <String>[], PainOutcome.watch),
      (4, <String>[], PainOutcome.modify),
      (6, <String>[], PainOutcome.modify),
      (7, <String>[], PainOutcome.clinicianToday),
      (10, <String>[], PainOutcome.clinicianToday),
      (2, ['pop_or_sudden'], PainOutcome.clinicianToday),
      (2, ['numb_weak_limb'], PainOutcome.clinicianToday),
      (2, ['fever_unwell'], PainOutcome.clinician),
      (5, ['night_pain'], PainOutcome.clinician),
      (1, ['bladder_bowel_saddle'], PainOutcome.urgent),
      (9, ['chest_or_breath', 'pop_or_sudden'], PainOutcome.urgent),
      (5, ['night_pain', 'rapid_swelling'], PainOutcome.clinicianToday),
    ]) {
      test('$severity with $flags is ${outcome.wire}', () {
        expect(painOutcome(severity, flags), outcome);
      });
    }

    test('without a red-flag answer it goes by the strength alone', () {
      expect(painOutcome(8, null), PainOutcome.clinicianToday);
      expect(painOutcome(5, null), PainOutcome.modify);
    });

    test('a flag this build does not know routes out today', () {
      expect(
        painOutcome(1, ['a_flag_from_the_future']),
        PainOutcome.clinicianToday,
      );
    });

    test('only urgent, today and clinician give a route', () {
      expect(PainOutcome.urgent.route, 'urgent');
      expect(PainOutcome.clinicianToday.route, 'clinician_today');
      expect(PainOutcome.clinician.route, 'clinician');
      expect(PainOutcome.modify.route, isNull);
      expect(PainOutcome.watch.route, isNull);
      expect(PainOutcome.clear.route, isNull);
    });

    test('every area is asked its own questions and the general ones', () {
      expect(redFlagCodesFor(PainArea.back), contains('bladder_bowel_saddle'));
      expect(
        redFlagCodesFor(PainArea.knee),
        isNot(contains('bladder_bowel_saddle')),
      );
      expect(redFlagCodesFor(PainArea.knee), contains('locks_gives_way'));
      expect(redFlagCodesFor(PainArea.shoulder), contains('chest_or_breath'));
      expect(
        redFlagCodesFor(PainArea.shoulder),
        contains('dislocated_or_cannot_lift'),
      );
      for (final area in PainArea.values) {
        expect(
          redFlagCodesFor(area),
          containsAll([
            'numb_weak_limb',
            'pop_or_sudden',
            'cannot_bear_or_move',
            'fever_unwell',
            'night_pain',
          ]),
        );
      }
    });
  });

  group('record_pain_check_v1 on the wire', () {
    late List<(String, Map<String, dynamic>)> calls;
    late Object? Function() answer;

    SupabasePainCheckRepository repository() =>
        SupabasePainCheckRepository.withRpc((function, params) async {
          calls.add((function, params));
          return answer();
        });

    setUp(() {
      calls = [];
      answer = () => jsonDecode(
        File('test/contract/fixtures/pain_check_v1_0.json').readAsStringSync(),
      );
    });

    test('sends the parameters it takes, with the idempotency key', () async {
      final result = await repository().record(
        PainReport(
          localDate: '2026-10-24',
          area: PainArea.back,
          severity: 5,
          redFlags: const ['pop_or_sudden'],
          idempotencyKey: 'k-1',
          exercisePerformanceId: 'perf-1',
        ),
      );
      expect(calls.single.$1, 'record_pain_check_v1');
      expect(calls.single.$2, {
        'local_date': '2026-10-24',
        'source': 'workout',
        'area': 'back',
        'severity': 5,
        'pattern': null,
        'red_flags': ['pop_or_sudden'],
        'cleared_by_clinician': false,
        'exercise_performance_id': 'perf-1',
        'idempotency_key': 'k-1',
      });
      expect(result.outcome, PainOutcome.modify);
      expect(result.areaState, 'limited');
    });

    test('a report that did not ask about red flags sends none, not an empty '
        'list', () async {
      await repository().record(
        PainReport(
          localDate: '2026-10-24',
          area: PainArea.back,
          severity: 3,
          redFlags: null,
          idempotencyKey: 'k-2',
        ),
      );
      expect(calls.single.$2['red_flags'], isNull);
      final back = PainReport.tryParse(
        jsonDecode(
          jsonEncode(
            PainReport(
              localDate: '2026-10-24',
              area: PainArea.back,
              severity: 3,
              redFlags: null,
              idempotencyKey: 'k-2',
            ).toJson(),
          ),
        ),
      )!;
      expect(back.redFlags, isNull, reason: 'kept as "not asked" in the queue');
    });

    test('names a refusal (22023) apart from a failure to reach it', () async {
      answer = () =>
          throw const PostgrestException(message: 'old', code: '22023');
      await expectLater(
        repository().record(_report()),
        throwsA(
          isA<PainCheckException>().having(
            (e) => e.failure,
            'failure',
            PainCheckFailure.refused,
          ),
        ),
      );
      answer = () =>
          throw const PostgrestException(message: 'busy', code: 'P0001');
      await expectLater(
        repository().record(_report()),
        throwsA(
          isA<PainCheckException>().having(
            (e) => e.failure,
            'failure',
            PainCheckFailure.retry,
          ),
        ),
      );
    });

    test(
      'an answer this build cannot read still means it was recorded',
      () async {
        answer = () => {'schema_version': '9.0'};
        final result = await repository().record(_report(severity: 8));
        expect(result.understood, isFalse);
        expect(
          result.outcome,
          PainOutcome.clinicianToday,
          reason: 'the phone\'s own outcome stands',
        );
      },
    );

    test('only the date window is "too old"; any other 22023 is not', () async {
      answer = () => throw const PostgrestException(
        message: 'a pain check is for today or yesterday',
        code: '22023',
      );
      await expectLater(
        repository().record(_report()),
        throwsA(
          isA<PainCheckException>().having((e) => e.tooOld, 'tooOld', true),
        ),
      );
      answer = () => throw const PostgrestException(
        message: 'that exercise is not yours to report on',
        code: '22023',
      );
      await expectLater(
        repository().record(_report()),
        throwsA(
          isA<PainCheckException>()
              .having((e) => e.failure, 'failure', PainCheckFailure.refused)
              .having((e) => e.tooOld, 'tooOld', false),
        ),
      );
    });
  });

  group('a report that cannot go yet', () {
    late SharedPreferences preferences;
    late FakePainCheckRepository server;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      server = FakePainCheckRepository();
    });

    test('waits on the phone and goes when it can, once', () async {
      final queue = PainReportQueue(preferences, userId: 'a');
      await queue.add(_report());
      await queue.add(_report(), refused: false);
      expect(queue.state.waiting, hasLength(1), reason: 'one key, one report');

      server.failure = PainCheckFailure.retry;
      var state = await queue.drain(server);
      expect(state.waiting, hasLength(1));
      expect(state.refused, isEmpty);

      server.failure = null;
      state = await queue.drain(server);
      expect(state.isEmpty, isTrue);
      expect(server.reports.map((r) => r.idempotencyKey), ['key-1', 'key-1']);
      expect(preferences.getString(PainReportQueue.storageKeyFor('a')), isNull);
    });

    test('a refusal is kept until the athlete has read it', () async {
      final queue = PainReportQueue(preferences, userId: 'a');
      await queue.add(_report(severity: 8, flags: const ['pop_or_sudden']));
      server.failure = PainCheckFailure.refused;
      var state = await queue.drain(server);
      expect(state.waiting, isEmpty);
      expect(state.refused.single.redFlags, ['pop_or_sudden']);

      // It is not sent again; nothing drops it silently.
      server.failure = null;
      server.reports.clear();
      state = await queue.drain(server);
      expect(state.refused, hasLength(1));
      expect(server.reports, isEmpty);

      await queue.dismissRefused();
      expect(queue.state.isEmpty, isTrue);
    });

    group('while a drain waits on the network', () {
      late _GatedRepository gated;
      late PainReportQueue queue;

      setUp(() {
        gated = _GatedRepository();
        queue = PainReportQueue(preferences, userId: 'a');
      });

      test('a report added meanwhile is not lost', () async {
        await queue.add(_report(key: 'r1'));
        gated.gate('r1');
        gated.failing.add('r2');
        final draining = queue.drain(gated);
        await _tick();

        await PainReportQueue(preferences, userId: 'a').add(_report(key: 'r2'));
        gated.gates['r1']!.complete();
        final left = await draining;

        expect(left.waiting.map((r) => r.idempotencyKey), ['r2']);
        expect(gated.sent, ['r1', 'r2'], reason: 'sent in the same drain');
        expect(
          PainReportQueue(preferences, userId: 'a').state.waiting,
          hasLength(1),
        );
      });

      test('a refusal dismissed meanwhile stays dismissed', () async {
        await queue.add(_report(key: 'old'), refused: true);
        await queue.add(_report(key: 'r1'));
        gated.gate('r1');
        gated.failing.add('r1');
        final draining = queue.drain(gated);
        await _tick();

        await PainReportQueue(preferences, userId: 'a').dismissRefused();
        gated.gates['r1']!.complete();
        final left = await draining;

        expect(left.refused, isEmpty);
        expect(
          PainReportQueue(preferences, userId: 'a').state.refused,
          isEmpty,
        );
        expect(left.waiting.single.idempotencyKey, 'r1');
      });

      test('a queue cleared for a deleted account stays empty', () async {
        await queue.add(_report(key: 'r1'));
        gated.gate('r1');
        gated.failing.add('r1');
        final draining = queue.drain(gated);
        await _tick();

        await PainReportQueue.clearFor(preferences, 'a');
        gated.gates['r1']!.complete();
        final left = await draining;

        expect(left.isEmpty, isTrue);
        expect(
          preferences.getString(PainReportQueue.storageKeyFor('a')),
          isNull,
          reason: 'the drain did not write the report back',
        );
      });

      test('a refusal that comes back is marked on the report that is '
          'still there, not on one that has gone', () async {
        await queue.add(_report(key: 'r1'));
        gated.gate('r1');
        final refusing = _RefusingRepository(gated.gates['r1']!);
        final draining = queue.drain(refusing);
        await _tick();
        await queue.remove('r1');
        gated.gates['r1']!.complete();
        final left = await draining;
        expect(left.isEmpty, isTrue, reason: 'it was not brought back');
      });

      test('an athlete who is no longer signed in gets nothing sent', () async {
        var signedIn = 'a';
        final guarded = PainReportQueue(
          preferences,
          userId: 'a',
          signedInUser: () => signedIn,
        );
        await guarded.add(_report(key: 'r1'));
        await guarded.add(_report(key: 'r2'));
        gated.gate('r1');
        final draining = guarded.drain(gated);
        await _tick();

        signedIn = 'b';
        gated.gates['r1']!.complete();
        final left = await draining;

        expect(gated.sent, ['r1'], reason: 'r2 was not sent for the old user');
        expect(left.waiting.map((r) => r.idempotencyKey), ['r2']);
      });

      test('two drains at once send each report once', () async {
        await queue.add(_report(key: 'r1'));
        gated.gate('r1');
        final first = queue.drain(gated);
        final second = PainReportQueue(preferences, userId: 'a').drain(gated);
        await _tick();
        gated.gates['r1']!.complete();
        await Future.wait([first, second]);
        expect(gated.sent, ['r1']);
      });
    });

    test('is kept per athlete', () async {
      await PainReportQueue(preferences, userId: 'a').add(_report());
      expect(PainReportQueue(preferences, userId: 'b').state.isEmpty, isTrue);
      expect(
        PainReportQueue(preferences, userId: 'a').state.waiting,
        hasLength(1),
      );
    });

    test('a report round-trips with everything it says', () {
      final original = PainReport(
        localDate: '2026-10-24',
        area: PainArea.shoulder,
        severity: 4,
        redFlags: const ['numb_weak_limb'],
        idempotencyKey: 'k',
        pattern: 'rest',
        exercisePerformanceId: 'p',
      );
      final back = PainReport.tryParse(
        jsonDecode(jsonEncode(original.toJson())),
      )!;
      expect(back.toJson(), original.toJson());
      expect(PainReport.tryParse({'area': 'knee'}), isNull);
    });
  });

  group('PainReporting', () {
    late FakePainCheckRepository server;
    late PainReporting reporting;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      server = FakePainCheckRepository();
      reporting = PainReporting(repository: server, userId: 'a');
    });

    test('sends at once and says the server\'s outcome', () async {
      final submission = reporting.submit(_report(severity: 5));
      final delivery = await submission.delivery;
      expect(delivery.sent, isTrue);
      expect(submission.outcome, PainOutcome.modify);
      expect(delivery.areaState, 'limited');
      expect((await reporting.state()).isEmpty, isTrue);
    });

    test(
      'without a connection keeps the report and still says what to do',
      () async {
        server.failure = PainCheckFailure.retry;
        final submission = reporting.submit(
          _report(
            severity: 2,
            flags: const ['bladder_bowel_saddle'],
            area: PainArea.back,
          ),
        );
        final delivery = await submission.delivery;
        expect(delivery.sent, isFalse);
        expect(delivery.refused, isFalse);
        expect(
          submission.outcome,
          PainOutcome.urgent,
          reason: 'a red flag is answered from the phone\'s own rules',
        );
        expect((await reporting.state()).waiting, hasLength(1));

        server.failure = null;
        final left = await reporting.drain();
        expect(left.isEmpty, isTrue);
        expect(server.reports.last.idempotencyKey, 'key-1');
      },
    );

    test('a refusal is kept, not forgotten', () async {
      server.failure = PainCheckFailure.refused;
      final submission = reporting.submit(_report(severity: 8));
      final delivery = await submission.delivery;
      expect(delivery.refused, isTrue);
      expect(submission.outcome, PainOutcome.clinicianToday);
      expect((await reporting.state()).refused, hasLength(1));
      await reporting.dismissRefused();
      expect((await reporting.state()).isEmpty, isTrue);
    });

    test('reads today again only when a drain sent something', () async {
      final readiness = FakeDayAdjustmentRepository(
        adjustmentJson(kind: 'none', status: 'none', triggers: const []),
      );
      final controller = DayAdjustmentController(
        repository: readiness,
        serverToday: () async => DateTime(2026, 10, 2),
      );
      addTearDown(controller.dispose);
      final withReadiness = PainReporting(
        repository: server,
        readiness: controller,
        userId: 'a',
      );

      await withReadiness.drain();
      await _tick();
      expect(readiness.loads, isEmpty, reason: 'nothing waited, nothing sent');

      server.failure = PainCheckFailure.retry;
      await withReadiness.submit(_report()).delivery;
      await withReadiness.drain();
      await _tick();
      expect(readiness.loads, isEmpty, reason: 'it could not be sent');

      server.failure = null;
      await withReadiness.drain();
      await _tick();
      expect(readiness.loads, hasLength(1), reason: 'sent: read it again');
    });

    test('a send that hangs is kept after the wait, and forgotten when it '
        'lands', () async {
      final gate = Completer<void>();
      server.hold = gate.future;
      final waiting = PainReporting(
        repository: server,
        userId: 'a',
        sendTimeout: const Duration(milliseconds: 40),
      );
      final submission = waiting.submit(_report(severity: 8));
      expect(
        submission.outcome,
        PainOutcome.clinicianToday,
        reason: 'the outcome is there before anything is sent',
      );
      final delivery = await submission.delivery;
      expect(delivery.sent, isFalse);
      expect(
        (await waiting.state()).waiting,
        hasLength(1),
        reason: 'kept, not lost',
      );

      gate.complete();
      await _tick();
      await _tick();
      expect(
        (await waiting.state()).isEmpty,
        isTrue,
        reason: 'the attempt landed after all',
      );
    });

    test('a report the server took but this build cannot read is recorded, '
        'not kept waiting', () async {
      server.unreadable = true;
      final submission = reporting.submit(_report(severity: 8));
      final delivery = await submission.delivery;
      expect(delivery.sent, isTrue);
      expect(delivery.outcome, PainOutcome.clinicianToday, reason: 'its own');
      expect(delivery.areaState, isNull);
      expect((await reporting.state()).isEmpty, isTrue);
    });

    test(
      'a refusal that is not about the date is not called too old',
      () async {
        server
          ..failure = PainCheckFailure.refused
          ..tooOld = false;
        final delivery = await reporting.submit(_report(severity: 8)).delivery;
        expect(delivery.refused, isTrue);
        expect(delivery.tooOld, isFalse);
        expect((await reporting.state()).refusedTooOld, isFalse);
      },
    );
  });

  test('the closest route wins, and an unknown one is the strictest', () {
    expect(stricterRoute(null, null), isNull);
    expect(stricterRoute('clinician', null), 'clinician');
    expect(
      stricterRoute('pain_referral', 'clinician_today'),
      'clinician_today',
    );
    expect(stricterRoute('urgent', 'clinician_today'), 'urgent');
    expect(
      stricterRoute('clinician_today', 'a_route_from_the_future'),
      'a_route_from_the_future',
    );
    expect(routeNeedsAcknowledgement('urgent'), isTrue);
    expect(routeNeedsAcknowledgement('clinician_today'), isTrue);
    expect(routeNeedsAcknowledgement('a_route_from_the_future'), isTrue);
    expect(routeNeedsAcknowledgement('pain_referral'), isFalse);
    expect(routeNeedsAcknowledgement('clinician'), isFalse);
  });
}
