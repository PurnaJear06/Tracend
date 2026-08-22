import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/shared/widgets/premium_gradient_card.dart';

void main() {
  testWidgets('renders child and never contains a BackdropFilter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: const Scaffold(
          body: Center(
            child: PremiumGradientCard(glow: true, child: Text('evidence')),
          ),
        ),
      ),
    );
    expect(find.text('evidence'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
