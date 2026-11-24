import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/family_learning.dart';

/// A subject's tests as a line, oldest to newest, on a 0-100% scale, with
/// the school's "weak below" mark dashed across it (docs/mobile-apps-review.md,
/// M8, 8.2). Absent tests are left out - absent is not nought.
///
/// Shown only with two scored tests or more: one point is not a trend.
class MarksTrend extends StatelessWidget {
  const MarksTrend({super.key, required this.tests, required this.weakBelow});

  final List<TestResult> tests;
  final double weakBelow;

  /// The scored tests in the order they were sat, as percentages.
  static List<double> pointsOf(List<TestResult> tests) {
    final scored = [
      for (final test in tests)
        if (!test.isAbsent && double.tryParse(test.percentage ?? '') != null) test,
    ]..sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));

    return [for (final test in scored) double.parse(test.percentage!).clamp(0, 100).toDouble()];
  }

  @override
  Widget build(BuildContext context) {
    final points = pointsOf(tests);
    if (points.length < 2) return const SizedBox.shrink();

    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final rising = points.last >= points.first;
    final l10n = context.l10n;

    return Semantics(
      label: rising
          ? l10n.familyTrendRisingLabel(points.length, points.first.round(), points.last.round())
          : l10n.familyTrendFallingLabel(points.length, points.first.round(), points.last.round()),
      excludeSemantics: true,
      child: Padding(
        key: const Key('family-marks-trend'),
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 72,
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendPainter(
                  points: points,
                  weakBelow: weakBelow,
                  line: scheme.primary,
                  weakLine: colors.danger,
                  grid: scheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.familyTrendLine(points.length, points.first.round(), points.last.round()),
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.weakBelow,
    required this.line,
    required this.weakLine,
    required this.grid,
  });

  final List<double> points;
  final double weakBelow;
  final Color line;
  final Color weakLine;
  final Color grid;

  static const _dot = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Room for the dots at the edges.
    final left = _dot;
    final right = size.width - _dot;
    final top = _dot;
    final bottom = size.height - _dot;
    double yOf(double percent) => bottom - (bottom - top) * percent / 100;
    double xOf(int index) => left + (right - left) * index / (points.length - 1);

    // The floor of the scale, faintly.
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), Paint()..color = grid);

    // The school's "weak below" line, dashed.
    final weakPaint = Paint()
      ..color = weakLine.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final weakY = yOf(weakBelow.clamp(0, 100).toDouble());
    for (var x = left; x < right; x += 8) {
      canvas.drawLine(Offset(x, weakY), Offset((x + 4).clamp(left, right).toDouble(), weakY), weakPaint);
    }

    final path = ui.Path()..moveTo(xOf(0), yOf(points[0]));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(xOf(i), yOf(points[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(Offset(xOf(i), yOf(points[i])), _dot, Paint()..color = points[i] < weakBelow ? weakLine : line);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.points != points || old.weakBelow != weakBelow || old.line != line;
}
