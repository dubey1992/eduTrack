import 'package:flutter/material.dart';

/// The Warm Editorial palette (2026-11-14): the public website's colours,
/// so the web app and school365ai.com read as one product. The website's
/// stylesheet (backend-python/school/public_site_assets/site.css) holds the
/// same values; change them together.
///
/// Screens never name these directly. They reach them through the theme
/// ([AppTheme.light] and [AppTheme.dark]) and the [ThemeExtension]s built
/// from it, so the dark theme gets its own set rather than the light one.
abstract final class BrandColors {
  // ---- The five brand colours ----
  static const plum = Color(0xFF492B4E);
  static const rose = Color(0xFFA33D63);
  static const coral = Color(0xFFE69568);
  static const ivory = Color(0xFFFFF8EF);
  static const blush = Color(0xFFF7E8F0);

  // ---- Their working shades ----
  /// The deepest plum: the sidebar's hover, the login panel's shadow.
  static const deepPlum = Color(0xFF321C37);

  /// Body text: a plum-tinted near-black rather than a neutral grey.
  static const ink = Color(0xFF342A38);

  /// Secondary text. Dark enough for 4.5:1 on white and on ivory.
  static const muted = Color(0xFF6F6574);

  /// Hairlines between cards, rows and fields.
  static const line = Color(0xFFEADFE5);

  /// The page behind the cards inside the app: a whisper of blush, so the
  /// white cards stand off it without a heavy shadow.
  static const workspace = Color(0xFFFCF8F8);

  // ---- The dark theme's ground ----
  static const night = Color(0xFF1B1320);
  static const nightSurface = Color(0xFF261A2B);
  static const nightLine = Color(0xFF3B2B41);
  static const nightText = Color(0xFFF5ECF2);
  static const nightMuted = Color(0xFFBDAFC1);

  /// The plum the dark theme acts in: light enough to read on [night].
  static const nightRose = Color(0xFFF0A7C3);

  /// The mark's gradient: rose at the top left to coral at the bottom right,
  /// as in the website's header and the favicon.
  static const markGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB24667), Color(0xFFE8916F)],
  );
}

/// The web app's corner radii, from the website's cards and fields.
abstract final class BrandRadii {
  static const card = 18.0;
  static const control = 12.0;
  static const dialog = 22.0;
}
