import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/features/today/today_screen.dart';

void main() {
  final day = DateTime(2026, 7, 1, 8);

  test('normalizes canonical daily values and removes duplicate samples', () {
    final summaries = normalizeHealthSamples(
      samples: [
        _sample(HealthMetric.steps, 3000, day, id: 'steps-a'),
        _sample(HealthMetric.steps, 3000, day, id: 'steps-a'),
        _sample(HealthMetric.steps, 2400, day, id: 'steps-b'),
        _sample(
          HealthMetric.sleep,
          0,
          day.subtract(const Duration(hours: 8)),
          end: day.subtract(const Duration(hours: 1)),
          id: 'sleep-a',
          sleepStage: SleepStage.asleep,
        ),
        _sample(HealthMetric.weight, 76.2, day, id: 'weight-a'),
        _sample(HealthMetric.restingHeartRate, 58, day, id: 'heart-a'),
        _sample(HealthMetric.hrvSdnn, 52, day, id: 'hrv-a'),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries, hasLength(1));
    expect(summaries.single.steps, 5400);
    expect(summaries.single.sleepMinutes, 420);
    expect(summaries.single.weightKg, 76.2);
    expect(summaries.single.hrvSdnnMs, 52);
    expect(summaries.single.sourceChecksum, hasLength(64));
    expect(
      summaries.single.toJson(HealthMetric.values.toSet())['completeness'],
      'partial',
    );
  });

  test('empty or permission-unknown data stays manual-only', () {
    expect(
      deriveHealthConnectionState(
        now: day,
        lastSuccessfulSync: null,
        availableMetrics: const {},
      ),
      HealthConnectionState.manualOnly,
    );
  });

  test('malformed samples are discarded before sync normalization', () {
    final summaries = normalizeHealthSamples(
      samples: [
        _sample(HealthMetric.steps, 900000, day, id: 'invalid-steps'),
        _sample(HealthMetric.steps, 1200, day, id: 'valid-steps'),
        _sample(HealthMetric.weight, double.nan, day, id: 'invalid-weight'),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries.single.steps, 1200);
    expect(summaries.single.weightKg, isNull);
    expect(summaries.single.presentMetrics, {HealthMetric.steps});
  });

  test(
    'respiratory rate averages valid samples and rejects out-of-range ones',
    () {
      final summaries = normalizeHealthSamples(
        samples: [
          _sample(HealthMetric.respRate, 14.2, day, id: 'resp-a'),
          _sample(HealthMetric.respRate, 15.8, day, id: 'resp-b'),
          _sample(HealthMetric.respRate, 140, day, id: 'resp-invalid'),
        ],
        requestedMetrics: HealthMetric.values.toSet(),
        timezone: 'Asia/Kolkata',
      );

      expect(summaries.single.respRateBpm, 15);
      expect(summaries.single.presentMetrics, contains(HealthMetric.respRate));
      final json = summaries.single.toJson(HealthMetric.values.toSet());
      expect(json['respiratory_rate_bpm'], 15);
    },
  );

  test('normalizes supported sleep stages without double-counting total', () {
    final summaries = normalizeHealthSamples(
      samples: [
        _sample(
          HealthMetric.sleep,
          0,
          day,
          end: day.add(const Duration(hours: 7)),
          id: 'asleep',
          sleepStage: SleepStage.asleep,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          day,
          end: day.add(const Duration(hours: 4)),
          id: 'light',
          sleepStage: SleepStage.light,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          day,
          end: day.add(const Duration(hours: 2)),
          id: 'deep',
          sleepStage: SleepStage.deep,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          day,
          end: day.add(const Duration(hours: 1)),
          id: 'rem',
          sleepStage: SleepStage.rem,
        ),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries.single.sleepMinutes, 420);
    expect(summaries.single.sleepLightMinutes, 240);
    expect(summaries.single.sleepDeepMinutes, 120);
    expect(summaries.single.sleepRemMinutes, 60);
  });

  test('a night crossing midnight lands whole on the morning it ends', () {
    final summaries = normalizeHealthSamples(
      samples: [
        // Watch-style 23:00 -> 07:00 night delivered as 30-minute segments.
        for (var i = 0; i < 16; i++)
          _sample(
            HealthMetric.sleep,
            0,
            DateTime(2026, 6, 30, 23).add(Duration(minutes: 30 * i)),
            end: DateTime(2026, 6, 30, 23).add(Duration(minutes: 30 * (i + 1))),
            id: 'seg-$i',
            sleepStage: i < 4
                ? SleepStage.deep
                : (i < 12 ? SleepStage.light : SleepStage.rem),
          ),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries, hasLength(1));
    expect(summaries.single.localDate, DateTime(2026, 7, 1));
    expect(summaries.single.sleepMinutes, 480);
    expect(summaries.single.sleepDeepMinutes, 120);
    expect(summaries.single.sleepLightMinutes, 240);
    expect(summaries.single.sleepRemMinutes, 120);
  });

  test('consecutive nights attribute to their own mornings', () {
    final summaries = normalizeHealthSamples(
      samples: [
        // Night 1: Jun 29 23:30 -> Jun 30 06:30.
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 6, 29, 23, 30),
          end: DateTime(2026, 6, 30, 6, 30),
          id: 'night-1',
          sleepStage: SleepStage.asleep,
        ),
        // Night 2: Jun 30 23:30 -> Jul 1 06:30.
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 6, 30, 23, 30),
          end: DateTime(2026, 7, 1, 6, 30),
          id: 'night-2',
          sleepStage: SleepStage.asleep,
        ),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries, hasLength(2));
    expect(summaries.first.localDate, DateTime(2026, 6, 30));
    expect(summaries.first.sleepMinutes, 420);
    expect(summaries.last.localDate, DateTime(2026, 7, 1));
    expect(summaries.last.sleepMinutes, 420);
  });

  test('an evening nap separated from the night is its own session', () {
    final summaries = normalizeHealthSamples(
      samples: [
        // Nap 19:00 -> 20:00, then a > 60 min gap before the night.
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 6, 30, 19),
          end: DateTime(2026, 6, 30, 20),
          id: 'nap',
          sleepStage: SleepStage.light,
        ),
        // Night 23:30 -> 06:30 (ends Jul 1).
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 6, 30, 23, 30),
          end: DateTime(2026, 7, 1, 6, 30),
          id: 'night',
          sleepStage: SleepStage.asleep,
        ),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries, hasLength(2));
    expect(
      summaries.first.localDate,
      DateTime(2026, 6, 30),
      reason: 'the nap ends the evening it starts',
    );
    expect(summaries.first.sleepMinutes, 60);
    expect(
      summaries.last.localDate,
      DateTime(2026, 7, 1),
      reason: 'the night ends the next morning',
    );
    expect(summaries.last.sleepMinutes, 420);
  });

  test('a mixed-category night unions unspecified and staged chunks', () {
    // Production regression (2026-09-10): a staged 4-hour stretch (Core 186
    // + Deep 34 + REM 20) followed by auto-detected unspecified fragments
    // and a mid-night awake spell. The old category preference stored only
    // the unspecified 146 of 386 measured minutes.
    final summaries = normalizeHealthSamples(
      samples: [
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 9, 9, 22),
          end: DateTime(2026, 9, 10, 1, 6),
          id: 'core-1',
          sleepStage: SleepStage.light,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 9, 10, 1, 6),
          end: DateTime(2026, 9, 10, 1, 40),
          id: 'deep-1',
          sleepStage: SleepStage.deep,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 9, 10, 1, 40),
          end: DateTime(2026, 9, 10, 2),
          id: 'rem-1',
          sleepStage: SleepStage.rem,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 9, 10, 3),
          end: DateTime(2026, 9, 10, 4),
          id: 'frag-1',
          sleepStage: SleepStage.asleep,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 9, 10, 4),
          end: DateTime(2026, 9, 10, 4, 17),
          id: 'awake-1',
          sleepStage: SleepStage.awake,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 9, 10, 4, 30),
          end: DateTime(2026, 9, 10, 5, 56),
          id: 'frag-2',
          sleepStage: SleepStage.asleep,
        ),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries, hasLength(1));
    expect(summaries.single.localDate, DateTime(2026, 9, 10));
    expect(summaries.single.sleepMinutes, 386);
    expect(summaries.single.sleepLightMinutes, 186);
    expect(summaries.single.sleepDeepMinutes, 34);
    expect(summaries.single.sleepRemMinutes, 20);
    expect(summaries.single.sleepAwakeMinutes, 17);
  });

  test('overlapping sleep sources union instead of double-counting', () {
    final summaries = normalizeHealthSamples(
      samples: [
        // Two sources each record the same 23:00 -> 00:00 hour: one plain
        // "asleep", one staged as Core. A plain sum would report 120.
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 6, 30, 23),
          end: DateTime(2026, 7, 1),
          id: 'watch-asleep',
          sleepStage: SleepStage.asleep,
        ),
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 6, 30, 23),
          end: DateTime(2026, 7, 1),
          id: 'app-core',
          sleepStage: SleepStage.light,
        ),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries, hasLength(1));
    expect(summaries.single.localDate, DateTime(2026, 7, 1));
    expect(summaries.single.sleepMinutes, 60);
    expect(summaries.single.sleepLightMinutes, 60);
  });

  test('an awake-only night is zero sleep minutes, not null', () {
    final summaries = normalizeHealthSamples(
      samples: [
        // Only restless awake-in-bed time was recorded — no asleep
        // category exists. The health_sync_v1 contract requires
        // sleep_minutes to be defined whenever sleep samples are present,
        // and the server's 1-960 scoring gate reads 0 as absence.
        _sample(
          HealthMetric.sleep,
          0,
          DateTime(2026, 6, 30, 23),
          end: DateTime(2026, 6, 30, 23, 40),
          id: 'awake-only',
          sleepStage: SleepStage.awake,
        ),
      ],
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    );

    expect(summaries.single.sleepMinutes, 0);
    expect(summaries.single.sleepAwakeMinutes, 40);
    expect(summaries.single.presentMetrics, contains(HealthMetric.sleep));
    final json = summaries.single.toJson(HealthMetric.values.toSet());
    expect(json['sleep_minutes'], 0);
    expect(json['sleep_light_minutes'], isNull);
  });

  test(
    'non-sleep metrics keep their start day alongside re-attributed sleep',
    () {
      final summaries = normalizeHealthSamples(
        samples: [
          _sample(
            HealthMetric.sleep,
            0,
            DateTime(2026, 6, 30, 23),
            end: DateTime(2026, 7, 1, 7),
            id: 'night',
            sleepStage: SleepStage.asleep,
          ),
          // Steps recorded during the evening still belong to Jun 30.
          _sample(
            HealthMetric.steps,
            3000,
            DateTime(2026, 6, 30, 20),
            id: 'steps',
          ),
        ],
        requestedMetrics: HealthMetric.values.toSet(),
        timezone: 'Asia/Kolkata',
      );

      expect(summaries, hasLength(2));
      final byDate = {
        for (final summary in summaries) summary.localDate: summary,
      };
      expect(byDate[DateTime(2026, 6, 30)]!.steps, 3000);
      expect(byDate[DateTime(2026, 6, 30)]!.sleepMinutes, isNull);
      expect(byDate[DateTime(2026, 7, 1)]!.sleepMinutes, 480);
      expect(byDate[DateTime(2026, 7, 1)]!.steps, isNull);
    },
  );

  test('checksum is stable when HealthKit sample order changes', () {
    final samples = [
      _sample(HealthMetric.steps, 1200, day, id: 'steps'),
      _sample(HealthMetric.weight, 76, day, id: 'weight'),
    ];
    final first = normalizeHealthSamples(
      samples: samples,
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    ).single;
    final second = normalizeHealthSamples(
      samples: samples.reversed.toList(),
      requestedMetrics: HealthMetric.values.toSet(),
      timezone: 'Asia/Kolkata',
    ).single;

    expect(second.sourceChecksum, first.sourceChecksum);
  });

  test('partial data is labeled partial without inventing missing values', () {
    expect(
      deriveHealthConnectionState(
        now: day,
        lastSuccessfulSync: day.subtract(const Duration(hours: 1)),
        availableMetrics: const {HealthMetric.steps},
      ),
      HealthConnectionState.partial,
    );
  });

  test('old data is labeled stale', () {
    expect(
      deriveHealthConnectionState(
        now: day,
        lastSuccessfulSync: day.subtract(const Duration(days: 3)),
        availableMetrics: HealthMetric.values.toSet(),
      ),
      HealthConnectionState.stale,
    );
  });

  test('unsupported device is labeled unavailable', () {
    expect(
      deriveHealthConnectionState(
        now: day,
        lastSuccessfulSync: null,
        availableMetrics: const {},
        unavailable: true,
      ),
      HealthConnectionState.unavailable,
    );
  });

  test('first sync backfills the initial 9-day window', () {
    expect(
      healthSyncStart(
        now: DateTime(2026, 7, 4, 8),
        initialBackfillComplete: false,
      ),
      DateTime(2026, 6, 26),
    );
    expect(
      healthSyncStart(
        now: DateTime(2026, 7, 4, 8),
        initialBackfillComplete: true,
      ),
      DateTime(2026, 6, 27),
    );
  });

  testWidgets('manual fallback remains actionable when sync fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Scaffold(
          body: HealthStatusCard(repository: _FailingHealthRepository()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Manual tracking'), findsOneWidget);
    expect(find.text('Connect Apple Health'), findsOneWidget);
    await tester.tap(find.text('Connect Apple Health'));
    await tester.pumpAndSettle();
    expect(find.text('Bad state: fixture failure'), findsOneWidget);
  });

  testWidgets('Today keeps Apple Health controls in the profile only', (
    tester,
  ) async {
    const environment = AppEnvironment(
      name: 'test',
      supabaseUrl: '',
      supabasePublishableKey: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const TodayScreen(
          environment: environment,
          health: _HistoryHealthRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Morning status recorded'),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.pumpAndSettle();
    // Chunk 7: the Apple Health section (status card + evidence) moved to the
    // profile; Today keeps the sync button in the hero instead.
    expect(find.text('What matters today'), findsNothing);
    expect(find.text('Daily steps'), findsNothing);
    expect(find.text('Connect Apple Health'), findsNothing);
    expect(find.text('Refresh Apple Health'), findsNothing);
  });
}

RawHealthSample _sample(
  HealthMetric metric,
  double value,
  DateTime start, {
  DateTime? end,
  required String id,
  SleepStage? sleepStage,
}) => RawHealthSample(
  metric: metric,
  value: value,
  start: start,
  end: end ?? start.add(const Duration(minutes: 1)),
  sampleId: id,
  sourceId: 'source',
  sleepStage: sleepStage,
);

class _FailingHealthRepository implements HealthRepository {
  @override
  Future<HealthSyncStatus> connectAndSync() async =>
      throw StateError('fixture failure');

  @override
  Future<HealthSyncStatus> loadStatus() async =>
      const HealthSyncStatus(state: HealthConnectionState.manualOnly);

  @override
  Future<HealthHistory> loadHistory() async => const HealthHistory([]);

  @override
  Future<HealthSyncStatus> sync() => connectAndSync();
}

class _HistoryHealthRepository implements HealthRepository {
  const _HistoryHealthRepository();

  @override
  Future<HealthSyncStatus> loadStatus() async => HealthSyncStatus(
    state: HealthConnectionState.partial,
    lastSuccessfulSync: DateTime(2026, 7, 4),
    availableMetrics: const {HealthMetric.steps},
  );

  @override
  Future<HealthHistory> loadHistory() async => HealthHistory([
    HealthDay(
      date: DateTime(2026, 7, 3),
      presentMetrics: const {HealthMetric.steps},
      steps: 6000,
    ),
    HealthDay(
      date: DateTime(2026, 7, 4),
      presentMetrics: const {HealthMetric.steps},
      steps: 7200,
    ),
  ]);

  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> sync() => loadStatus();
}
