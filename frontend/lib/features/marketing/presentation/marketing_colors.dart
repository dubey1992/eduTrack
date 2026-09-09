import 'package:flutter/material.dart';

/// Standalone palette for the public marketing site - deliberately not the
/// app's internal Slate Monochrome [AppTheme]. A sales/landing page and an
/// internal admin tool conventionally carry different visual identities;
/// this mirrors the source prototype's own CSS custom properties
/// (docs/marketing/edusync_marketing_page_prototype.html) 1:1.
class MarketingColors {
  const MarketingColors._();

  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const primaryLight = Color(0xFFDBEAFE);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF475569);
  static const subtle = Color(0xFF64748B);
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const border = Color(0xFFE2E8F0);
  static const teal = Color(0xFF0D9488);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFDC2626);

  /// The feature-grid icon colors, in the prototype's own order.
  static const featureIconColors = [
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFF4F46E5),
    Color(0xFFF59E0B),
    Color(0xFF0D9488),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFFF97316),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
  ];
}

/// Breakpoints matching the prototype's own `@media` queries - distinct
/// from the admin app's [Breakpoints] (1100px sidebar cutoff), since this
/// page has its own layout rhythm.
class MarketingBreakpoints {
  const MarketingBreakpoints._();

  static const tablet = 900.0;
  static const mobile = 560.0;
}
