import 'package:flutter/material.dart';

import '../../../marketing/presentation/marketing_colors.dart';

/// One line of the login page's feature checklist - a check mark plus a
/// short label, matching the prototype's `.points div` rows.
class FeatureItem extends StatelessWidget {
  const FeatureItem({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 18, color: MarketingColors.teal),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 15, color: MarketingColors.text)),
        ],
      ),
    );
  }
}
