import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analytics_repository.dart';
import '../data/models/analytics_series.dart';

/// What the analytics screen is currently charting (docs/analytics.md, A2).
///
/// One value, so one provider covers every measure: switching measure,
/// interval, school or range is a new query, not new state to manage.
class AnalyticsQuery {
  const AnalyticsQuery({
    required this.measure,
    this.interval = AnalyticsInterval.month,
    this.schoolId,
    this.from,
    this.to,
  });

  final String measure;
  final AnalyticsInterval interval;
  final int? schoolId;

  /// ISO dates; both null means the server's default, the last twelve
  /// periods.
  final String? from;
  final String? to;

  @override
  bool operator ==(Object other) {
    return other is AnalyticsQuery &&
        other.measure == measure &&
        other.interval == interval &&
        other.schoolId == schoolId &&
        other.from == from &&
        other.to == to;
  }

  @override
  int get hashCode => Object.hash(measure, interval, schoolId, from, to);
}

/// What this person may chart. The same for every school they can see, so
/// it is asked once.
///
/// No automatic retry here or below: a 403 is an answer, not a blip.
final analyticsMeasuresProvider = FutureProvider.autoDispose<List<AnalyticsMeasure>>(
  (ref) => ref.watch(analyticsRepositoryProvider).measures(),
  retry: (retryCount, error) => null,
);

final analyticsSeriesProvider = FutureProvider.autoDispose.family<AnalyticsSeries, AnalyticsQuery>((ref, query) {
  return ref
      .watch(analyticsRepositoryProvider)
      .series(query.measure, interval: query.interval, schoolId: query.schoolId, from: query.from, to: query.to);
}, retry: (retryCount, error) => null);
