import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/chart_palette.dart';
import '../../data/models/dashboard.dart';

/// A ring split into its parts, with the headline figure in the middle and a
/// legend beside it (decided 2026-11-04) - today's students, today's staff,
/// fees collected.
///
/// Painted by hand, like the dashboard's bar charts: a ring of a few arcs is
/// a short CustomPainter, and not worth a charting package.
class BreakdownRingCard extends StatelessWidget {
  const BreakdownRingCard({super.key, required this.breakdown});

  static const double width = 420;
  static const double ringSize = 124;

  final DashboardBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = breakdown.total;
    final parts = [
      for (final segment in breakdown.segments) (segment: segment, colour: segmentColour(context, segment.key)),
    ];

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(breakdown.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox.square(
                    dimension: ringSize,
                    child: CustomPaint(
                      painter: _RingPainter(
                        values: [for (final part in parts) part.segment.value],
                        colours: [for (final part in parts) part.colour],
                        track: scheme.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                child: Text(
                                  breakdown.headline,
                                  key: Key('ring-headline-${breakdown.key}'),
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                                ),
                              ),
                              Text(
                                breakdown.caption,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, height: 1.2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final part in parts)
                          _LegendRow(
                            label: part.segment.label,
                            display: part.segment.display,
                            share: total > 0 ? part.segment.value / total : 0,
                            colour: part.colour,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What each part means decides its colour, so "Absent" is the same red on
  /// every ring and "not marked yet" is always the quiet grey.
  static Color segmentColour(BuildContext context, String key) {
    final colours = context.appColors;

    return switch (key) {
      'present' || 'collected' => colours.success,
      'half_day' => ChartPalette.teal.strong(context),
      'absent' => colours.danger,
      'leave' => ChartPalette.violet.strong(context),
      'outstanding' => colours.warning,
      _ => Theme.of(context).colorScheme.outlineVariant,
    };
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.label, required this.display, required this.share, required this.colour});

  final String label;
  final String display;
  final double share;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 6),
          // The figure is never cut short; a long label gives way first.
          Text(display, maxLines: 1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          SizedBox(
            width: 40,
            child: Text(
              '${(share * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.values, required this.colours, required this.track});

  final List<double> values;
  final List<Color> colours;
  final Color track;

  static const double stroke = 16;

  /// The gap between two parts, in radians, so neighbours never blur.
  static const double gap = 0.04;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // The empty ring underneath, which is all there is when nothing counts.
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);

    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;

    final shown = values.where((value) => value > 0).length;
    var start = -math.pi / 2;

    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;

      final sweep = values[i] / total * math.pi * 2;
      // One part alone is a full circle; with several, each gives up a sliver.
      final drawn = shown > 1 ? math.max(sweep - gap, 0.001) : sweep;
      canvas.drawArc(rect, start + (shown > 1 ? gap / 2 : 0), drawn, false, paint..color = colours[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.track != track || !_same(old.values, values) || !_same(old.colours, colours);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
