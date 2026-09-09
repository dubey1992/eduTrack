import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'models/hod_department_report.dart';

final hodReportApiProvider = Provider<HodReportApi>((ref) => HodReportApi(ref.watch(dioClientProvider)));

class HodReportApi {
  HodReportApi(this._dio);

  final Dio _dio;

  Future<HodDepartmentReport> departmentReport({
    int? schoolId,
    int? departmentId,
    required String month,
    required int page,
    required int perPage,
  }) async {
    final response = await _dio.get(
      '/hod/department-report',
      queryParameters: {
        'school_id': ?schoolId,
        'department_id': ?departmentId,
        'month': month,
        'page': page,
        'per_page': perPage,
      },
    );
    return HodDepartmentReport.fromJson(response.data as Map<String, dynamic>);
  }
}
