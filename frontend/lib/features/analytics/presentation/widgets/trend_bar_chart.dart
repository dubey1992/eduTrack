import 'package:flutter/material.dart';

/// One bar: the period it stands for, its value (null for a gap) and the
/// value as a person reads it.
class TrendBar {
  const TrendBar({required this.label, required this.value, required this.valueLabel});

  final String label;
  final double? value;
  final String valueLabel;
}

/// A bar per week or month (docs/analytics.md, A2).
///
/// Plain widgets rather than a charting package, like the dashboard's
/// attendance trend: a row of proportional bars is what Flutter already
/// does well. A gap - a holiday week, a period before the first recording -
/// is a hairline and a dash, never a bar of nought.
class TrendBarChart extends StatelessWidget {
  const TrendBarChart({super.key, required this.bars, required this.maxValue, this.height = 200, this.compact = false});

  final List<TrendBar> bars;

  /// The top of the scale: 100 for a percentage, the largest value
  /// otherwise.
  final double maxValue;
  final double height;

  /// The dashboard's small version: no figure above each bar - the card
  /// states the latest one - so the bars can be narrow.
  final bool compact;

  /// Narrower than this and the labels stop being readable, so the chart
  /// scrolls sideways instead - a year of weeks on a phone.
  static const _minBarWidth = 52.0;
  static const _minCompactBarWidth = 24.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = compact ? _minCompactBarWidth : _minBarWidth;
        final fits = constraints.maxWidth / bars.length >= minWidth;
        final row = SizedBox(
          height: height,
          width: fits ? constraints.maxWidth : bars.length * minWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bar in bars)
                Expanded(
                  child: _Bar(bar: bar, maxValue: maxValue, compact: compact),
                ),
            ],
          ),
        );

        if (fits) return row;

        // Opens at the latest periods, which are the ones being asked about.
        return SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: row);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.bar, required this.maxValue, required this.compact});

  final TrendBar bar;
  final double maxValue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = bar.value;

    return Semantics(
      label: '${bar.label}: ${bar.valueLabel}',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!compact) ...[
              Text(
                bar.valueLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: value == null ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final share = value == null || maxValue <= 0 ? 0.0 : value / maxValue;

                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: value == null ? 2 : (constraints.maxHeight * share).clamp(2, constraints.maxHeight),
                      decoration: BoxDecoration(
                        color: value == null ? scheme.outlineVariant : scheme.primary,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              bar.label,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
