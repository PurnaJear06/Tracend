import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/brand/tracend_loader.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  testWidgets('the loader says what is loading and keeps moving', (
    tester,
  ) async {
    // The suite runs under a static motion scope; the loader moves only at
    // full motion.
    await tester.pumpWidget(
      TracendMotionScope(
        level: TracendMotionLevel.full,
        child: _host(const TracendLoader(semanticLabel: 'Loading your plan')),
      ),
    );

    expect(find.bySemanticsLabel('Loading your plan'), findsOneWidget);
    expect(tester.getSize(find.byType(TracendLoader)), const Size(28, 28));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('under Reduce Motion the arc and dot stay still', (tester) async {
    await tester.pumpWidget(
      _host(
        const TracendLoader(semanticLabel: 'Loading your plan'),
        reduceMotion: true,
      ),
    );

    expect(find.bySemanticsLabel('Loading your plan'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the mark is an image named Tracend unless told otherwise', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const TracendMark(size: 64)));
    expect(find.bySemanticsLabel('Tracend'), findsOneWidget);
    expect(tester.getSize(find.byType(TracendMark)), const Size(64, 64));

    await tester.pumpWidget(_host(const TracendMark(semanticLabel: null)));
    expect(find.bySemanticsLabel('Tracend'), findsNothing);
  });
}
