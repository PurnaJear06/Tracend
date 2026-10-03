import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/widgets/tracend_segmented_control.dart';

import 'haptics_recorder.dart';
import 'widget_host.dart';

void main() {
  testWidgets('changes selection with a selection haptic', (tester) async {
    final haptics = recordHaptics(tester);
    var selected = 7;
    await tester.pumpWidget(
      widgetHost(
        StatefulBuilder(
          builder: (context, setState) => TracendSegmentedControl<int>(
            segments: const [(7, '7 days'), (30, '30 days'), (90, '90 days')],
            selected: selected,
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );

    await tester.tap(find.text('30 days'));
    await tester.pump();
    expect(selected, 30);
    expect(haptics, ['HapticFeedbackType.selectionClick']);

    await tester.tap(find.text('30 days'));
    await tester.pump();
    expect(haptics, hasLength(1));
  });

  testWidgets('is at least 44pt tall and marks the selected segment', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      widgetHost(
        TracendSegmentedControl<int>(
          segments: const [(7, '7 days'), (30, '30 days')],
          selected: 7,
          onChanged: (_) {},
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(TracendSegmentedControl<int>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSemantics(find.text('7 days')),
      matchesSemantics(
        label: '7 days',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}
