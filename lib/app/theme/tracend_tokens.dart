import 'package:flutter/material.dart';

@immutable
class TracendColors extends ThemeExtension<TracendColors> {
  const TracendColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderSubtle,
    required this.actionPrimary,
    required this.actionOnPrimary,
    required this.stateStable,
    required this.stateAttention,
    required this.stateDanger,
    required this.focusRing,
    required this.scrim,
  });

  static const light = TracendColors(
    canvas: Color(0xFFF3F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF9FBFC),
    textPrimary: Color(0xFF10151D),
    textSecondary: Color(0xFF556170),
    borderSubtle: Color(0xFFDCE2E8),
    actionPrimary: Color(0xFF4A57E8),
    actionOnPrimary: Color(0xFFFFFFFF),
    stateStable: Color(0xFF00796B),
    stateAttention: Color(0xFFC43C31),
    stateDanger: Color(0xFFA92F28),
    focusRing: Color(0xFF4A57E8),
    scrim: Color(0x99090D14),
  );

  static const dark = TracendColors(
    canvas: Color(0xFF090D14),
    surface: Color(0xFF121925),
    surfaceRaised: Color(0xFF182130),
    textPrimary: Color(0xFFF4F7FB),
    textSecondary: Color(0xFFAAB5C5),
    borderSubtle: Color(0xFF293446),
    actionPrimary: Color(0xFF9BA5FF),
    actionOnPrimary: Color(0xFF10151D),
    stateStable: Color(0xFF59D6C7),
    stateAttention: Color(0xFFFF887D),
    stateDanger: Color(0xFFFF887D),
    focusRing: Color(0xFF9BA5FF),
    scrim: Color(0xB3090D14),
  );

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderSubtle;
  final Color actionPrimary;
  final Color actionOnPrimary;
  final Color stateStable;
  final Color stateAttention;
  final Color stateDanger;
  final Color focusRing;
  final Color scrim;

  @override
  TracendColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? textPrimary,
    Color? textSecondary,
    Color? borderSubtle,
    Color? actionPrimary,
    Color? actionOnPrimary,
    Color? stateStable,
    Color? stateAttention,
    Color? stateDanger,
    Color? focusRing,
    Color? scrim,
  }) {
    return TracendColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      actionPrimary: actionPrimary ?? this.actionPrimary,
      actionOnPrimary: actionOnPrimary ?? this.actionOnPrimary,
      stateStable: stateStable ?? this.stateStable,
      stateAttention: stateAttention ?? this.stateAttention,
      stateDanger: stateDanger ?? this.stateDanger,
      focusRing: focusRing ?? this.focusRing,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  TracendColors lerp(TracendColors? other, double t) {
    if (other is! TracendColors) return this;
    return TracendColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
      actionOnPrimary: Color.lerp(actionOnPrimary, other.actionOnPrimary, t)!,
      stateStable: Color.lerp(stateStable, other.stateStable, t)!,
      stateAttention: Color.lerp(stateAttention, other.stateAttention, t)!,
      stateDanger: Color.lerp(stateDanger, other.stateDanger, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

extension TracendThemeContext on BuildContext {
  TracendColors get tracendColors => Theme.of(this).extension<TracendColors>()!;
}

abstract final class TracendSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const gutter = 20.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class TracendRadii {
  static const control = 12.0;
  static const card = 20.0;
  static const decision = 28.0;
  static const navigation = 28.0;
}

abstract final class TracendMotion {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const emphasized = Duration(milliseconds: 360);
  static const curve = Curves.easeOutCubic;
}
