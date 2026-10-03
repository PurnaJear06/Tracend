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

  test('light secondary text meets AA on canvas', () {
    const light = TracendColors.light;
    expect(
      _contrast(light.textSecondary, light.canvas),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('dark graphics tokens meet the 3:1 graphics threshold on canvas', () {
    final dark = TracendColors.dark;
    for (final c in [
      dark.actionPrimary,
      dark.stateStable,
      dark.accentAmber,
      dark.accentSignalInk,
      dark.accentSignalRing,
      dark.stateAttention,
      dark.stateDanger,
    ]) {
      expect(_contrast(c, dark.canvas), greaterThanOrEqualTo(3));
      expect(_contrast(c, dark.surface), greaterThanOrEqualTo(3));
    }
  });

  test('palette A: graphite and signal lime', () {
    expect(TracendColors.dark.canvas, const Color(0xFF0C0D0E));
    expect(TracendColors.dark.surface, const Color(0xFF18191B));
    expect(TracendColors.dark.accentSignal, const Color(0xFFC8F05A));
    expect(TracendColors.light.canvas, const Color(0xFFF4F4F1));
    expect(TracendColors.light.accentSignalInk, const Color(0xFF4E6A00));
  });

  test('lime text is only ever ink-safe: lime fills carry dark ink', () {
    for (final colors in [TracendColors.light, TracendColors.dark]) {
      expect(
        _contrast(colors.onAccentSignal, colors.accentSignal),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(colors.accentSignalInk, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(colors.actionOnPrimary, colors.actionPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(colors.onStateGood, colors.stateStable),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('primary text meets AA on canvas in both themes', () {
    for (final colors in [TracendColors.light, TracendColors.dark]) {
      expect(
        _contrast(colors.textPrimary, colors.canvas),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('button label meets AA on the primary action fill in both themes', () {
    for (final colors in [TracendColors.light, TracendColors.dark]) {
      expect(
        _contrast(colors.actionOnPrimary, colors.actionPrimary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('light graphics tokens meet the 3:1 graphics threshold', () {
    const light = TracendColors.light;
    for (final c in [
      light.actionPrimary,
      light.stateStable,
      light.accentAmber,
      light.accentSignalInk,
      light.accentSignalRing,
      light.stateAttention,
      light.stateDanger,
    ]) {
      expect(_contrast(c, light.canvas), greaterThanOrEqualTo(3));
      expect(_contrast(c, light.surface), greaterThanOrEqualTo(3));
    }
  });

  test(
    'shape lock: inputs 12, cards 20, sheets 28, buttons and chips pill',
    () {
      expect(TracendRadii.control, 12.0);
      expect(TracendRadii.card, 20.0);
      expect(TracendRadii.decision, 28.0);
      expect(TracendRadii.sheet, 28.0);
      expect(TracendRadii.pill, 999.0);
    },
  );
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
