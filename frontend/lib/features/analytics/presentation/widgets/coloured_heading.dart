import 'package:flutter/material.dart';

import '../../../../core/theme/chart_palette.dart';

/// A section title led by its icon on the section's own colour - the
/// Analytics page's share of the colourful dashboard (decided 2026-11-04).
class ColouredHeading extends StatelessWidget {
  const ColouredHeading({super.key, required this.title, required this.hue, required this.icon});

  final String title;
  final ChartHue hue;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: hue.soft(context), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: hue.strong(context)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      ],
    );
  }
}
