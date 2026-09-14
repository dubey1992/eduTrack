import 'package:flutter/material.dart';

import '../../data/models/dashboard.dart';

/// A small bar chart of attendance over the last working days.
///
/// Drawn with plain widgets rather than a charting package: it is a row of
/// proportional bars, which Flutter already does well, and a dependency that
/// exists to draw seven rectangles would be a poor trade.
///
/// A day with no register is drawn as an empty slot with a dash, never as a
/// zero bar - nobody was absent, nobody was counted.
class AttendanceTrendChart extends StatelessWidget {
  const AttendanceTrendChart({super.key, required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (points.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No attendance has been recorded yet.')),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance, recent working days', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Weekends and holidays are left out - they are not days anyone was due in.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(child: _Bar(point: point)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.point});

  final TrendPoint point;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rate = point.attendanceRate;
    // Below 75% is the figure a head teacher is looking for.
    final poor = rate != null && rate < 75;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            rate == null ? '-' : '${rate.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: rate == null ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  // A day with no register gets a hairline, not a bar: an
                  // empty column would read as nobody having turned up.
                  height: rate == null ? 2 : (constraints.maxHeight * (rate / 100)).clamp(2, constraints.maxHeight),
                  decoration: BoxDecoration(
                    color: rate == null
                        ? scheme.outlineVariant
                        : (poor ? scheme.error : scheme.primary),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            point.label,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
