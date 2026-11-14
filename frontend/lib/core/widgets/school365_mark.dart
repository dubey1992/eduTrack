import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/brand_tokens.dart';

/// The School365ai mark: a white mortarboard on the rose-to-coral circle,
/// as in the website's header and the favicon (2026-11-14).
class School365Mark extends StatelessWidget {
  const School365Mark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: BrandColors.markGradient,
        boxShadow: [
          BoxShadow(
            color: BrandColors.rose.withValues(alpha: 0.28),
            blurRadius: size / 3,
            offset: Offset(0, size / 12),
          ),
        ],
      ),
      child: Icon(Icons.school, color: Colors.white, size: size * 0.55),
    );
  }
}

/// The mark and the name beside it, "ai" in the accent - the website's
/// wordmark. [onDark] for a plum ground (the sidebar, the login panel).
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
    final nameColour = dark ? Colors.white : BrandColors.plum;
    final aiColour = dark ? BrandColors.coral : BrandColors.rose;
    final taglineColour = dark ? Colors.white.withValues(alpha: 0.72) : BrandColors.muted;
    final name = GoogleFonts.dmSans(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        School365Mark(size: markSize),
        SizedBox(width: markSize / 4),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'School365',
                      style: name.copyWith(color: nameColour),
                    ),
                    TextSpan(
                      text: 'ai',
                      style: name.copyWith(color: aiColour),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (tagline != null)
                Text(
                  tagline!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: fontSize * 0.55, color: taglineColour),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
