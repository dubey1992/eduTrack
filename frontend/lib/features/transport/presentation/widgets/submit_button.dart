import 'package:flutter/material.dart';

/// The dialogs' primary button: disabled with a spinner while a request is
/// in flight (duplicate-submission guard), the label otherwise.
class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.isSubmitting, required this.onPressed, required this.label});

  final bool isSubmitting;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isSubmitting ? null : onPressed,
      child: isSubmitting
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label),
    );
  }
}
