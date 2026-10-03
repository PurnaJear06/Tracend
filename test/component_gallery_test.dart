import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/dev/component_gallery_app.dart';
import 'package:tracend/shared/widgets/pressable.dart';
import 'package:tracend/shared/widgets/tracend_scaffold.dart';
import 'package:tracend/shared/widgets/tracend_skeleton.dart';

void main() {
  for (final width in [375.0, 390.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('gallery renders at ${width.toInt()}pt in ${mode.name}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(ComponentGalleryApp(themeMode: mode));
        await tester.pumpAndSettle();

        expect(find.text('Component gallery'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Start workout'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Start workout'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('gallery remains operable at an accessibility text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      const ComponentGalleryApp(themeMode: ThemeMode.light),
    );
    await tester.pumpAndSettle();

    expect(find.text('Component gallery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery respects reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const ComponentGalleryApp(themeMode: ThemeMode.light),
    );
    await tester.scrollUntilVisible(
      find.text('Start workout'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Start workout'));
    await tester.pump();

    expect(find.text('Workout started'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('7-day trend exposes an ordered trend summary', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const ComponentGalleryApp(themeMode: ThemeMode.light),
    );
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(
        RegExp('7-day heart rate variability trend, 18–24 Aug'),
      ),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.bySemanticsLabel(
        '7-day heart rate variability trend, 18–24 Aug: range 42–53 ms, '
        '53 ms latest on 24 Aug, 7 of 7 days recorded. '
        'Up 11 ms since 18 Aug.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    // The 7-day trend's latest-day pulse loops, so settle by frame count.
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('gallery sheet opens and swipes closed in ${mode.name}', (
      tester,
    ) async {
      await tester.pumpWidget(ComponentGalleryApp(themeMode: mode));
      await reveal(tester, find.text('Sheet'));

      await tester.tap(find.text('Sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Training load'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.fling(
        find.text('Training load'),
        const Offset(0, 500),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.text('Training load'), findsNothing);
    });

    testWidgets('gallery confirm and toast work in ${mode.name}', (
      tester,
    ) async {
      await tester.pumpWidget(ComponentGalleryApp(themeMode: mode));
      await reveal(tester, find.text('Destructive confirm'));

      await tester.tap(find.text('Destructive confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this thread?'), findsOneWidget);
      await tester.tap(find.text('Delete thread'));
      await tester.pumpAndSettle();

      expect(find.text('Thread deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('gallery theme switch moves between light and dark', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ComponentGalleryApp(themeMode: ThemeMode.light),
    );
    BuildContext screen() =>
        tester.element(find.byType(ComponentGalleryScreen));
    expect(Theme.of(screen()).brightness, Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(screen()).brightness, Brightness.dark);
  });

  testWidgets('gallery shows every shared widget', (tester) async {
    await tester.pumpWidget(
      const ComponentGalleryApp(themeMode: ThemeMode.dark),
    );
    await reveal(tester, find.text('Ready to train'));
    expect(find.byType(Pressable), findsOneWidget);
    await reveal(tester, find.text('New best'));
    expect(find.byType(StatusChip), findsNWidgets(5));
    await reveal(tester, find.text('16 sets'));
    await reveal(tester, find.byType(TracendSkeleton).last);
    expect(find.byType(TracendSkeleton), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
