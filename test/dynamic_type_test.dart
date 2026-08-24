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
  // Plan §8.2: Dynamic Type 1.0 / 1.3 / largest — wraps before truncating,
  // no overflow at 320pt. 1.0 is covered by the width matrix in
  // frontend_smoke_test.dart; this file covers 1.3 and the largest iOS
  // accessibility scale (~2.0) at the narrowest supported width.
  for (final scale in [1.3, 2.0]) {
    testWidgets('all tabs render without overflow at 320pt × $scale text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        const TracendApp(environment: _environment, themeMode: ThemeMode.dark),
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
}

void _expectNoLayoutException(WidgetTester tester, String tab) {
  final exception = tester.takeException();
  final detail = exception is FlutterError
      ? exception.toStringDeep()
      : exception?.toString();
  expect(exception, isNull, reason: '$tab layout failed:\n$detail');
}
