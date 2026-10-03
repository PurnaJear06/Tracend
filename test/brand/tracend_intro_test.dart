import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/brand/tracend_intro.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';

Widget _host({required bool ready, bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: TracendIntro(
        ready: ready,
        child: const Scaffold(body: Center(child: Text('Your plan'))),
      ),
    ),
  ),
);

/// Records the haptics the intro asks for.
List<String> _recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return haptics;
}

Finder get _wordmark => find.text('Tracend');

void main() {
  testWidgets('plays once, settles with a light haptic, then reveals the app', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: true));

    expect(_wordmark, findsOneWidget);
    expect(find.bySemanticsLabel('Skip intro'), findsOneWidget);
    // The app is built beneath from the first frame, hidden from VoiceOver.
    expect(find.text('Your plan'), findsOneWidget);
    expect(find.bySemanticsLabel('Your plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    expect(haptics, isEmpty);
    await tester.pump(const Duration(milliseconds: 150));
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    final settled = await tester.pumpAndSettle();
    expect(_wordmark, findsNothing);
    expect(find.bySemanticsLabel('Your plan'), findsOneWidget);
    expect(haptics, hasLength(1), reason: 'the intro never loops');
    // The motion, then the fade: well under two seconds in all.
    expect(settled, lessThan(12));
  });

  testWidgets('holds the finished mark with a loader until the app is ready', (
    tester,
  ) async {
    _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: false));
    // Past the motion, frame by frame, as the device would draw it.
    for (var frame = 0; frame < 14; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(_wordmark, findsOneWidget);
    expect(find.byType(TracendLoader), findsOneWidget);
    expect(find.bySemanticsLabel('Restoring your session'), findsOneWidget);
    expect(find.bySemanticsLabel('Skip intro'), findsNothing);

    await tester.pumpWidget(_host(ready: true));
    await tester.pumpAndSettle();
    expect(_wordmark, findsNothing);
    expect(find.text('Your plan'), findsOneWidget);
  });

  testWidgets('a tap skips straight to the app', (tester) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: true));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.bySemanticsLabel('Skip intro'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(_wordmark, findsNothing);
    expect(find.bySemanticsLabel('Your plan'), findsOneWidget);
    expect(haptics, isEmpty);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('Reduce Motion shows the finished mark and crossfades', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: true, reduceMotion: true));

    final wordmarkOpacity = tester.widget<Opacity>(
      find.ancestor(of: _wordmark, matching: find.byType(Opacity)).first,
    );
    expect(wordmarkOpacity.opacity, 1);
    expect(find.bySemanticsLabel('Skip intro'), findsNothing);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(_wordmark, findsNothing);
    expect(find.text('Your plan'), findsOneWidget);
    expect(haptics, isEmpty);
  });
}
