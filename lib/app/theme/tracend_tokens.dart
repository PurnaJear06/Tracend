import 'package:flutter/material.dart';

/// Graphite + signal lime (DESIGN_SYSTEM.md §2). Semantic roles stay separate:
/// lime is the brand and action signal; recovery and status keep their own
/// colors.
@immutable
class TracendColors extends ThemeExtension<TracendColors> {
  const TracendColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.sheet,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.borderSubtle,
    required this.borderHairline,
    required this.actionPrimary,
    required this.actionOnPrimary,
    required this.accentSignal,
    required this.onAccentSignal,
    required this.accentSignalInk,
    required this.accentSignalRing,
    required this.accentSignalTint,
    required this.accentAmber,
    required this.stateStable,
    required this.stateGoodTint,
    required this.onStateGood,
    required this.stateAttention,
    required this.stateDanger,
    required this.focusRing,
    required this.scrim,
    required this.glass,
    required this.glassEdge,
    required this.shimmer,
    required this.mapOff,
    required this.mapBase,
  });

  static const light = TracendColors(
    canvas: Color(0xFFF4F4F1),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEDEDE9),
    sheet: Color(0xFFF9F9F7),
    textPrimary: Color(0xFF121311),
    textSecondary: Color(0xFF61635D),
    textTertiary: Color(0xFF8A8B86),
    borderSubtle: Color(0xFFE3E3DE),
    borderHairline: Color(0xFFECECE8),
    actionPrimary: Color(0xFF121311),
    actionOnPrimary: Color(0xFFF9F9F7),
    accentSignal: Color(0xFFC8F05A),
    onAccentSignal: Color(0xFF141A05),
    accentSignalInk: Color(0xFF4E6A00),
    accentSignalRing: Color(0xFF6B8F0E),
    accentSignalTint: Color(0x2996BE28),
    accentAmber: Color(0xFFA86A00),
    stateStable: Color(0xFF087A5A),
    stateGoodTint: Color(0x1F087A5A),
    onStateGood: Color(0xFFFFFFFF),
    stateAttention: Color(0xFFC24A3A),
    stateDanger: Color(0xFFB3392B),
    focusRing: Color(0xFF4E6A00),
    scrim: Color(0x47141412),
    glass: Color(0xBDFFFFFF),
    glassEdge: Color(0x0F000000),
    shimmer: Color(0x0D000000),
    mapOff: Color(0xFFD6D6D0),
    mapBase: Color(0xFFE6E6E1),
  );

  static const dark = TracendColors(
    canvas: Color(0xFF0C0D0E),
    surface: Color(0xFF18191B),
    surfaceRaised: Color(0xFF232427),
    sheet: Color(0xFF1A1B1D),
    textPrimary: Color(0xFFF4F4F1),
    textSecondary: Color(0xFF9C9D98),
    textTertiary: Color(0xFF6E6F6A),
    borderSubtle: Color(0xFF2A2B2F),
    borderHairline: Color(0xFF222326),
    actionPrimary: Color(0xFFF4F4F1),
    actionOnPrimary: Color(0xFF0C0D0E),
    accentSignal: Color(0xFFC8F05A),
    onAccentSignal: Color(0xFF141A05),
    accentSignalInk: Color(0xFFC8F05A),
    accentSignalRing: Color(0xFFC8F05A),
    accentSignalTint: Color(0x24C8F05A),
    accentAmber: Color(0xFFF2B544),
    stateStable: Color(0xFF4FD1A5),
    stateGoodTint: Color(0x244FD1A5),
    onStateGood: Color(0xFF062419),
    stateAttention: Color(0xFFF07F6E),
    stateDanger: Color(0xFFF07F6E),
    focusRing: Color(0xFFC8F05A),
    scrim: Color(0x73000000),
    glass: Color(0xB81E1F21),
    glassEdge: Color(0x14FFFFFF),
    shimmer: Color(0x0FFFFFFF),
    mapOff: Color(0xFF34363A),
    mapBase: Color(0xFF26272A),
  );

  /// Page background.
  final Color canvas;

  /// Cards and grouped rows.
  final Color surface;

  /// Controls and nested fills on a surface.
  final Color surfaceRaised;

  /// Bottom sheets and dialogs.
  final Color sheet;
  final Color textPrimary;
  final Color textSecondary;

  /// Placeholders and disabled text. Never for information that must be read.
  final Color textTertiary;
  final Color borderSubtle;
  final Color borderHairline;

  /// The primary pill fill: near-black in light, off-white in dark.
  final Color actionPrimary;
  final Color actionOnPrimary;

  /// Signal lime as a fill. Text on it uses [onAccentSignal]. Brand and action signal only (today, now, selected, new best, active tab, the primary progress ring); never means "good".
  final Color accentSignal;
  final Color onAccentSignal;

  /// Lime that is safe as text or an icon on canvas and surface.
  final Color accentSignalInk;

  /// Lime for rings and strokes on canvas and surface (3:1 or better).
  final Color accentSignalRing;

  /// Lime wash behind selected or new-best content.
  final Color accentSignalTint;

  /// Caution.
  final Color accentAmber;

  /// Good: recovery and success.
  final Color stateStable;
  final Color stateGoodTint;
  final Color onStateGood;

  /// Low: needs attention.
  final Color stateAttention;

  /// Destructive actions and errors.
  final Color stateDanger;
  final Color focusRing;
  final Color scrim;

  /// Translucent chrome: tab bar, toast, sheet scrim only.
  final Color glass;
  final Color glassEdge;

  /// Skeleton highlight.
  final Color shimmer;

  /// Muscle map: muscles not worked.
  final Color mapOff;

  /// Muscle map: body silhouette and separation lines.
  final Color mapBase;

  @override
  TracendColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? sheet,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? borderSubtle,
    Color? borderHairline,
    Color? actionPrimary,
    Color? actionOnPrimary,
    Color? accentSignal,
    Color? onAccentSignal,
    Color? accentSignalInk,
    Color? accentSignalRing,
    Color? accentSignalTint,
    Color? accentAmber,
    Color? stateStable,
    Color? stateGoodTint,
    Color? onStateGood,
    Color? stateAttention,
    Color? stateDanger,
    Color? focusRing,
    Color? scrim,
    Color? glass,
    Color? glassEdge,
    Color? shimmer,
    Color? mapOff,
    Color? mapBase,
  }) {
    return TracendColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      sheet: sheet ?? this.sheet,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderHairline: borderHairline ?? this.borderHairline,
      actionPrimary: actionPrimary ?? this.actionPrimary,
      actionOnPrimary: actionOnPrimary ?? this.actionOnPrimary,
      accentSignal: accentSignal ?? this.accentSignal,
      onAccentSignal: onAccentSignal ?? this.onAccentSignal,
      accentSignalInk: accentSignalInk ?? this.accentSignalInk,
      accentSignalRing: accentSignalRing ?? this.accentSignalRing,
      accentSignalTint: accentSignalTint ?? this.accentSignalTint,
      accentAmber: accentAmber ?? this.accentAmber,
      stateStable: stateStable ?? this.stateStable,
      stateGoodTint: stateGoodTint ?? this.stateGoodTint,
      onStateGood: onStateGood ?? this.onStateGood,
      stateAttention: stateAttention ?? this.stateAttention,
      stateDanger: stateDanger ?? this.stateDanger,
      focusRing: focusRing ?? this.focusRing,
      scrim: scrim ?? this.scrim,
      glass: glass ?? this.glass,
      glassEdge: glassEdge ?? this.glassEdge,
      shimmer: shimmer ?? this.shimmer,
      mapOff: mapOff ?? this.mapOff,
      mapBase: mapBase ?? this.mapBase,
    );
  }

  @override
  TracendColors lerp(TracendColors? other, double t) {
    if (other is! TracendColors) return this;
    return TracendColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderHairline: Color.lerp(borderHairline, other.borderHairline, t)!,
      actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
      actionOnPrimary: Color.lerp(actionOnPrimary, other.actionOnPrimary, t)!,
      accentSignal: Color.lerp(accentSignal, other.accentSignal, t)!,
      onAccentSignal: Color.lerp(onAccentSignal, other.onAccentSignal, t)!,
      accentSignalInk: Color.lerp(accentSignalInk, other.accentSignalInk, t)!,
      accentSignalRing: Color.lerp(
        accentSignalRing,
        other.accentSignalRing,
        t,
      )!,
      accentSignalTint: Color.lerp(
        accentSignalTint,
        other.accentSignalTint,
        t,
      )!,
      accentAmber: Color.lerp(accentAmber, other.accentAmber, t)!,
      stateStable: Color.lerp(stateStable, other.stateStable, t)!,
      stateGoodTint: Color.lerp(stateGoodTint, other.stateGoodTint, t)!,
      onStateGood: Color.lerp(onStateGood, other.onStateGood, t)!,
      stateAttention: Color.lerp(stateAttention, other.stateAttention, t)!,
      stateDanger: Color.lerp(stateDanger, other.stateDanger, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassEdge: Color.lerp(glassEdge, other.glassEdge, t)!,
      shimmer: Color.lerp(shimmer, other.shimmer, t)!,
      mapOff: Color.lerp(mapOff, other.mapOff, t)!,
      mapBase: Color.lerp(mapBase, other.mapBase, t)!,
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
  static const sheet = 28.0;
  static const pill = 999.0;
}

abstract final class TracendFonts {
  /// Display type: titles, headings and large numbers.
  static const displayFamily = 'Archivo';

  /// Numbers in data rows and readouts. Always paired with tabular figures.
  static const numericFamily = 'Archivo SemiCondensed';
}

abstract final class TracendMotion {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const emphasized = Duration(milliseconds: 360);
  static const curve = Curves.easeOutCubic;

  /// A soft spring-like overshoot for things that settle into place.
  static const settle = Cubic(0.3, 1.25, 0.5, 1);
}
