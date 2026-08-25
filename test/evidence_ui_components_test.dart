import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/health/health_models.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/shared/widgets/trajectory_trend.dart';

void main() {
  testWidgets('7-day trend fits compact phones', (tester) async {
    tester.view.physicalSize = const Size(240, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: Scaffold(
          body: TrajectoryTrend(
            history: HealthHistory([
              for (var i = 6; i >= 0; i--)
                HealthDay(
                  date: DateTime(2026, 8, 24).subtract(Duration(days: i)),
                  presentMetrics: const {HealthMetric.hrvSdnn},
                  hrvSdnnMs: 42.0 + (6 - i) * 2,
                ),
            ]),
          ),
        ),
      ),
    );
    // Bounded pump: the NOW-dot pulse is an intentional infinite loop.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('health status fits compact phones', (tester) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const Scaffold(
          body: HealthStatusCard(repository: ManualHealthRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
