import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/features/health/health_repository.dart';
import 'package:tracend/features/health/health_status_card.dart';
import 'package:tracend/shared/widgets/trajectory_lens.dart';

void main() {
  testWidgets('signal rail fits compact phones', (tester) async {
    tester.view.physicalSize = const Size(240, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.light,
        home: const Scaffold(
          body: TrajectoryLens(
            evidence: ['Recovery check-in', 'Approved plan'],
          ),
        ),
      ),
    );
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
