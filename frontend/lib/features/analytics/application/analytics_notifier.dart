import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analytics_repository.dart';
import '../data/models/academic_overview.dart';
import '../data/models/finance_overview.dart';
import '../data/models/transport_overview.dart';
import '../data/models/analytics_series.dart';
import '../data/models/early_warning.dart';

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
final analyticsMeasuresProvider = FutureProvider.autoDispose<List<AnalyticsMeasure>>((ref) {
  _keep(ref);
  return ref.watch(analyticsRepositoryProvider).measures();
}, retry: (retryCount, error) => null);

/// Figures fetched for the dashboard or the Analytics page are kept for
/// the session rather than dropped the moment nobody is looking. Coming back
/// then shows them at once, and the screen re-reads them in place - Riverpod
/// keeps the old value on screen while a kept provider refreshes - instead
/// of loading from nothing. Loading from nothing grew the dashboard's trend
/// cards and banner a moment after arriving, pushing the page around under
/// somebody's scroll. Cleared on sign-out (AuthNotifier), so the next person
/// on the browser never sees them.
void _keep(Ref ref) => ref.keepAlive();

final analyticsSeriesProvider = FutureProvider.autoDispose.family<AnalyticsSeries, AnalyticsQuery>((ref, query) {
  _keep(ref);
  return ref
      .watch(analyticsRepositoryProvider)
      .series(query.measure, interval: query.interval, schoolId: query.schoolId, from: query.from, to: query.to);
}, retry: (retryCount, error) => null);

/// What the early-warning list is asking for (A3).
class EarlyWarningQuery {
  const EarlyWarningQuery({this.schoolId, this.level, this.page = 1, this.perPage = 20});

  final int? schoolId;

  /// Null for every flagged student.
  final EarlyWarningLevel? level;
  final int page;
  final int perPage;

  EarlyWarningQuery copyWith({int? page, int? perPage}) =>
      EarlyWarningQuery(schoolId: schoolId, level: level, page: page ?? this.page, perPage: perPage ?? this.perPage);

  @override
  bool operator ==(Object other) {
    return other is EarlyWarningQuery &&
        other.schoolId == schoolId &&
        other.level == level &&
        other.page == page &&
        other.perPage == perPage;
  }

  @override
  int get hashCode => Object.hash(schoolId, level, page, perPage);
}

final earlyWarningProvider = FutureProvider.autoDispose.family<EarlyWarningPage, EarlyWarningQuery>((ref, query) {
  _keep(ref);
  return ref
      .watch(analyticsRepositoryProvider)
      .earlyWarning(schoolId: query.schoolId, level: query.level, page: query.page, perPage: query.perPage);
}, retry: (retryCount, error) => null);

/// Which school's year the "Subjects & classes" view shows (A4). A null
/// year is the school's current one.
typedef AcademicQuery = ({int? schoolId, int? academicYearId});

final academicOverviewProvider = FutureProvider.autoDispose.family<AcademicOverview, AcademicQuery>((ref, query) {
  return ref
      .watch(analyticsRepositoryProvider)
      .academic(schoolId: query.schoolId, academicYearId: query.academicYearId);
}, retry: (retryCount, error) => null);

/// Which school's fee money the Finance view shows (A5): the last twelve
/// months unless a range is given.
typedef FinanceQuery = ({int? schoolId, String? from, String? to});

final financeOverviewProvider = FutureProvider.autoDispose.family<FinanceOverview, FinanceQuery>((ref, query) {
  return ref.watch(analyticsRepositoryProvider).finance(schoolId: query.schoolId, from: query.from, to: query.to);
}, retry: (retryCount, error) => null);

/// Each route of a school, the last twelve months (A6).
final transportOverviewProvider = FutureProvider.autoDispose.family<TransportOverview, int?>((ref, schoolId) {
  return ref.watch(analyticsRepositoryProvider).transport(schoolId: schoolId);
}, retry: (retryCount, error) => null);
