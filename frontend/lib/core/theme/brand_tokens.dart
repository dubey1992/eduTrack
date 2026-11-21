import 'package:flutter/material.dart';

/// The School365AI palette (Homepage V3, 2026-11-21): the public website's
/// colours, so the web app and school365ai.com read as one product. The
/// website's stylesheet (backend-python/school/public_site_assets/site.css)
/// holds the same values; change them together.
///
/// Screens never name these directly. They reach them through the theme
/// ([AppTheme.light] and [AppTheme.dark]) and the [ThemeExtension]s built
/// from it, so the dark theme gets its own set rather than the light one.
abstract final class BrandColors {
  // ---- The brand colours ----
  /// Dark grounds: the sidebar, the sign-in panel.
  static const deep = Color(0xFF0D2140);

  /// Headings and body text.
  static const navy = Color(0xFF142A49);

  /// Actions: buttons, links, the focused field, the selected item.
  static const teal = Color(0xFF087E79);

  /// A button's hover and pressed shade.
  static const tealInk = Color(0xFF066A66);

  /// Soft fills: icon tiles, selected rows, badges.
  static const mint = Color(0xFFE6F7F2);

  /// The warm accent, used sparingly.
  static const orange = Color(0xFFFFB76A);

  /// The page behind the cards inside the app.
  static const offWhite = Color(0xFFF7F9FC);

  // ---- Their working shades ----
  /// Body text.
  static const ink = navy;

  /// Secondary text. Dark enough for 4.5:1 on white and on [offWhite].
  static const muted = Color(0xFF5B6C84);

  /// Hairlines between cards, rows and fields.
  static const line = Color(0xFFE2E9F0);

  /// A field's border, a little firmer than a card's.
  static const outline = Color(0xFFC9D6E1);

  /// The page behind the cards.
  static const workspace = offWhite;

  // ---- The dark theme's ground ----
  static const night = Color(0xFF0A1628);
  static const nightSurface = Color(0xFF11223A);
  static const nightLine = Color(0xFF24395A);
  static const nightOutline = Color(0xFF3A5274);
  static const nightText = Color(0xFFE8EEF6);
  static const nightMuted = Color(0xFFA9B8CB);

  /// The teal the dark theme acts in: light enough to read on [night].
  static const nightTeal = Color(0xFF5FD3C8);

  /// A soft teal fill on [night].
  static const nightMint = Color(0xFF123B44);

  /// "365" and "AI" of the wordmark on a dark ground, from the logo's own
  /// teal and violet, lifted so they read on [deep].
  static const logoTealOnDark = Color(0xFF5FD3C8);
  static const logoVioletOnDark = Color(0xFFB79CFF);
}

/// The web app's corner radii, from the website's cards and fields.
abstract final class BrandRadii {
  static const card = 16.0;
  static const control = 10.0;
  static const dialog = 20.0;
}

/// The logo files (assets/brand), drawn from the School365AI logo.
abstract final class BrandAssets {
  /// The whole logo - the S mark and "School365AI" - for a light ground.
  static const logo = 'assets/brand/logo-full.png';

  /// The S mark alone: the book, the cap and the S.
  static const mark = 'assets/brand/logo-mark.png';
}
