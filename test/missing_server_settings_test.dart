import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tracend/app/app.dart';
import 'package:tracend/app/environment.dart';
import 'package:tracend/features/auth/phase_2_gate.dart';
import 'package:tracend/features/shell/app_shell.dart';

const _unconfigured = AppEnvironment(
  name: 'test',
  supabaseUrl: '',
  supabasePublishableKey: '',
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('a release build without server settings says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Phase2Gate(environment: _unconfigured, releaseBuild: true),
      ),
    );

    expect(find.text('This build is missing its server settings'), findsOne);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('a debug build without server settings keeps the demo data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TracendApp(environment: _unconfigured));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOne);
    expect(
      find.text('This build is missing its server settings'),
      findsNothing,
    );
  });
}
