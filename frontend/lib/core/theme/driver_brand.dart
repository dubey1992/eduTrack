import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// The Driver app's colours - since 2026-11-24 the School365AI navy with the
/// brand orange (slice B1, docs/mobile-apps-review.md).
///
/// Navy carries the buttons and the launcher tile, white on it: the strongest
/// contrast there is, for a phone read in sunlight on a bus. The orange is
/// the warm note on what is chosen, and leads at night.
abstract final class DriverBrand {
  /// The primary in light mode, and the launcher icon's ground.
  static const navy = BrandColors.deep;

  /// The orange: the primary in dark mode, and the shuttle's lamps.
  static const orange = BrandColors.orange;

  /// A chosen chip or row in light mode, and text on it.
  static const orangeSoft = Color(0xFFFFF1E2);
  static const orangeInk = Color(0xFF8A4508);

  /// A chosen chip or row in dark mode.
  static const orangeNight = Color(0xFF3B2A16);
}
