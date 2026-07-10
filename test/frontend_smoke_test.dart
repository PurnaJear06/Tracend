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
  for (final width in [320.0, 375.0, 390.0, 430.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'primary shells render at ${width.toInt()}pt in ${mode.name}',
        (tester) async {
          _configurePhone(tester, width);

          await tester.pumpWidget(
            TracendApp(environment: _environment, themeMode: mode),
          );
          await tester.pumpAndSettle();
          _expectNoLayoutException(tester, 'Today');

          for (final tab in ['Train', 'Coach', 'Nutrition', 'Progress']) {
            await tester.tap(find.text(tab).last);
            await tester.pumpAndSettle();
            _expectNoLayoutException(tester, tab);
          }
        },
      );
    }
  }

  testWidgets('primary shell supports accessibility text and reduced motion', (
    tester,
  ) async {
    _configurePhone(tester, 375);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const TracendApp(environment: _environment, themeMode: ThemeMode.light),
    );
    await tester.pumpAndSettle();
    _expectNoLayoutException(tester, 'Today');

    for (final tab in ['Train', 'Coach', 'Nutrition', 'Progress']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      _expectNoLayoutException(tester, tab);
    }
  });
}

void _expectNoLayoutException(WidgetTester tester, String tab) {
  final exception = tester.takeException();
  final detail = exception is FlutterError
      ? exception.toStringDeep()
      : exception?.toString();
  expect(exception, isNull, reason: '$tab layout failed:\n$detail');
}

void _configurePhone(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
