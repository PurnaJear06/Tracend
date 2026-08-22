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

  test('dark secondary text meets AA on canvas and surface', () {
    final dark = TracendColors.dark;
    expect(
      _contrast(dark.textSecondary, dark.canvas),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(dark.textSecondary, dark.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('dark graphics tokens meet the 3:1 graphics threshold on canvas', () {
    final dark = TracendColors.dark;
    expect(_contrast(dark.actionPrimary, dark.canvas), greaterThanOrEqualTo(3));
    expect(_contrast(dark.stateStable, dark.canvas), greaterThanOrEqualTo(3));
    expect(_contrast(dark.accentAmber, dark.canvas), greaterThanOrEqualTo(3));
    expect(_contrast(dark.accentNow, dark.canvas), greaterThanOrEqualTo(3));
  });

  test('light theme keeps the Phase-4 baseline palette', () {
    const light = TracendColors.light;
    expect(light.canvas, const Color(0xFFF3F6F8));
    expect(light.surface, const Color(0xFFFFFFFF));
    expect(light.textPrimary, const Color(0xFF10151D));
    expect(light.textSecondary, const Color(0xFF556170));
    expect(light.actionPrimary, const Color(0xFF4A57E8));
    expect(light.stateStable, const Color(0xFF00796B));
  });

  test('dark theme uses the Precision Pro Stitch palette', () {
    const dark = TracendColors.dark;
    expect(dark.canvas, const Color(0xFF080B10));
    expect(dark.surface, const Color(0xFF111827));
    expect(dark.surfaceRaised, const Color(0xFF1A222F));
    expect(dark.textSecondary, const Color(0xFF8894A8));
    expect(dark.actionPrimary, const Color(0xFF8A94F5));
    expect(dark.stateStable, const Color(0xFF45C4B5));
    expect(dark.borderHairline, const Color(0xFF2D3748));
    expect(dark.accentAmber, const Color(0xFFE2A45C));
    expect(dark.accentNow, const Color(0xFFBCE85D));
  });

  test('shape lock: radii scale is 12/24/28', () {
    expect(TracendRadii.control, 12.0);
    expect(TracendRadii.card, 24.0);
    expect(TracendRadii.decision, 28.0);
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
