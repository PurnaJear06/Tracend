import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

abstract final class TracendTheme {
  static ThemeData get light => _build(Brightness.light, TracendColors.light);
  static ThemeData get dark => _build(Brightness.dark, TracendColors.dark);

  /// Numbers in rows and readouts: Archivo SemiCondensed with tabular figures,
  /// so digits line up and do not jitter while they change.
  static TextStyle numeric(
    TracendColors colors, {
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
  }) => TextStyle(
    fontFamily: TracendFonts.numericFamily,
    color: color ?? colors.textPrimary,
    fontSize: fontSize,
    height: 1.2,
    fontWeight: fontWeight,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Small secondary data text (timestamps, units, footnotes with numbers).
  static TextStyle dataUtility(TracendColors colors) => numeric(
    colors,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: colors.textSecondary,
  ).copyWith(height: 18 / 13);

  /// Small label above a group of content. Sentence case: write the label as
  /// it should read. Caps are kept only where they encode something real,
  /// such as weekday letters.
  static TextStyle labelCaps(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(color: color);

  static ThemeData _build(Brightness brightness, TracendColors colors) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.actionPrimary,
        onPrimary: colors.actionOnPrimary,
        secondary: colors.accentSignal,
        onSecondary: colors.onAccentSignal,
        tertiary: colors.stateStable,
        onTertiary: colors.onStateGood,
        error: colors.stateDanger,
        onError: colors.actionOnPrimary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        onSurfaceVariant: colors.textSecondary,
        surfaceContainerHighest: colors.surfaceRaised,
        surfaceContainerHigh: colors.surfaceRaised,
        surfaceContainer: colors.surface,
        surfaceContainerLow: colors.surface,
        outline: colors.borderSubtle,
        outlineVariant: colors.borderHairline,
        shadow: Colors.black,
        scrim: colors.scrim,
      ),
      extensions: [colors],
    );

    TextStyle display(
      double size,
      double height,
      FontWeight weight,
      double tracking,
    ) => TextStyle(
      fontFamily: TracendFonts.displayFamily,
      color: colors.textPrimary,
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: tracking,
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: display(56, 1.0, FontWeight.w800, -1.6),
      displayMedium: display(44, 1.02, FontWeight.w800, -1.2),
      displaySmall: display(34, 1.06, FontWeight.w800, -0.8),
      headlineMedium: display(28, 1.1, FontWeight.w800, -0.6),
      headlineSmall: display(24, 1.15, FontWeight.w700, -0.4),
      titleLarge: display(20, 1.2, FontWeight.w700, -0.2),
      titleMedium: display(17, 1.3, FontWeight.w600, 0),
      titleSmall: TextStyle(
        color: colors.textPrimary,
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: colors.textPrimary,
        fontSize: 17,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        color: colors.textSecondary,
        fontSize: 15,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        color: colors.textSecondary,
        fontSize: 13,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        color: colors.textPrimary,
        fontSize: 16,
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
      labelSmall: TextStyle(
        color: colors.textSecondary,
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );

    const pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(TracendRadii.pill)),
    );
    final control = BorderRadius.circular(TracendRadii.control);
    final buttonText = textTheme.labelLarge!;

    return base.copyWith(
      textTheme: textTheme,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: colors.textPrimary,
        scaffoldBackgroundColor: colors.canvas,
        barBackgroundColor: colors.glass,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TracendRadii.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.actionPrimary,
          foregroundColor: colors.actionOnPrimary,
          disabledBackgroundColor: colors.surfaceRaised,
          disabledForegroundColor: colors.textTertiary,
          minimumSize: const Size(44, 52),
          padding: const EdgeInsets.symmetric(horizontal: TracendSpacing.lg),
          shape: pill,
          textStyle: buttonText,
          elevation: 0,
          splashFactory: NoSplash.splashFactory,
          animationDuration: TracendMotion.quick,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: colors.surfaceRaised,
          foregroundColor: colors.textPrimary,
          disabledForegroundColor: colors.textTertiary,
          minimumSize: const Size(44, 52),
          padding: const EdgeInsets.symmetric(horizontal: TracendSpacing.lg),
          side: BorderSide.none,
          shape: pill,
          textStyle: buttonText,
          splashFactory: NoSplash.splashFactory,
          animationDuration: TracendMotion.quick,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(44, 44),
          shape: pill,
          textStyle: buttonText.copyWith(fontSize: 15),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(44, 44),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceRaised,
        hintStyle: textTheme.bodyLarge!.copyWith(color: colors.textTertiary),
        labelStyle: textTheme.bodyMedium,
        floatingLabelStyle: textTheme.labelMedium,
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall!.copyWith(color: colors.stateDanger),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: colors.focusRing, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: colors.stateDanger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: control,
          borderSide: BorderSide(color: colors.stateDanger, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceRaised,
        selectedColor: colors.accentSignal,
        disabledColor: colors.surfaceRaised,
        labelStyle: textTheme.labelSmall!.copyWith(color: colors.textPrimary),
        secondaryLabelStyle: textTheme.labelSmall!.copyWith(
          color: colors.onAccentSignal,
        ),
        checkmarkColor: colors.onAccentSignal,
        side: BorderSide.none,
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TracendSpacing.md,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onAccentSignal
              : colors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentSignal
              : colors.surfaceRaised,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentSignal
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(colors.onAccentSignal),
        side: BorderSide(color: colors.textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accentSignalRing
              : colors.textSecondary,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.accentSignalRing,
        inactiveTrackColor: colors.surfaceRaised,
        thumbColor: colors.textPrimary,
        overlayColor: colors.accentSignalTint,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.sheet,
        modalBackgroundColor: colors.sheet,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colors.scrim,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        dragHandleColor: colors.borderSubtle,
        dragHandleSize: const Size(36, 5),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TracendRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.sheet,
        surfaceTintColor: Colors.transparent,
        barrierColor: colors.scrim,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TracendRadii.decision),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.textPrimary,
        contentTextStyle: textTheme.bodyMedium!.copyWith(color: colors.canvas),
        actionTextColor: colors.canvas,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: control),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(borderRadius: control),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall!.copyWith(color: colors.canvas),
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderHairline,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accentSignalRing,
        linearTrackColor: colors.surfaceRaised,
        circularTrackColor: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(TracendRadii.pill),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accentSignalRing,
        selectionColor: colors.accentSignalTint,
        selectionHandleColor: colors.accentSignalRing,
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
