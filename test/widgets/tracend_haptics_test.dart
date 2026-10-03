import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/widgets/tracend_haptics.dart';

import 'haptics_recorder.dart';

void main() {
  testWidgets('each role sends its system haptic type', (tester) async {
    final calls = recordHaptics(tester);

    await TracendHaptics.selection();
    await TracendHaptics.light();
    await TracendHaptics.medium();
    await TracendHaptics.heavy();
    await TracendHaptics.success();
    await TracendHaptics.warning();

    expect(calls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.successNotification',
      'HapticFeedbackType.warningNotification',
    ]);
  });

  testWidgets('without a mock a fire-and-forget call does nothing', (
    tester,
  ) async {
    // Callers never await a haptic, so an unanswered channel cannot stall
    // the interaction that played it.
    unawaited(TracendHaptics.selection());
    unawaited(TracendHaptics.success());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
