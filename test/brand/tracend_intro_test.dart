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

Finder get _wordmark => find.bySemanticsLabel('Tracend');

/// The nearest [T] above [of]: the intro's own wrapper, below the route's.
W _nearest<W extends Widget>(WidgetTester tester, Finder of) =>
    tester.widget<W>(find.ancestor(of: of, matching: find.byType(W)).first);

double _appScale(WidgetTester tester) =>
    _nearest<ScaleTransition>(tester, find.text('Your plan')).scale.value;

double _appOpacity(WidgetTester tester) =>
    _nearest<FadeTransition>(tester, find.text('Your plan')).opacity.value;

double _stageScale(WidgetTester tester) =>
    _nearest<ScaleTransition>(tester, _wordmark).scale.value;

double _stageOpacity(WidgetTester tester) =>
    _nearest<FadeTransition>(tester, _wordmark).opacity.value;

void main() {
  testWidgets('plays once, lands with a light haptic, then hands over', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: true));

    expect(_wordmark, findsOneWidget);
    // The app is built beneath from the first frame, hidden from VoiceOver.
    expect(find.text('Your plan'), findsOneWidget);
    expect(find.bySemanticsLabel('Your plan'), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    expect(haptics, isEmpty);
    await tester.pump(const Duration(milliseconds: 150));
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    // A ready app still sees the motion through; it is not cut short.
    await tester.pump(const Duration(milliseconds: 200));
    expect(_wordmark, findsOneWidget);
    expect(_appOpacity(tester), 0);

    final settled = await tester.pumpAndSettle();
    expect(_wordmark, findsNothing);
    expect(find.bySemanticsLabel('Your plan'), findsOneWidget);
    expect(_appOpacity(tester), 1);
    expect(_appScale(tester), 1);
    expect(haptics, hasLength(1), reason: 'the intro never loops');
    // The rest of the motion, then the hand-off: well under a second.
    expect(settled, lessThan(8));
  });

  testWidgets('hands off by zooming through to the app', (tester) async {
    _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: true));
    // The first frame past the motion starts the hand-off.
    await tester.pump(TracendIntro.motion + const Duration(milliseconds: 1));
    expect(_stageScale(tester), 1);
    expect(_appScale(tester), 0.97);
    expect(_appOpacity(tester), 0);

    // Partway through the hand-off the mark has grown and is fading while
    // the app grows into place and fades in.
    await tester.pump(const Duration(milliseconds: 120));
    expect(_stageScale(tester), inExclusiveRange(1, 1.06));
    expect(_stageOpacity(tester), inExclusiveRange(0, 1));
    expect(_appScale(tester), inExclusiveRange(0.97, 1));
    expect(_appOpacity(tester), inExclusiveRange(0, 1));

    await tester.pump(TracendIntro.handOff);
    await tester.pump();
    expect(_wordmark, findsNothing);
    expect(_appScale(tester), 1);
    expect(_appOpacity(tester), 1);
  });

  testWidgets('has no skip: a tap neither ends nor shortens the intro', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: true));
    expect(find.text('Skip'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('skip', caseSensitive: false)),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.tapAt(tester.getCenter(find.byType(TracendIntro)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_wordmark, findsOneWidget);
    expect(_appOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    await tester.pumpAndSettle();
    expect(_wordmark, findsNothing);
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
    expect(_appOpacity(tester), 0);

    await tester.pumpWidget(_host(ready: true));
    // The loader leaves with the mark rather than blinking out first.
    await tester.pump();
    expect(find.byType(TracendLoader), findsOneWidget);
    await tester.pumpAndSettle();
    expect(_wordmark, findsNothing);
    expect(find.byType(TracendLoader), findsNothing);
    expect(find.bySemanticsLabel('Your plan'), findsOneWidget);
  });

  testWidgets('Reduce Motion shows the finished mark and crossfades', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: true, reduceMotion: true));
    expect(_wordmark, findsOneWidget);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // A crossfade only: nothing zooms.
    expect(_stageScale(tester), 1);
    expect(_appScale(tester), 1);
    expect(_appOpacity(tester), inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 150));
    expect(_wordmark, findsNothing);
    expect(find.text('Your plan'), findsOneWidget);
    expect(haptics, isEmpty);
  });

  testWidgets('Reduce Motion holds the finished mark with a loader', (
    tester,
  ) async {
    _recordHaptics(tester);
    await tester.pumpWidget(_host(ready: false, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_wordmark, findsOneWidget);
    expect(find.byType(TracendLoader), findsOneWidget);

    await tester.pumpWidget(_host(ready: true, reduceMotion: true));
    await tester.pumpAndSettle();
    expect(_wordmark, findsNothing);
    expect(find.bySemanticsLabel('Your plan'), findsOneWidget);
  });
}
