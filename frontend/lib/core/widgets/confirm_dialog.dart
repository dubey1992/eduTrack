import 'package:flutter/material.dart';

/// Asks before doing something the person cannot simply undo.
///
/// Returns true only if they actually chose to go ahead - dismissing the
/// dialog by tapping outside it or pressing Escape counts as "no", which is
/// the safe reading of "I did not answer".
///
/// The app's own dialog, never the browser's `confirm()`: that one cannot be
/// styled, says "127.0.0.1 says" above the message, and looks like something
/// has gone wrong with the page.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDestructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
