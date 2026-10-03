import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';
import 'package:tracend/shared/widgets/tracend_motion.dart';
import 'package:tracend/shared/widgets/tracend_toast.dart';

import 'widget_host.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    TracendMotionLevel? motion,
    String message = 'Check-in saved',
  }) async {
    await tester.pumpWidget(
      widgetHost(
        motion: motion,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => TracendToast.show(
                context,
                message,
                icon: CupertinoIcons.checkmark_alt,
              ),
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a glass pill with its icon in a live region', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpHost(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Check-in saved'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    expect(find.byType(TracendGlass), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Check-in saved')),
      matchesSemantics(label: 'Check-in saved', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('dismisses itself after its time', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('Save'));
    await tester.pump();

    await tester.pump(
      TracendToast.visibleFor - const Duration(milliseconds: 1),
    );
    expect(find.text('Check-in saved'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Check-in saved'), findsNothing);
  });

  testWidgets('springs in and out at full motion', (tester) async {
    await pumpHost(tester, motion: TracendMotionLevel.full);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Check-in saved'), findsOneWidget);

    await tester.pumpAndSettle();
    await tester.pump(TracendToast.visibleFor);
    await tester.pumpAndSettle();
    expect(find.text('Check-in saved'), findsNothing);
  });

  testWidgets('a tap dismisses it early', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('Save'));
    await tester.pump();

    await tester.tap(find.text('Check-in saved'));
    await tester.pumpAndSettle();
    expect(find.text('Check-in saved'), findsNothing);
  });

  testWidgets('a new toast replaces the visible one', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      widgetHost(
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    TracendToast.show(captured, 'First');
    await tester.pump();
    TracendToast.show(captured, 'Second');
    await tester.pump();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    TracendToast.hide(captured);
    await tester.pump();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('leaves no pending timer when the tree goes away', (
    tester,
  ) async {
    await pumpHost(tester, motion: TracendMotionLevel.full);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Check-in saved'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(find.text('Check-in saved'), findsNothing);
  });
}
