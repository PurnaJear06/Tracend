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

  test('first sync backfills the full bounded project history', () {
    expect(
      healthSyncStart(
        now: DateTime(2026, 7, 4, 8),
        initialBackfillComplete: false,
      ),
      DateTime(2026, 6, 3),
    );
    expect(
      healthSyncStart(
        now: DateTime(2026, 7, 4, 8),
        initialBackfillComplete: true,
      ),
      DateTime(2026, 6, 28),
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
    expect(
      find.text(
        'Apple Health could not sync. Manual tracking is still available.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Today renders stored health evidence and honest missing sleep', (
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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('APPLE HEALTH EVIDENCE'), findsOneWidget);
    expect(find.text('Daily steps'), findsOneWidget);
    expect(find.textContaining('Sleep has no stored samples'), findsOneWidget);
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
