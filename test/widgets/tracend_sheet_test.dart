import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/widgets/tracend_sheet.dart';

import 'widget_host.dart';

void main() {
  Future<Future<String?>> open(
    WidgetTester tester, {
    List<double>? detents,
    String? title = 'Training load',
  }) async {
    late Future<String?> result;
    await tester.pumpWidget(
      widgetHost(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => result = showTracendSheet<String>(
                context,
                title: title,
                subtitle: 'How much you have trained lately',
                detents: detents,
                builder: (sheetContext) => Column(
                  children: [
                    const Text('Sheet body'),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop('done'),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('opens with the standard header, handle and blurred scrim', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Training load'), findsOneWidget);
    expect(find.text('How much you have trained lately'), findsOneWidget);
    expect(find.text('Sheet body'), findsOneWidget);
    expect(find.byType(TracendSheetHandle), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completes with the value the sheet pops', (tester) async {
    final result = await open(tester);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(await result, 'done');
    expect(find.text('Sheet body'), findsNothing);
  });

  testWidgets('the close button dismisses with null', (tester) async {
    final result = await open(tester);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(find.text('Sheet body'), findsNothing);
  });

  testWidgets('a swipe down dismisses it', (tester) async {
    final result = await open(tester);

    await tester.fling(find.text('Training load'), const Offset(0, 400), 1500);
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(find.text('Sheet body'), findsNothing);
  });

  testWidgets('a tap on the scrim dismisses it', (tester) async {
    final result = await open(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });

  testWidgets('detents open at the first size in a draggable sheet', (
    tester,
  ) async {
    await open(tester, detents: const [0.5, 0.9]);

    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.initialChildSize, 0.5);
    expect(sheet.maxChildSize, 0.9);
    expect(sheet.snap, isTrue);
    expect(find.text('Sheet body'), findsOneWidget);
  });

  testWidgets('without a title there is no header', (tester) async {
    await open(tester, title: null);

    expect(find.bySemanticsLabel('Close'), findsNothing);
    expect(find.text('Sheet body'), findsOneWidget);
  });

  testWidgets('the body is lifted above the keyboard exactly once', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    late double seenInset;
    await tester.pumpWidget(
      widgetHost(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showTracendSheet<void>(
              context,
              title: 'Note',
              builder: (sheetContext) {
                seenInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
                return const Text('Typing');
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(seenInset, 0);
    final bottom = tester.getBottomLeft(find.text('Typing')).dy;
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(bottom, lessThan(screen - 300 / tester.view.devicePixelRatio));
  });
}
