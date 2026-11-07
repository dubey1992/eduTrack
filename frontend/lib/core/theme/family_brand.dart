import 'package:flutter/material.dart';

/// The Family app's colours (docs/parent-student-app.md, "Look and feel").
///
/// The School365ai blue, the website's, with a coral heart as the one warm
/// note. Navy for headings, a soft off-white ground.
abstract final class FamilyBrand {
  /// The primary, and the launcher icon's ground (android/app/src/family).
  static const blue = Color(0xFF2563EB);

  /// The far end of the splash and the Today band.
  static const blueDeep = Color(0xFF1D4ED8);

  /// The primary in dark mode: blue lifted until it reads on near-black.
  static const blueBright = Color(0xFF60A5FA);

  /// A container in dark mode.
  static const blueNight = Color(0xFF172554);

  /// A container in light mode, and the icons' soft circles.
  static const mist = Color(0xFFEFF4FF);

  /// The page behind the cards, in light mode.
  static const ground = Color(0xFFF6F8FC);

  /// Headings on light grounds.
  static const navy = Color(0xFF0F172A);

  /// The heart in the mark.
  static const coral = Color(0xFFFB7185);

  /// The splash and the Today band, top left to bottom right.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, blueDeep],
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
