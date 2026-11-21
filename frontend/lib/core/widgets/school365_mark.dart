import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/brand_tokens.dart';

/// The School365AI mark: the S drawn as an open book under a cap (2026-11-21),
/// as in the website's header and the favicon.
class School365Mark extends StatelessWidget {
  const School365Mark({super.key, this.size = 40});

  /// The mark's height; it is a little narrower than it is tall.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BrandAssets.mark,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'School365AI',
    );
  }
}

/// The logo with an optional line under it.
///
/// On a light ground it is the logo itself. On a dark one - the sidebar,
/// the sign-in panel - the logo's navy "School" would vanish, so it is the
/// mark beside the name set in white, with "365" and "AI" in the logo's
/// teal and violet. [onDark] asks for that look whatever the theme.
class School365Wordmark extends StatelessWidget {
  const School365Wordmark({super.key, this.markSize = 40, this.fontSize = 20, this.onDark = false, this.tagline});

  final double markSize;
  final double fontSize;
  final bool onDark;

  /// A line under the name, such as "Smarter Schools. Brighter Futures."
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    final taglineColour = dark ? Colors.white.withValues(alpha: 0.72) : BrandColors.muted;

    final Widget logo = dark
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              School365Mark(size: markSize),
              SizedBox(width: markSize / 5),
              Flexible(child: _DarkName(fontSize: fontSize)),
            ],
          )
        : Image.asset(
            BrandAssets.logo,
            height: markSize,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            filterQuality: FilterQuality.medium,
            semanticLabel: 'School365AI',
          );

    if (tagline == null) return logo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 4),
        Text(
          tagline!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmSans(fontSize: fontSize * 0.55, color: taglineColour),
        ),
      ],
    );
  }
}

/// "School365AI" for a dark ground, coloured as the logo is.
class _DarkName extends StatelessWidget {
  const _DarkName({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final name = GoogleFonts.manrope(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'School',
            style: name.copyWith(color: Colors.white),
          ),
          TextSpan(
            text: '365',
            style: name.copyWith(color: BrandColors.logoTealOnDark),
          ),
          TextSpan(
            text: 'AI',
            style: name.copyWith(color: BrandColors.logoVioletOnDark),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
