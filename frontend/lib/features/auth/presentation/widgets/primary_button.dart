import 'package:flutter/material.dart';

import 'auth_palette.dart';

/// The login card's full-width "Sign In" action - built on a plain
/// [ElevatedButton] (matching every other primary action in the app, and
/// what the existing login widget tests already find via
/// `find.widgetWithText(ElevatedButton, 'Sign In')`) with a loading spinner
/// swapped in for [isLoading], and the public palette's blue instead of the
/// admin app's monochrome theme (see [AuthPalette]).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.isLoading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return ConstrainedBox(
      // A minimum, not a fixed height: the label grows with large text (M11, 3.4).
      constraints: const BoxConstraints(minHeight: 50, minWidth: double.infinity),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          disabledBackgroundColor: palette.primary,
          // The theme's bold text face: a bare TextStyle would ask for a
          // weight of the font that was never loaded.
          textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: palette.onPrimary),
              )
            : Text(label),
      ),
    );
  }
}
