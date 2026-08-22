import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/shared/widgets/tracend_glass.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: TracendTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('renders with blur when enabled', (tester) async {
    await tester.pumpWidget(
      host(const TracendGlass(child: SizedBox(width: 100, height: 40))),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('enabled: false renders opaque fallback without blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const TracendGlass(
          enabled: false,
          child: SizedBox(width: 100, height: 40),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('reduceTransparency renders opaque fallback without blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const TracendGlass(
          reduceTransparency: true,
          child: SizedBox(width: 100, height: 40),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
