import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/shared/widgets/micro_motion.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('entrance animates when motion is allowed', (tester) async {
    await tester.pumpWidget(host(const MicroMotionEntrance(child: Text('in'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('in'), findsOneWidget);
  });

  testWidgets('entrance renders statically under Reduce Motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(host(const MicroMotionEntrance(child: Text('in'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('in'), findsOneWidget);
  });

  testWidgets('pulse loops when motion is allowed', (tester) async {
    await tester.pumpWidget(host(const MicroMotionPulse(child: Text('now'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('pulse renders statically under Reduce Motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(host(const MicroMotionPulse(child: Text('now'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('now'), findsOneWidget);
  });

  test('stagger delay is capped at 60ms per index', () {
    expect(MicroMotion.stagger(0), Duration.zero);
    expect(MicroMotion.stagger(1), const Duration(milliseconds: 60));
    expect(MicroMotion.stagger(20), const Duration(milliseconds: 480));
  });

  test('exit duration is faster than entry', () {
    const entry = Duration(milliseconds: 240);
    expect(
      MicroMotion.exitDuration(entry).inMilliseconds,
      lessThan(entry.inMilliseconds),
    );
  });
}
