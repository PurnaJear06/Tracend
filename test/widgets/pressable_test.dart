import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';

import 'haptics_recorder.dart';
import 'widget_host.dart';

void main() {
  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('scales to 0.97 while pressed and taps with its haptic', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    var taps = 0;
    await tester.pumpWidget(
      widgetHost(
        motion: TracendMotionLevel.full,
        Center(
          child: Pressable(
            onTap: () => taps++,
            haptic: TracendHaptics.light,
            child: const SizedBox(width: 200, height: 80, child: Text('Card')),
          ),
        ),
      ),
    );

    expect(scaleOf(tester), 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(scaleOf(tester), 0.97);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Pressable.pressDuration,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
    expect(taps, 1);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('reduced motion keeps the tap and drops the scale', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      widgetHost(
        motion: TracendMotionLevel.reduced,
        Center(
          child: Pressable(
            onTap: () => taps++,
            child: const SizedBox(width: 200, height: 80, child: Text('Card')),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(scaleOf(tester), 1);
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('is a button to VoiceOver, dimmed without onTap', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      widgetHost(
        Column(
          children: [
            Pressable(
              onTap: () {},
              semanticLabel: 'Open training load',
              child: const Text('Load'),
            ),
            const Pressable(onTap: null, child: Text('Locked')),
          ],
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Open training load')),
      matchesSemantics(
        label: 'Open training load',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Locked')),
      matchesSemantics(label: 'Locked', isButton: true, hasEnabledState: true),
    );
    semantics.dispose();
  });
}
