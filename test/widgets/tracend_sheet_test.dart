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

  group('unsaved input guard', () {
    Future<Future<String?>> openGuarded(WidgetTester tester) async {
      late Future<String?> result;
      final note = TextEditingController();
      addTearDown(note.dispose);
      await tester.pumpWidget(
        widgetHost(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => result = showTracendSheet<String>(
                  context,
                  title: 'Note',
                  builder: (sheetContext) => TracendSheetUnsavedGuard(
                    listenable: note,
                    isDirty: () => note.text.isNotEmpty,
                    child: Column(
                      children: [
                        TextField(controller: note),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop('saved'),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
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

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    final gestures = <String, Future<void> Function(WidgetTester)>{
      'the close button': (tester) =>
          tester.tap(find.bySemanticsLabel('Close')),
      'a tap on the scrim': (tester) => tester.tapAt(const Offset(20, 20)),
      'a swipe down': (tester) =>
          tester.fling(find.text('Note'), const Offset(0, 400), 1500),
    };

    for (final MapEntry(key: name, value: gesture) in gestures.entries) {
      testWidgets('$name closes a clean sheet at once', (tester) async {
        final result = await openGuarded(tester);

        await gesture(tester);
        await tester.pumpAndSettle();

        expect(await result, isNull);
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.text('Note'), findsNothing);
      });

      testWidgets('$name asks first when input is unsaved, then keeps it', (
        tester,
      ) async {
        await openGuarded(tester);
        await type(tester, 'half a thought');

        await gesture(tester);
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsNothing);
        expect(find.text('Note'), findsOneWidget);
        expect(find.text('half a thought'), findsOneWidget);
      });

      testWidgets('$name closes an unsaved sheet once discarded', (
        tester,
      ) async {
        final result = await openGuarded(tester);
        await type(tester, 'half a thought');

        await gesture(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        expect(await result, isNull);
        expect(find.text('Note'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('clearing the input makes the sheet clean again', (
      tester,
    ) async {
      final result = await openGuarded(tester);
      await type(tester, 'half a thought');
      await type(tester, '');

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(await result, isNull);
    });

    testWidgets('a save that pops the sheet is never asked about', (
      tester,
    ) async {
      final result = await openGuarded(tester);
      await type(tester, 'half a thought');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(await result, 'saved');
    });

    testWidgets('a guarded sheet with detents does not close on a swipe', (
      tester,
    ) async {
      final note = TextEditingController(text: 'typed');
      addTearDown(note.dispose);
      await tester.pumpWidget(
        widgetHost(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showTracendSheet<void>(
                context,
                title: 'Note',
                detents: const [0.5, 0.9],
                builder: (_) => TracendSheetUnsavedGuard(
                  isDirty: () => note.text.isNotEmpty,
                  child: const Text('Body'),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DraggableScrollableSheet>(
              find.byType(DraggableScrollableSheet),
            )
            .shouldCloseOnMinExtent,
        isFalse,
      );
    });

    testWidgets('outside a sheet the guard only shows its child', (
      tester,
    ) async {
      await tester.pumpWidget(
        widgetHost(
          TracendSheetUnsavedGuard(
            isDirty: () => true,
            child: const Text('Hi'),
          ),
        ),
      );

      expect(find.text('Hi'), findsOneWidget);
    });
  });
}
