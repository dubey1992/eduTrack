import 'package:flutter/material.dart';

import 'auth_palette.dart';

/// One line of the login page's feature checklist - a check mark plus a
/// short label, matching the prototype's `.points div` rows.
class FeatureItem extends StatelessWidget {
  const FeatureItem({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 18, color: palette.teal),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 15, color: palette.text)),
        ],
      ),
    );
  }
}
