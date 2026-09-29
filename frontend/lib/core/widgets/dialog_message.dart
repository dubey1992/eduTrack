import 'package:flutter/material.dart';

/// The message inside an alert dialog, held to a readable width.
///
/// An [AlertDialog] takes its width from its content, and a bare [Text] is
/// happy to lay a long sentence out on a single line - so one sentence
/// stretched the dialog most of the way across a desktop window, and the
/// same alert looked different on every page depending on how long its
/// message happened to be.
///
/// Capping the message fixes both: it wraps at a comfortable reading
/// measure, and every alert in the app comes out the same shape. The cap is
/// a maximum, so a short message still makes a small dialog and a narrow
/// phone screen still decides for itself.
class DialogMessage extends StatelessWidget {
  const DialogMessage(this.message, {super.key, this.style});

  final String message;
  final TextStyle? style;

  /// Around 60 characters a line, which is where running text reads most
  /// comfortably.
  static const double maxWidth = 420;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Text(message, style: style),
    );
  }
}
