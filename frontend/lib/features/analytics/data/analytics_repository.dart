import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'analytics_api.dart';
import 'models/academic_overview.dart';
import 'models/finance_overview.dart';
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
}
