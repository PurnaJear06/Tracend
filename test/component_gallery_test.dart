import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/dev/component_gallery_app.dart';

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

  testWidgets('trajectory lens exposes an ordered evidence summary', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const ComponentGalleryApp(themeMode: ThemeMode.light),
    );
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(
        'Trajectory evidence: Sleep stable, Training on plan, Nutrition on '
        'target. Next move: Maintain plan.',
      ),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.bySemanticsLabel(
        'Trajectory evidence: Sleep stable, Training on plan, Nutrition on '
        'target. Next move: Maintain plan.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
