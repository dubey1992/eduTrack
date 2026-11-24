import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// The Family app's colours (docs/parent-student-app.md, "Look and feel") -
/// since 2026-11-24 the violet of the School365AI logo's "AI" on the brand's
/// grounds (slice B1, docs/mobile-apps-review.md), with a coral heart as the
/// one warm note.
abstract final class FamilyBrand {
  /// The primary, and the launcher icon's ground (android/app/src/family).
  static const violet = Color(0xFF6D3BD8);

  /// Text on the violet's soft containers, and the far end of the gradient.
  static const violetDeep = Color(0xFF4C25A8);

  /// The primary in dark mode: violet lifted until it reads on the night navy.
  static const violetBright = BrandColors.logoVioletOnDark;

  /// A container in dark mode.
  static const violetNight = Color(0xFF2A2350);

  /// A container in light mode, and the icons' soft circles.
  static const mist = Color(0xFFF1ECFD);

  /// The page behind the cards, in light mode: the brand's off-white.
  static const ground = BrandColors.offWhite;

  /// Headings on light grounds: the brand navy.
  static const navy = BrandColors.deep;

  /// The heart in the mark.
  static const coral = Color(0xFFFB7185);

  /// The splash and the Today band, top left to bottom right: violet into
  /// the brand navy.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, BrandColors.navy],
  );

  /// Each child's own colour, so a parent of two never mixes them up: the
  /// first child is blue, the second violet, and so on, by their place in
  /// the list (which the server keeps in a fixed order).
  static const childColours = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0D9488),
    Color(0xFFEA580C),
    Color(0xFFDB2777),
  ];

  static Color childColour(int index) => childColours[index % childColours.length];
}
