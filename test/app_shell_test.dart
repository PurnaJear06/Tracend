import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';

const _environment = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

void main() {
  testWidgets('shows exactly five labeled primary destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TracendApp(environment: _environment));
    await tester.pumpAndSettle();

    for (final label in ['Today', 'Train', 'Coach', 'Nutrition', 'Progress']) {
      expect(find.text(label), findsWidgets);
      expect(
        find.byKey(ValueKey('tab-${label.toLowerCase()}')),
        findsOneWidget,
      );
    }
    expect(find.text('Complete Push day.'), findsOneWidget);
  });

  testWidgets('switches tabs while preserving the primary shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TracendApp(environment: _environment));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nutrition').last);
    await tester.pumpAndSettle();

    expect(find.text('Confirmed meals only'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-nutrition')), findsOneWidget);

    await tester.tap(find.text('Progress').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Record two measurements to reveal a trend'),
      findsOneWidget,
    );
  });

  testWidgets('opens account as a detail route rather than a sixth tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TracendApp(environment: _environment));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open account'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('PRIVACY AND DATA'), 240);

    expect(find.text('PRIVACY AND DATA'), findsOneWidget);
  });
}
