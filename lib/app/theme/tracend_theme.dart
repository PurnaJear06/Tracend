import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

abstract final class TracendTheme {
  static ThemeData get light => _build(Brightness.light, TracendColors.light);
  static ThemeData get dark => _build(Brightness.dark, TracendColors.dark);

  static ThemeData _build(Brightness brightness, TracendColors colors) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: '.SF Pro Text',
      scaffoldBackgroundColor: colors.canvas,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.actionPrimary,
        onPrimary: colors.actionOnPrimary,
        secondary: colors.stateStable,
        onSecondary: colors.canvas,
        error: colors.stateDanger,
        onError: colors.actionOnPrimary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        outline: colors.borderSubtle,
        shadow: Colors.black,
      ),
      extensions: [colors],
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: TextStyle(
        color: colors.textPrimary,
        fontSize: 32,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: colors.textPrimary,
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        color: colors.textPrimary,
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: colors.textPrimary,
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: colors.textPrimary,
        fontSize: 17,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        color: colors.textSecondary,
        fontSize: 15,
        height: 1.5,
      ),
      labelLarge: TextStyle(
        color: colors.textPrimary,
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: colors.textSecondary,
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: textTheme.headlineMedium,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TracendRadii.card),
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 52),
          padding: const EdgeInsets.symmetric(horizontal: TracendSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TracendRadii.control),
          ),
          textStyle: textTheme.labelLarge,
          elevation: 0,
          animationDuration: TracendMotion.quick,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 52),
          side: BorderSide(color: colors.borderSubtle),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TracendRadii.control),
          ),
          animationDuration: TracendMotion.quick,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colors.surface,
        indicatorColor: colors.actionPrimary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            fontSize: 12,
            color: states.contains(WidgetState.selected)
                ? colors.actionPrimary
                : colors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.actionPrimary
                : colors.textSecondary,
            size: 23,
          );
        }),
      ),
      dividerTheme: DividerThemeData(color: colors.borderSubtle, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.actionPrimary,
        linearTrackColor: colors.borderSubtle,
        borderRadius: BorderRadius.circular(999),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
