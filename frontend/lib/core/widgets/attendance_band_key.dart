import 'package:flutter/material.dart';

import '../theme/chart_palette.dart';

/// The key to attendance colours: what green, amber and red each stand for
/// (decided 2026-11-04). Shown wherever attendance bars are coloured by band.
class AttendanceBandKey extends StatelessWidget {
  const AttendanceBandKey({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final band in AttendanceBand.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: band.colour(context), borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 6),
              Text(band.label, style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
      ],
    );
  }
}
