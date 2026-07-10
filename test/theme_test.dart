import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

void main() {
  test('body text tokens meet WCAG AA in both themes', () {
    for (final colors in [TracendColors.light, TracendColors.dark]) {
      expect(
        _contrast(colors.textPrimary, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(colors.textSecondary, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

double _contrast(Color foreground, Color background) {
  final light = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final dark = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (light + 0.05) / (dark + 0.05);
}
