import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../data/models/analytics_series.dart';

/// One line of figures to chart: the series itself, or for money one
/// currency of it. Money is never added across currencies, so a money
/// series becomes one of these per currency.
class SeriesLine {
  const SeriesLine({required this.unit, required this.values, this.currencyCode, required this.additive});

  /// [snapshot] measures are a reading at a moment (students on roll, owed);
  /// the rest of the counts and money are flows over the period, which can
  /// be added up into a total.
  static List<SeriesLine> of(AnalyticsSeries series, {required bool snapshot}) {
    final additive = series.unit != AnalyticsUnit.percent && !snapshot;

    if (series.unit != AnalyticsUnit.money) {
      return [
        SeriesLine(unit: series.unit, values: [for (final point in series.points) point.value], additive: additive),
      ];
    }

    return [
      for (final code in series.currencies)
        SeriesLine(
          unit: series.unit,
          currencyCode: code,
          additive: additive,
          values: [
            for (final point in series.points)
              point.amounts == null
                  ? null
                  // Recorded, but nothing in this currency that period: nought.
                  : double.parse(point.amounts!.where((line) => line.currencyCode == code).firstOrNull?.amount ?? '0'),
          ],
        ),
    ];
  }

  final AnalyticsUnit unit;
  final List<double?> values;
  final String? currencyCode;
  final bool additive;

  String format(double? value) {
    if (value == null) return '-';

    return switch (unit) {
      AnalyticsUnit.percent => '${_trim(value)}%',
      AnalyticsUnit.count => NumberFormat.decimalPattern().format(value),
      AnalyticsUnit.money => formatCurrency(value, currencyCode!),
    };
  }

  /// A change from one period to the next. Percentages change by points,
  /// not by per cent of themselves.
  String formatChange(double change) {
    final sign = change > 0 ? '+' : (change < 0 ? '-' : '');
    final size = change.abs();

    return switch (unit) {
      AnalyticsUnit.percent => '$sign${_trim(size)} pts',
      _ => '$sign${format(size)}',
    };
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  /// The top of the chart's scale.
  double get scale {
    if (unit == AnalyticsUnit.percent) return 100;

    final top = values.whereType<double>().fold<double>(0, (a, b) => a > b ? a : b);
    return top;
  }
}

/// A period as a bar's label: "Sep 2026" for a month, "09/07" - the
/// Monday - for a week.
String periodLabel(AnalyticsPoint point, AnalyticsInterval interval) {
  final start = DateTime.parse(point.from);

  return interval == AnalyticsInterval.month
      ? DateFormat('MMM yyyy').format(start)
      : DateFormat('MM/dd').format(start.subtract(Duration(days: start.weekday - 1)));
}
