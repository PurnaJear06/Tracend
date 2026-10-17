import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/features/workout_hr/heart_rate_profile.dart';
import 'package:tracend/features/workout_hr/heart_rate_profile_repository.dart';

class _Repository implements HealthRepository {
  @override
  Future<HealthSyncStatus> loadStatus() async => HealthSyncStatus(
    state: HealthConnectionState.partial,
    lastSuccessfulSync: DateTime.now(),
    availableMetrics: const {HealthMetric.steps},
  );

  @override
  Future<HealthHistory> loadHistory() async => const HealthHistory([]);

  @override
  Future<HealthSyncStatus> connectAndSync() => loadStatus();

  @override
  Future<HealthSyncStatus> sync() => loadStatus();
}

class _WithProfile extends _Repository implements HeartRateProfileSource {
  _WithProfile(this.profile);

  final HeartRateProfile? profile;
  int loads = 0;

  @override
  Future<HeartRateProfile?> loadHeartRateProfile() async {
    loads += 1;
    return profile;
  }
}

HeartRateProfile _profile() => buildHeartRateProfile(
  HeartRateInputs(
    asOf: '2026-10-17',
    birthYear: 1990,
    resting: [
      for (var day = 1; day <= 5; day++)
        RestingHeartRateDay(
          localDate: '2026-10-${(17 - day).toString().padLeft(2, '0')}',
          bpm: 60,
        ),
    ],
    sets: const [],
    peakCandidates: const [],
  ),
);

Future<void> _pump(
  WidgetTester tester,
  HealthRepository repository, {
  bool compact = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: TracendTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: HealthStatusCard(repository: repository, compact: compact),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'the Health sheet shows the zones once Apple Health is connected',
    (tester) async {
      final repository = _WithProfile(_profile());
      await _pump(tester, repository);
      await tester.pumpAndSettle();
      expect(find.text('Heart-rate zones'), findsOneWidget);
      expect(find.text('Z5'), findsOneWidget);
      expect(repository.loads, 1);
    },
  );

  testWidgets('a repository without a profile source shows no zones', (
    tester,
  ) async {
    await _pump(tester, _Repository());
    await tester.pumpAndSettle();
    expect(find.text('Heart-rate zones'), findsNothing);
  });

  testWidgets('the compact card and a failed profile read show no zones', (
    tester,
  ) async {
    final repository = _WithProfile(_profile());
    await _pump(tester, repository, compact: true);
    await tester.pumpAndSettle();
    expect(find.text('Heart-rate zones'), findsNothing);
    expect(repository.loads, 0);
    await _pump(tester, _WithProfile(null));
    await tester.pumpAndSettle();
    expect(find.text('Heart-rate zones'), findsNothing);
  });
}
