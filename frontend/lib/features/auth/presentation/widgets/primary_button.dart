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

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: palette.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
