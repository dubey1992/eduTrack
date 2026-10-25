import 'package:flutter/material.dart';

/// The Teacher app's colours (docs/teacher-app.md).
///
/// Teal for the classroom and the app's own mark, amber for the ribbon in
/// the book - the one warm note, used sparingly. The driver app is blue, so
/// the two read apart on a launcher and in a hand.
abstract final class TeacherBrand {
  /// The primary, and the launcher icon's ground (android/app/src/teacher).
  static const teal = Color(0xFF0F766E);

  /// The far end of the splash and the hero's gradient.
  static const tealDeep = Color(0xFF115E59);

  /// The primary in dark mode: teal lifted until it reads on near-black.
  static const tealBright = Color(0xFF2DD4BF);

  /// A container in dark mode.
  static const tealNight = Color(0xFF123A37);

  /// A container in light mode, and the icons' soft circles.
  static const mint = Color(0xFFE6F4F1);

  /// The bookmark.
  static const amber = Color(0xFFF59E0B);

  /// The splash and the hero band, top left to bottom right.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, tealDeep],
  );
}
