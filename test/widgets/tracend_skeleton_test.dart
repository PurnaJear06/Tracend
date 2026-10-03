import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';

import 'widget_host.dart';

void main() {
  const shapes = Column(
    children: [
      TracendSkeleton.block(height: 120),
      TracendSkeleton.line(widthFactor: 0.6),
      TracendSkeleton.row(),
      TracendSkeleton.row(lines: 1),
    ],
  );

  testWidgets('renders still under the suite-wide static scope', (
    tester,
  ) async {
    await tester.pumpWidget(widgetHost(shapes));
    await tester.pumpAndSettle();

    expect(find.byType(TracendSkeleton), findsNWidgets(4));
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('renders still under Reduce Motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      widgetHost(motion: TracendMotionLevel.full, shapes),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('sweeps while visible at full motion', (tester) async {
    await tester.pumpWidget(
      widgetHost(motion: TracendMotionLevel.full, shapes),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ShaderMask), findsNWidgets(4));
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
  });

  testWidgets('pauses when its TickerMode is off', (tester) async {
    await tester.pumpWidget(
      widgetHost(
        motion: TracendMotionLevel.full,
        const TickerMode(enabled: false, child: shapes),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('is hidden from VoiceOver', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      widgetHost(
        Semantics(label: 'Loading Train', container: true, child: shapes),
      ),
    );

    expect(find.bySemanticsLabel('Loading Train'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Loading Train')),
      matchesSemantics(label: 'Loading Train'),
    );
    semantics.dispose();
  });
}
