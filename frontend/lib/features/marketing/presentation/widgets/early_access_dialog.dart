import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../marketing_colors.dart';

/// Custom confirmation dialog for every "Join Early Access" CTA on the page.
/// There's no lead-capture backend yet (the source prototype stubs this with
/// a JS alert) - this keeps the same "not wired up yet" honesty but as the
/// app's own dialog UI rather than a browser alert.
///
/// Dialogs render through the Navigator's overlay, not as a descendant of
/// MarketingScreen's widget subtree, so they don't inherit its
/// DefaultTextStyle - the Inter font is applied explicitly here instead.
Future<void> showEarlyAccessDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Thanks for your interest!', style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
      content: Text(
        "We're not accepting early-access sign-ups just yet, but we'll let you know the moment we are.",
        style: GoogleFonts.poppins(),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(backgroundColor: MarketingColors.primary),
          child: Text('Got it', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
