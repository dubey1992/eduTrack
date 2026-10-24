import 'package:flutter/material.dart';

import '../../../marketing/presentation/marketing_colors.dart';

/// The colours of the public sign-in screens, in both themes.
///
/// These screens carry the product's public face - the marketing blue, the
/// white card - rather than the admin theme's monochrome, and until now
/// they carried it as constants: light on every phone, whatever the phone
/// was set to. On a dark phone that gave a white card with the theme's dark
/// input boxes sitting inside it, which is how the problem was found. So
/// the same names, chosen once per brightness; a screen asks for the
/// palette in `build` and never names a constant of its own.
///
/// The light set *is* [MarketingColors], so the web's homepage and its
/// sign-in still match. The dark set keeps the blue - it is the brand - and
/// moves everything else onto the admin theme's dark greys so the card,
/// the fields and the page behind them are one surface again.
class AuthPalette {
  const AuthPalette._({
    required this.primary,
    required this.primaryLight,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.background,
    required this.surface,
    required this.border,
    required this.teal,
    required this.danger,
    required this.shadow,
  });

  static AuthPalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const light = AuthPalette._(
    primary: MarketingColors.primary,
    primaryLight: MarketingColors.primaryLight,
    text: MarketingColors.text,
    muted: MarketingColors.muted,
    subtle: MarketingColors.subtle,
    background: MarketingColors.background,
    surface: MarketingColors.surface,
    border: MarketingColors.border,
    teal: MarketingColors.teal,
    danger: MarketingColors.danger,
    shadow: Color(0x14000000),
  );

  static const dark = AuthPalette._(
    primary: Color(0xFF3B82F6),
    primaryLight: Color(0xFF1E3A8A),
    text: Color(0xFFF1F5F9),
    muted: Color(0xFFCBD5E1),
    subtle: Color(0xFF94A3B8),
    background: Color(0xFF0B0F1A),
    surface: Color(0xFF111827),
    border: Color(0xFF263042),
    teal: Color(0xFF2DD4BF),
    danger: Color(0xFFF87171),
    shadow: Color(0x66000000),
  );

  final Color primary;
  final Color primaryLight;
  final Color text;
  final Color muted;
  final Color subtle;
  final Color background;
  final Color surface;
  final Color border;
  final Color teal;
  final Color danger;

  /// The card's drop shadow. Deeper in the dark theme, where a soft grey
  /// shadow would vanish into the page.
  final Color shadow;
}
