import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_theme.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

void main() {
  test('font family constants match the registered pubspec families', () {
    expect(TracendFonts.displayFamily, 'Archivo');
    expect(TracendFonts.numericFamily, 'Archivo SemiCondensed');
  });

  test('display styles carry Archivo; body/label styles stay system', () {
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

  test('dataUtility helper is numeric with tabular figures', () {
    final style = TracendTheme.dataUtility(TracendColors.dark);
    expect(style.fontFamily, TracendFonts.numericFamily);
    expect(style.fontSize, 13);
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('labelCaps is the sentence-case 13pt w600 label', (tester) async {
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
    expect(style.fontSize, 13);
    expect(style.letterSpacing, 0);
    expect(style.fontWeight, FontWeight.w600);
  });

  test('every bundled weight is registered for both Archivo families', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final file in [
      'Archivo-Medium',
      'Archivo-SemiBold',
      'Archivo-Bold',
      'Archivo-ExtraBold',
      'ArchivoSemiCondensed-Medium',
      'ArchivoSemiCondensed-SemiBold',
      'ArchivoSemiCondensed-Bold',
      'ArchivoSemiCondensed-ExtraBold',
    ]) {
      expect(pubspec, contains('assets/fonts/$file.ttf'));
      expect(File('assets/fonts/$file.ttf').existsSync(), isTrue);
    }
  });
}
