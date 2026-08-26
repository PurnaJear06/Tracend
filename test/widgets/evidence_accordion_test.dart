import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';
import 'package:tracend/shared/widgets/evidence_accordion.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [TracendColors.dark],
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('EvidenceAccordion', () {
    testWidgets('starts collapsed with content unmounted', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceAccordion(
            title: 'Evidence used and data gaps',
            child: Text('hidden content'),
          ),
        ),
      );
      expect(find.text('Evidence used and data gaps'), findsOneWidget);
      expect(find.text('hidden content'), findsNothing);
    });

    testWidgets('expanding mounts the content after the animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceAccordion(
            title: 'Evidence',
            child: Text('hidden content'),
          ),
        ),
      );
      await tester.tap(find.text('Evidence'));
      await tester.pump();
      expect(find.text('hidden content'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('hidden content'), findsOneWidget);
    });

    testWidgets('collapsing keeps content mounted until animation completes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceAccordion(
            title: 'Evidence',
            initiallyExpanded: true,
            child: Text('hidden content'),
          ),
        ),
      );
      expect(find.text('hidden content'), findsOneWidget);

      await tester.tap(find.text('Evidence'));
      await tester.pump();
      // Height animates BEFORE the content is removed.
      expect(find.text('hidden content'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('hidden content'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('hidden content'), findsNothing);
    });

    testWidgets('chevron rotates with expansion state', (tester) async {
      await tester.pumpWidget(
        _wrap(const EvidenceAccordion(title: 'Evidence', child: Text('body'))),
      );
      RotationTransition chevron() => tester.widget<RotationTransition>(
        find.descendant(
          of: find.byType(EvidenceAccordion),
          matching: find.byType(RotationTransition),
        ),
      );
      expect(chevron().turns.value, 0.0);
      await tester.tap(find.text('Evidence'));
      await tester.pumpAndSettle();
      expect(chevron().turns.value, 0.5);
      await tester.tap(find.text('Evidence'));
      await tester.pumpAndSettle();
      expect(chevron().turns.value, 0.0);
    });

    testWidgets('Reduce Motion expands and collapses instantly', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await tester.pumpWidget(
        _wrap(const EvidenceAccordion(title: 'Evidence', child: Text('body'))),
      );
      await tester.tap(find.text('Evidence'));
      // A single frame (no settle) must already show the content: the height
      // jumps to its end value instead of animating.
      await tester.pump();
      expect(find.text('body'), findsOneWidget);
      final expanded = tester.widget<Align>(
        find
            .ancestor(of: find.text('body'), matching: find.byType(Align))
            .first,
      );
      expect(expanded.heightFactor, 1.0);

      await tester.tap(find.text('Evidence'));
      await tester.pump();
      // Collapsed content is unmounted immediately, no animation wait.
      expect(find.text('body'), findsNothing);
    });

    testWidgets('header announces expanded state to semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(const EvidenceAccordion(title: 'Evidence', child: Text('body'))),
      );
      var node = tester.getSemantics(find.bySemanticsLabel('Evidence'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isExpanded, isNot(Tristate.none));
      expect(node.flagsCollection.isExpanded, Tristate.isFalse);

      await tester.tap(find.text('Evidence'));
      await tester.pumpAndSettle();
      node = tester.getSemantics(find.bySemanticsLabel('Evidence'));
      expect(node.flagsCollection.isExpanded, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('header meets the 44pt accessible tap target', (tester) async {
      await tester.pumpWidget(
        _wrap(const EvidenceAccordion(title: 'Evidence', child: Text('body'))),
      );
      final size = tester.getSize(find.byType(InkWell));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}
