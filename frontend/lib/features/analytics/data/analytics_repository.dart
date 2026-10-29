import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'analytics_api.dart';
import 'models/analytics_series.dart';

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
}
