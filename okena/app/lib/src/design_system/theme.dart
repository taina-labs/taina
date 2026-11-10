import 'package:flutter/material.dart';

import 'tokens.dart';

/// The single Tainá theme: dark, Material 3, built from the semantic tokens.
///
/// Feature agents wire it once at the app root:
///
/// ```dart
/// MaterialApp(theme: TainaTheme.data, ...)
/// ```
///
/// Widgets still read colors and type from [TainaPalette] and
/// [TainaTypography]; this class only makes the Material defaults agree with
/// those tokens (scaffold, dialogs, sheets, snack bars, app bars, buttons).
abstract final class TainaTheme {
  static final ThemeData data = _build();

  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: TainaPalette.brandPrimary,
    onPrimary: TainaPalette.textOnBrand,
    primaryContainer: TainaPalette.surfaceRaised,
    onPrimaryContainer: TainaPalette.textPrimary,
    secondary: TainaPalette.brandEmber,
    onSecondary: TainaPalette.textOnBrand,
    secondaryContainer: TainaPalette.serviceMaracaSoft,
    onSecondaryContainer: TainaPalette.textPrimary,
    tertiary: TainaPalette.serviceNhaman,
    onTertiary: TainaPalette.textOnBrand,
    error: TainaPalette.feedbackError,
    onError: TainaPrimitives.star50,
    surface: TainaPalette.surfaceDefault,
    onSurface: TainaPalette.textPrimary,
    surfaceDim: TainaPalette.surfaceDim,
    surfaceBright: TainaPalette.surfaceHigh,
    surfaceContainerLowest: TainaPalette.bgDeep,
    surfaceContainerLow: TainaPalette.bgApp,
    surfaceContainer: TainaPalette.surfaceDefault,
    surfaceContainerHigh: TainaPalette.surfaceRaised,
    surfaceContainerHighest: TainaPalette.surfaceHigh,
    onSurfaceVariant: TainaPalette.textMuted,
    outline: TainaPalette.borderDefault,
    outlineVariant: TainaPalette.borderSubtle,
    shadow: TainaPrimitives.night950,
    scrim: TainaPrimitives.night950,
    inverseSurface: TainaPrimitives.star50,
    onInverseSurface: TainaPrimitives.night900,
    inversePrimary: TainaPrimitives.dawn700,
    surfaceTint: Colors.transparent,
  );

  static ThemeData _build() {
    final TextTheme textTheme = TainaTypography.textTheme.apply(
      bodyColor: TainaPalette.textPrimary,
      displayColor: TainaPalette.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      splashFactory: InkRipple.splashFactory,
      fontFamily: TainaFonts.body,
      scaffoldBackgroundColor: TainaPalette.bgApp,
      canvasColor: TainaPalette.bgApp,
      dividerColor: TainaPalette.borderSubtle,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: TainaPalette.textSecondary),
      appBarTheme: AppBarThemeData(
        backgroundColor: TainaPalette.bgApp,
        foregroundColor: TainaPalette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: TainaSizes.appbar,
        centerTitle: false,
        titleTextStyle: TainaTypography.h3.copyWith(
          color: TainaPalette.textPrimary,
        ),
        iconTheme: const IconThemeData(
          color: TainaPalette.textPrimary,
          size: 24,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TainaPalette.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: TainaRadii.xlAll),
        titleTextStyle: TainaTypography.h3.copyWith(
          color: TainaPalette.textPrimary,
        ),
        contentTextStyle: TainaTypography.body.copyWith(
          color: TainaPalette.textSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TainaPalette.surfaceDefault,
        modalBackgroundColor: TainaPalette.surfaceDefault,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: TainaPalette.surfaceScrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TainaRadii.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TainaPalette.surfaceHigh,
        contentTextStyle: TainaTypography.bodySm.copyWith(
          color: TainaPalette.textPrimary,
        ),
        actionTextColor: TainaPalette.brandPrimary,
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: TainaPalette.borderSubtle,
        thickness: TainaSizes.hairline,
        space: TainaSizes.hairline,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TainaPalette.brandPrimary,
        linearTrackColor: TainaPalette.surfaceRaised,
        linearMinHeight: TainaSizes.progress,
        circularTrackColor: TainaPalette.surfaceRaised,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: TainaPalette.brandPrimary,
        selectionColor: Color(0x52F2A65A),
        selectionHandleColor: TainaPalette.brandPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TainaPalette.brandPrimary,
          foregroundColor: TainaPalette.textOnBrand,
          minimumSize: const Size(0, TainaSizes.controlMd),
          padding: const EdgeInsets.symmetric(
            horizontal: TainaSpacing.space4,
            vertical: TainaSpacing.space3,
          ),
          shape: const RoundedRectangleBorder(borderRadius: TainaRadii.mdAll),
          textStyle: TainaTypography.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TainaPalette.textPrimary,
          minimumSize: const Size(0, TainaSizes.controlMd),
          padding: const EdgeInsets.symmetric(
            horizontal: TainaSpacing.space4,
            vertical: TainaSpacing.space3,
          ),
          shape: const RoundedRectangleBorder(borderRadius: TainaRadii.mdAll),
          side: const BorderSide(
            color: TainaPalette.borderDefault,
            width: TainaSizes.hairline,
          ),
          textStyle: TainaTypography.label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TainaPalette.brandPrimary,
          minimumSize: const Size(0, TainaSizes.touch),
          shape: const RoundedRectangleBorder(borderRadius: TainaRadii.mdAll),
          textStyle: TainaTypography.label,
        ),
      ),
    );
  }
}
