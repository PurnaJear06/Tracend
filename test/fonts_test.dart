import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

void main() {
  test('font family constants match the registered pubspec families', () {
    expect(TracendFonts.displayFamily, 'Spline Sans');
    expect(TracendFonts.monoFamily, 'IBM Plex Mono');
  });

  test('display styles carry Spline Sans; body/label styles stay system', () {
    for (final theme in [TracendTheme.light, TracendTheme.dark]) {
      final text = theme.textTheme;
      expect(text.displaySmall?.fontFamily, TracendFonts.displayFamily);
      expect(text.headlineMedium?.fontFamily, TracendFonts.displayFamily);
      expect(text.titleLarge?.fontFamily, TracendFonts.displayFamily);
      expect(text.titleMedium?.fontFamily, TracendFonts.displayFamily);
      expect(text.bodyLarge?.fontFamily, isNull);
      expect(text.bodyMedium?.fontFamily, isNull);
      expect(text.labelLarge?.fontFamily, isNull);
      expect(text.labelMedium?.fontFamily, isNull);
    }
  });

  test('base theme does not force a custom family', () {
    expect(TracendTheme.light.textTheme.bodyLarge?.fontFamily, isNull);
    expect(TracendTheme.dark.textTheme.bodyLarge?.fontFamily, isNull);
  });

  test('dataUtility helper is mono with tabular figures', () {
    final style = TracendTheme.dataUtility(TracendColors.dark);
    expect(style.fontFamily, TracendFonts.monoFamily);
    expect(style.fontSize, 13);
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('labelCaps matches DESIGN_SYSTEM §3.2: 11/16, 0.08em, w500', (
    tester,
  ) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: TracendTheme.dark,
        home: Builder(
          builder: (context) {
            style = TracendTheme.labelCaps(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(style.fontSize, 11);
    expect(style.letterSpacing, 0.9);
    expect(style.fontWeight, FontWeight.w500);
    expect(style.height, closeTo(16 / 11, 0.001));
  });
}
