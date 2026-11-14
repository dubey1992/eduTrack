import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/brand_tokens.dart';
import '../../../marketing/presentation/marketing_colors.dart';

/// The colours of the public sign-in screens, in both themes.
///
/// A [ThemeExtension], so each app carries its own (2026-11-14): the web app
/// signs in under the website's Warm Editorial colours ([editorialLight],
/// [editorialDark]), while the Driver and Teacher apps, which reuse some of
/// these screens on a phone, keep the blue they launched with ([light],
/// [dark]). A screen asks for the palette in `build` with [AuthPalette.of]
/// and never names a constant of its own - a constant was how a dark phone
/// once got a white card with dark input boxes inside it.
class AuthPalette extends ThemeExtension<AuthPalette> {
  const AuthPalette._({
    required this.primary,
    this.onPrimary = Colors.white,
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
    this.serifHeadings = false,
  });

  /// The current theme's palette. A theme without one - a widget test that
  /// pumps a bare MaterialApp - gets the web app's, by brightness.
  static AuthPalette of(BuildContext context) {
    final theme = Theme.of(context);

    return theme.extension<AuthPalette>() ?? (theme.brightness == Brightness.dark ? editorialDark : editorialLight);
  }

  /// The web app's sign-in: plum and rose on warm ivory.
  static const editorialLight = AuthPalette._(
    primary: BrandColors.plum,
    primaryLight: BrandColors.blush,
    text: BrandColors.ink,
    muted: BrandColors.muted,
    subtle: BrandColors.muted,
    background: BrandColors.ivory,
    surface: Colors.white,
    border: BrandColors.line,
    teal: Color(0xFF277B62),
    danger: Color(0xFFB03A4A),
    shadow: Color(0x1A492B4E),
    serifHeadings: true,
  );

  static const editorialDark = AuthPalette._(
    primary: BrandColors.nightRose,
    onPrimary: BrandColors.deepPlum,
    primaryLight: Color(0xFF3A2440),
    text: BrandColors.nightText,
    muted: BrandColors.nightMuted,
    subtle: BrandColors.nightMuted,
    background: BrandColors.night,
    surface: BrandColors.nightSurface,
    border: BrandColors.nightLine,
    teal: Color(0xFF6FD3B0),
    danger: Color(0xFFF59AA5),
    shadow: Color(0x66000000),
    serifHeadings: true,
  );

  /// The phone apps' sign-in: the blue the website had before the redesign.
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

  /// Text and spinners on a [primary] button.
  final Color onPrimary;
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

  /// Whether headings are set in the website's serif (the web app) or in
  /// the text face, bold (the phone apps).
  final bool serifHeadings;

  /// A screen's heading at [fontSize], in this palette's face.
  TextStyle heading(double fontSize) => serifHeadings
      ? GoogleFonts.gelasio(fontSize: fontSize + 2, height: 1.15, fontWeight: FontWeight.w600, color: text)
      : TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: text);

  @override
  AuthPalette copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primaryLight,
    Color? text,
    Color? muted,
    Color? subtle,
    Color? background,
    Color? surface,
    Color? border,
    Color? teal,
    Color? danger,
    Color? shadow,
  }) {
    return AuthPalette._(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryLight: primaryLight ?? this.primaryLight,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      teal: teal ?? this.teal,
      danger: danger ?? this.danger,
      shadow: shadow ?? this.shadow,
      serifHeadings: serifHeadings,
    );
  }

  @override
  AuthPalette lerp(ThemeExtension<AuthPalette>? other, double t) {
    if (other is! AuthPalette) return this;

    return AuthPalette._(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      serifHeadings: t < 0.5 ? serifHeadings : other.serifHeadings,
    );
  }
}
