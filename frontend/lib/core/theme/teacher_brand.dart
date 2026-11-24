import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// The Staff app's colours (docs/teacher-app.md) - since 2026-11-24 the
/// School365AI brand's own (slice B1, docs/mobile-apps-review.md).
///
/// Teal for the app and its mark, running into the brand navy on the splash
/// and the hero band; the brand orange for the ribbon in the book - the one
/// warm note, used sparingly.
abstract final class TeacherBrand {
  /// The primary, and the launcher icon's ground (android/app/src/teacher).
  static const teal = BrandColors.teal;

  /// Shadows under the teal tile.
  static const tealDeep = BrandColors.tealInk;

  /// The primary in dark mode: teal lifted until it reads on the night navy.
  static const tealBright = BrandColors.nightTeal;

  /// A container in dark mode.
  static const tealNight = BrandColors.nightMint;

  /// A container in light mode, and the icons' soft circles.
  static const mint = BrandColors.mint;

  /// The bookmark.
  static const amber = BrandColors.orange;

  /// The splash and the hero band, top left to bottom right: teal into navy,
  /// as on the website's hero.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, BrandColors.navy],
  );
}
