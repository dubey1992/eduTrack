/// Analytics, A1 (docs/analytics.md): one figure week by week or month by
/// month, as `GET /analytics/series` sends it.
///
/// Each point is what the matching report says for that period. A point
/// with no value is a gap - a week of holidays, or a period from before the
/// school's figures were first recorded - and is drawn as one, never as 0.
library;

enum AnalyticsUnit {
  percent,
  count,
  money;

  static AnalyticsUnit fromApi(String value) =>
      AnalyticsUnit.values.firstWhere((unit) => unit.name == value, orElse: () => AnalyticsUnit.count);
}

enum AnalyticsInterval {
  week,
  month;

  String get apiValue => name;
}

/// One entry in the measure picker: what this person may chart.
class AnalyticsMeasure {
  const AnalyticsMeasure({required this.key, required this.label, required this.unit, required this.snapshot});

  factory AnalyticsMeasure.fromJson(Map<String, dynamic> json) {
    return AnalyticsMeasure(
      key: json['key'] as String,
      label: json['label'] as String,
      unit: AnalyticsUnit.fromApi(json['unit'] as String),
      snapshot: json['snapshot'] as bool? ?? false,
    );
  }

  final String key;
  final String label;
  final AnalyticsUnit unit;

  /// Recorded nightly rather than counted from history, so it has no
  /// figures from before the school's first recording.
  final bool snapshot;
}

/// One currency's amount. Exact, as the server sent it - money is never
/// added across currencies, so a point holds one of these per currency.
class AnalyticsAmount {
  const AnalyticsAmount({required this.currencyCode, required this.amount});

  factory AnalyticsAmount.fromJson(Map<String, dynamic> json) {
    return AnalyticsAmount(currencyCode: json['currency_code'] as String, amount: json['amount'] as String);
  }

  final String currencyCode;
  final String amount;
}

class AnalyticsPoint {
  const AnalyticsPoint({required this.from, required this.to, required this.workingDays, this.value, this.amounts});

  factory AnalyticsPoint.fromJson(Map<String, dynamic> json) {
    final amounts = json['amounts'] as List<dynamic>?;

    return AnalyticsPoint(
      from: json['from'] as String,
      to: json['to'] as String,
      workingDays: json['working_days'] as int? ?? 0,
      value: (json['value'] as num?)?.toDouble(),
      amounts: amounts?.map((line) => AnalyticsAmount.fromJson(line as Map<String, dynamic>)).toList(),
    );
  }

  /// ISO dates, the period's first and last day.
  final String from;
  final String to;
  final int workingDays;

  /// A percentage or a count; null for a gap.
  final double? value;

  /// For a money measure: one line per currency; null for a gap.
  final List<AnalyticsAmount>? amounts;

  bool get isGap => value == null && amounts == null;
}

class AnalyticsSeries {
  const AnalyticsSeries({
    required this.measure,
    required this.label,
    required this.unit,
    required this.interval,
    required this.from,
    required this.to,
    required this.points,
  });

  factory AnalyticsSeries.fromJson(Map<String, dynamic> json) {
    return AnalyticsSeries(
      measure: json['measure'] as String,
      label: json['label'] as String,
      unit: AnalyticsUnit.fromApi(json['unit'] as String),
      interval: json['interval'] == 'week' ? AnalyticsInterval.week : AnalyticsInterval.month,
      from: json['from'] as String,
      to: json['to'] as String,
      points: (json['points'] as List<dynamic>)
          .map((point) => AnalyticsPoint.fromJson(point as Map<String, dynamic>))
          .toList(),
    );
  }

  final String measure;
  final String label;
  final AnalyticsUnit unit;
  final AnalyticsInterval interval;
  final String from;
  final String to;
  final List<AnalyticsPoint> points;

  /// Every currency that appears anywhere in the series, in order - one
  /// line on a money chart each.
  List<String> get currencies {
    final seen = <String>{};
    for (final point in points) {
      for (final line in point.amounts ?? const <AnalyticsAmount>[]) {
        seen.add(line.currencyCode);
      }
    }

    return seen.toList()..sort();
  }

  /// Whether there is anything to draw at all.
  bool get isEmpty => points.every((point) => point.isGap);
}
