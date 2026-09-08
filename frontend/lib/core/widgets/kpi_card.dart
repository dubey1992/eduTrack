import 'package:flutter/material.dart';

/// Small bordered stat box - muted label over a bold value - matching the
/// prototype's `.kpi` component. Used on dashboard-style screens (Payment
/// Dashboard now, others as later phases add their own KPI rows).
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
