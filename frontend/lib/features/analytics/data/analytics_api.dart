import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/analytics_series.dart';
import 'models/early_warning.dart';

final analyticsApiProvider = Provider<AnalyticsApi>((ref) => AnalyticsApi(ref.watch(dioClientProvider)));

class AnalyticsApi {
  AnalyticsApi(this._dio);

  final Dio _dio;

  Future<List<AnalyticsMeasure>> measures() async {
    final response = await _dio.get('/analytics/measures');
    final data = (response.data as Map<String, dynamic>)['data'] as List<dynamic>;

    return data.map((json) => AnalyticsMeasure.fromJson(json as Map<String, dynamic>)).toList();
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
    final response = await _dio.get(
      '/analytics/series',
      queryParameters: {
        'measure': measure,
        'interval': interval.apiValue,
        'school_id': ?schoolId,
        'from': ?from,
        'to': ?to,
        'class_section_id': ?classSectionId,
        'department_id': ?departmentId,
      },
    );

    return AnalyticsSeries.fromJson(response.data as Map<String, dynamic>);
  }

  Future<EarlyWarningPage> earlyWarning({
    int? schoolId,
    int? classSectionId,
    EarlyWarningLevel? level,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _dio.get(
      '/analytics/early-warning',
      queryParameters: {
        'school_id': ?schoolId,
        'class_section_id': ?classSectionId,
        'level': ?level?.apiValue,
        'page': page,
        'per_page': perPage,
      },
    );

    return EarlyWarningPage.fromJson(response.data as Map<String, dynamic>);
  }
}
