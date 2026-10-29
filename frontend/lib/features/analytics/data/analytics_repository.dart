import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'analytics_api.dart';
import 'models/academic_overview.dart';
import 'models/finance_overview.dart';
import 'models/platform_overview.dart';
import 'models/transport_overview.dart';
import 'models/analytics_series.dart';
import 'models/early_warning.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => AnalyticsRepository(ref.watch(analyticsApiProvider)),
);

class AnalyticsRepository {
  AnalyticsRepository(this._api);

  final AnalyticsApi _api;

  Future<List<AnalyticsMeasure>> measures() async {
    try {
      return await _api.measures();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AnalyticsSeries> series(
    String measure, {
    AnalyticsInterval interval = AnalyticsInterval.month,
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
  }) async {
    try {
      return await _api.series(
        measure,
        interval: interval,
        schoolId: schoolId,
        from: from,
        to: to,
        classSectionId: classSectionId,
        departmentId: departmentId,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<EarlyWarningPage> earlyWarning({
    int? schoolId,
    int? classSectionId,
    EarlyWarningLevel? level,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      return await _api.earlyWarning(
        schoolId: schoolId,
        classSectionId: classSectionId,
        level: level,
        page: page,
        perPage: perPage,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<AcademicOverview> academic({int? schoolId, int? academicYearId}) async {
    try {
      return await _api.academic(schoolId: schoolId, academicYearId: academicYearId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<FinanceOverview> finance({int? schoolId, String? from, String? to}) async {
    try {
      return await _api.finance(schoolId: schoolId, from: from, to: to);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<TransportOverview> transport({int? schoolId}) async {
    try {
      return await _api.transport(schoolId: schoolId);
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<PlatformSchool>> platformSchools(PlatformSchoolsQuery query) async {
    try {
      return await _api.platformSchools(
        page: query.page,
        perPage: query.perPage,
        q: query.q.isEmpty ? null : query.q,
        category: query.category,
      );
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PlatformOverview> platform() async {
    try {
      return await _api.platform();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }
}

/// One page of the per-school list on Platform analytics.
class PlatformSchoolsQuery {
  const PlatformSchoolsQuery({this.page = 1, this.perPage = 20, this.q = '', this.category});

  final int page;
  final int perPage;
  final String q;

  /// A [SchoolCategory] api value, or null for every category.
  final String? category;

  PlatformSchoolsQuery copyWith({int? page, int? perPage, String? q, String? category, bool changeCategory = false}) {
    return PlatformSchoolsQuery(
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      q: q ?? this.q,
      category: changeCategory ? category : this.category,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlatformSchoolsQuery &&
      other.page == page &&
      other.perPage == perPage &&
      other.q == q &&
      other.category == category;

  @override
  int get hashCode => Object.hash(page, perPage, q, category);
}
