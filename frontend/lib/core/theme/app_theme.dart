import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// App theme. Palette is "Slate Monochrome" - near-black/white, high
/// contrast, almost no brand color - so status badges (green/red/amber)
/// carry the color instead of a branded hue. Minimal, editorial, and
/// culturally neutral for a product launching across multiple countries.
/// Respects the device's light/dark preference (ThemeMode.system in
/// main.dart) rather than forcing one look.
///
/// Typeface is Inter (via google_fonts) app-wide - the same font as the
/// public marketing page, applied here through [textTheme] plus every
/// sub-theme that carries its own hardcoded TextStyle (AppBar, buttons,
/// chips, DataTable, SnackBar), since those aren't guaranteed to inherit
/// fontFamily from textTheme the way a plain inherited Text widget does.
class AppTheme {
  const AppTheme._();

  // ---- Light ----
  static const _lightPrimary = Color(0xFF0F172A);
  static const _lightPrimarySoft = Color(0xFFE9ECF1);
  static const _lightBackground = Colors.white;
  static const _lightSurface = Colors.white;
  static const _lightText = Color(0xFF0F172A);
  static const _lightBorder = Color(0xFFCFD5DE);

  // ---- Dark (monochrome inverted, not a different hue) ----
  static const _darkPrimary = Color(0xFFE2E8F0);
  static const _darkPrimarySoft = Color(0xFF1E293B);
  static const _darkBackground = Color(0xFF0B0F1A);
  static const _darkSurface = Color(0xFF111827);
  static const _darkText = Color(0xFFF1F5F9);
  static const _darkBorder = Color(0xFF263042);

  static const radiusCard = 8.0;
  static const radiusControl = 6.0;

  static ThemeData light() => _build(
    brightness: Brightness.light,
    primary: _lightPrimary,
    primarySoft: _lightPrimarySoft,
    background: _lightBackground,
    surface: _lightSurface,
    text: _lightText,
    border: _lightBorder,
    appColors: AppColors.light,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    primary: _darkPrimary,
    primarySoft: _darkPrimarySoft,
    background: _darkBackground,
    surface: _darkSurface,
    text: _darkText,
    border: _darkBorder,
    appColors: AppColors.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color primarySoft,
    required Color background,
    required Color surface,
    required Color text,
    required Color border,
    required AppColors appColors,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      surface: surface,
      primaryContainer: primarySoft,
    );

    final baseTextTheme = Typography.material2021(platform: TargetPlatform.android).black
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          // A slightly heavier weight than default reads better for an admin
          // dashboard's headings, matching the prototype's font-weight: 850.
          titleLarge: TextStyle(color: text, fontWeight: FontWeight.w800),
          titleMedium: TextStyle(color: text, fontWeight: FontWeight.w700),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      extensions: [appColors],
      textTheme: GoogleFonts.interTextTheme(baseTextTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(color: text, fontSize: 20, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: GoogleFonts.inter(color: background, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        // Floating alone still stretches to the full window width on
        // desktop/web - capping `width` is what actually makes it read as a
        // small toast instead of a full-width bar.
        width: 360,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: primarySoft,
        labelStyle: GoogleFonts.inter(color: primary, fontWeight: FontWeight.w700, fontSize: 12),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(background),
        dataRowColor: WidgetStatePropertyAll(surface),
        headingTextStyle: GoogleFonts.inter(color: appColors.muted, fontWeight: FontWeight.w700, fontSize: 13),
        dividerThickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }
}
